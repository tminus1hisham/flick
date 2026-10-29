package dev.local.flick

import android.util.Log
import java.io.BufferedInputStream
import java.io.Closeable
import java.io.IOException
import java.io.InputStream
import java.io.RandomAccessFile
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.libtorrent4j.TorrentInfo

class Cancelled : Exception()

/** One HTTP connection. Closing it unblocks a write stalled by a paused player. */
class Conn(val socket: Socket) {
    @Volatile var cancelled = false
    @Volatile var lastProgress = System.nanoTime()

    fun cancel() {
        cancelled = true
        try { socket.close() } catch (_: IOException) {}
    }
}

/**
 * Loopback HTTP server that serves torrent files while they download, like Stremio's streaming server.
 * URLs are /<torrent id>/<file index>; only the file currently being played (Entry.activeFile) is served.
 */
class StreamServer(private val lookup: (Int) -> Entry?) : Closeable {
    private val socket = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
    private val pool = ThreadPoolExecutor(4, 4, 0, TimeUnit.SECONDS, SynchronousQueue()) { r ->
        Thread(r, "torrent-http").apply { isDaemon = true }
    }
    private val conns = ConcurrentHashMap.newKeySet<Conn>()
    private val watchdog = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "torrent-http-watchdog").apply { isDaemon = true }
    }

    init {
        thread(isDaemon = true, name = "torrent-http-accept") { acceptLoop() }
        watchdog.scheduleWithFixedDelay({
            val now = System.nanoTime()
            for (c in conns) if (now - c.lastProgress > STALL_NANOS) c.cancel()
        }, 5, 5, TimeUnit.SECONDS)
    }

    fun url(id: Int, file: Int) = "http://127.0.0.1:${socket.localPort}/$id/$file"

    override fun close() {
        try { socket.close() } catch (_: IOException) {}
        watchdog.shutdownNow()
        pool.shutdownNow()
        conns.forEach { it.cancel() }
    }

    private fun acceptLoop() {
        while (!socket.isClosed) {
            val c = try { Conn(socket.accept()) } catch (_: IOException) { break }
            conns += c
            try {
                pool.execute {
                    try {
                        serve(c)
                    } catch (e: Exception) {
                        if (!c.cancelled) Log.w("torrent-http", "request failed", e)
                    } finally {
                        c.cancel()
                        conns -= c
                    }
                }
            } catch (_: RejectedExecutionException) {
                c.cancel()
                conns -= c
            }
        }
    }

    private fun serve(c: Conn) {
        c.socket.soTimeout = 10_000
        val input = BufferedInputStream(c.socket.getInputStream())
        val head = readHead(input) ?: return
        c.socket.soTimeout = 0
        val out = c.socket.getOutputStream()
        val parts = head.first().split(' ')
        val method = parts.getOrNull(0)
        if (method != "GET" && method != "HEAD") {
            out.write("HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray())
            return
        }
        val path = Regex("""/(\d+)/(\d+)""").matchEntire(parts.getOrNull(1) ?: "")
        val entry = path?.groupValues?.get(1)?.toIntOrNull()?.let(lookup)
        val file = path?.groupValues?.get(2)?.toIntOrNull()
        // Registered in entry.conns only once everything that can 404 has passed, and always paired with
        // the finally below, so rejected requests never linger in the set.
        val claim = if (entry == null || file == null) null else synchronized(entry) {
            if (!entry.alive || entry.activeFile != file) return@synchronized null
            val ti = entry.th.torrentFile() ?: return@synchronized null
            // No cancelling of other requests here: mpv probes the file's tail on a second connection while the
            // head request still waits. A waiting request ends when its own client hangs up (awaitVerified).
            entry.conns += c
            entry.gen to ti
        }
        if (entry == null || file == null || claim == null) {
            out.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray())
            return
        }
        try {
            body(c, input, entry, claim.first, claim.second, file, method, head)
        } finally {
            synchronized(entry) { entry.conns -= c }
        }
    }

    private fun body(c: Conn, input: InputStream, e: Entry, gen: Int, ti: TorrentInfo, file: Int, method: String, head: List<String>) {
        val fs = ti.files()
        val size = fs.fileSize(file)
        val fileOffset = fs.fileOffset(file)
        val range = parseRange(head.drop(1).firstOrNull { it.startsWith("range:", true) }?.substringAfter(':'), size)
        val out = c.socket.getOutputStream()
        out.write(responseHead(range, size, mimeOf(fs.fileName(file))).toByteArray())
        if (method == "HEAD") return
        val (from, to) = when (range) {
            ByteRange.Full -> 0L to size - 1
            is ByteRange.Part -> range.start to range.end
            ByteRange.Unsatisfiable -> return
        }
        val last = pieceRange(fileOffset, size, ti.pieceLength()).last
        val buf = ByteArray(1 shl 20)
        var pos = from
        var opened: RandomAccessFile? = null // libtorrent creates the file on its first write
        try {
            while (pos <= to) {
                val ch = chunk(fileOffset, pos, to, ti.pieceLength(), ti::pieceSize)
                awaitVerified(c, input, e, gen, ti, ch.piece, last)
                val raf = opened ?: RandomAccessFile(fs.filePath(file, e.dir), "r").also { opened = it }
                raf.seek(pos)
                var left = ch.len
                while (left > 0) {
                    val n = raf.read(buf, 0, minOf(left, buf.size))
                    if (n < 0) throw IOException("short read")
                    out.write(buf, 0, n)
                    c.lastProgress = System.nanoTime()
                    left -= n
                    pos += n
                }
            }
        } finally {
            opened?.close()
        }
    }

    /**
     * Blocks until piece [p] is downloaded and its bytes on disk hash to the torrent's piece hash. libtorrent can
     * report a piece before its last blocks leave the store buffer, so a downloaded piece is not yet readable.
     * Ends when the client hangs up; while it stays connected the wait counts as progress for the watchdog.
     */
    private fun awaitVerified(c: Conn, input: InputStream, e: Entry, gen: Int, ti: TorrentInfo, p: Int, last: Int) {
        val window = maxOf(4, (16 shl 20) / ti.pieceLength())
        var first = true
        var mismatches = 0
        while (true) {
            if (c.cancelled) throw Cancelled()
            val have = synchronized(e) {
                if (!e.alive || e.gen != gen) throw Cancelled()
                if (e.verified[p]) return
                if (first) {
                    for ((k, q) in (p..minOf(p + window, last)).withIndex()) {
                        if (!e.th.havePiece(q)) e.th.setPieceDeadline(q, k * 200)
                    }
                    first = false
                }
                e.th.havePiece(p)
            }
            if (have) {
                val slices = ti.mapBlock(p, 0, ti.pieceSize(p)).map {
                    Slice(if (ti.files().padFileAt(it.fileIndex())) null else ti.files().filePath(it.fileIndex(), e.dir),
                        it.offset(), it.size())
                }
                val digest = try { sha1(slices) { c.cancelled } } catch (_: IOException) { null }
                if (digest != null && digest.toHex() == ti.hashForPiece(p).toHex()) {
                    synchronized(e) { e.verified.set(p) }
                    return
                }
                if (c.cancelled) throw Cancelled()
                if (++mismatches >= 50) throw IOException("piece $p does not verify")
            }
            // Still waiting: only the client hanging up ends it, so the watchdog must not count this as a stall.
            if (clientGone(c.socket, input)) { c.cancel(); throw Cancelled() }
            c.lastProgress = System.nanoTime()
            Thread.sleep(if (have) 100 else 50)
        }
    }

    /** Request line and headers, at most 8 KiB and 64 lines; null if the client sends more or hangs up. */
    private fun readHead(input: InputStream): List<String>? {
        val lines = mutableListOf<String>()
        val line = StringBuilder()
        var total = 0
        while (true) {
            val b = input.read()
            if (b < 0 || ++total > 8192) return null
            if (b == '\n'.code) {
                val s = line.toString().trimEnd('\r')
                if (s.isEmpty()) return lines.ifEmpty { null }
                if (lines.size >= 64) return null
                lines += s
                line.clear()
            } else {
                line.append(b.toChar())
            }
        }
    }

    private companion object {
        val STALL_NANOS = TimeUnit.SECONDS.toNanos(60)
    }
}

private fun ByteArray.toHex() = joinToString("") { "%02x".format(it) }
