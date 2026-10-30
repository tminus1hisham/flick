package dev.local.flick

import java.io.InputStream
import java.io.RandomAccessFile
import java.net.Socket
import java.net.SocketException
import java.net.SocketTimeoutException
import java.security.MessageDigest

/** A request's byte range against a resource, per RFC 9110 (single ranges only). */
sealed interface ByteRange {
    object Full : ByteRange
    data class Part(val start: Long, val end: Long) : ByteRange
    object Unsatisfiable : ByteRange
}

private val rangeSpec = Regex("""bytes=(\d*)-(\d*)""")

/** Absent, malformed and multi-range headers are ignored (RFC 9110 allows serving the whole file). */
fun parseRange(header: String?, size: Long): ByteRange {
    val (a, b) = header?.trim()?.let { rangeSpec.matchEntire(it) }?.destructured ?: return ByteRange.Full
    if (a.isEmpty()) {
        val n = b.toLongOrNull() ?: return ByteRange.Full // "bytes=-" or overflow
        return if (n == 0L || size == 0L) ByteRange.Unsatisfiable else ByteRange.Part(maxOf(0, size - n), size - 1)
    }
    val start = a.toLongOrNull() ?: return ByteRange.Full
    val end = if (b.isEmpty()) Long.MAX_VALUE else b.toLongOrNull() ?: Long.MAX_VALUE
    return when {
        end < start -> ByteRange.Full
        start >= size -> ByteRange.Unsatisfiable
        else -> ByteRange.Part(start, minOf(end, size - 1))
    }
}

/** Status line and headers; a HEAD response sends exactly this and no body. */
fun responseHead(range: ByteRange, size: Long, type: String): String {
    val (status, length, extra) = when (range) {
        ByteRange.Full -> Triple("200 OK", size, "")
        is ByteRange.Part -> Triple(
            "206 Partial Content", range.end - range.start + 1,
            "Content-Range: bytes ${range.start}-${range.end}/$size\r\n")
        ByteRange.Unsatisfiable -> Triple("416 Range Not Satisfiable", 0L, "Content-Range: bytes */$size\r\n")
    }
    return "HTTP/1.1 $status\r\nContent-Type: $type\r\nContent-Length: $length\r\n" +
        "Accept-Ranges: bytes\r\n${extra}Connection: close\r\n\r\n"
}

/** Where file byte [pos] lives: its piece, its offset in that piece, and how many bytes until the piece or range ends. */
data class Chunk(val piece: Int, val start: Int, val len: Int)

fun chunk(fileOffset: Long, pos: Long, end: Long, pieceLength: Int, pieceSize: (Int) -> Int): Chunk {
    val off = fileOffset + pos
    val piece = (off / pieceLength).toInt()
    val start = (off % pieceLength).toInt()
    return Chunk(piece, start, minOf(end - pos + 1, (pieceSize(piece) - start).toLong()).toInt())
}

/** Pieces overlapping a file of [size] bytes at [fileOffset] in the torrent. */
fun pieceRange(fileOffset: Long, size: Long, pieceLength: Int): IntRange =
    if (size == 0L) IntRange.EMPTY
    else (fileOffset / pieceLength).toInt()..((fileOffset + size - 1) / pieceLength).toInt()

/** Pieces to keep deadlines on ahead of the reader: 30 s of video at [rate] bytes/s, clamped to 8–64 MiB, at least 2. */
fun window(rate: Long, pieceLen: Int): Int {
    val bytes = (30 * rate).coerceIn(8L shl 20, 64L shl 20)
    return maxOf(2, ((bytes + pieceLen - 1) / pieceLen).toInt())
}

/**
 * Deadlines (piece, ms from [now]) for the pieces from [reader] to the window's end or [last] that are not had yet:
 * each is due when the player at [rate] bytes/s will reach it. libtorrent deadlines are relative to the moment they
 * are set, so a piece already in [due] (absolute ms) is returned only when its new deadline is earlier; re-setting
 * the same relative deadline every tick would postpone it forever.
 */
fun schedule(reader: Int, last: Int, pieceLen: Int, rate: Long, now: Long, have: (Int) -> Boolean,
             due: Map<Int, Long>): List<Pair<Int, Int>> =
    (reader..minOf(reader + window(rate, pieceLen), last)).filterNot(have).mapNotNull { p ->
        val ms = (1000L * (p - reader) * pieceLen / rate).toInt()
        val old = due[p]
        if (old == null || now + ms < old) p to ms else null
    }

/** A request starting at piece [start] jumps away from [reader]; requests into the last 2 pieces are tail probes. */
fun isSeek(start: Int, reader: Int, window: Int, last: Int): Boolean =
    start !in (reader - 1)..(reader + window) && start < last - 1

/** A run of piece bytes inside one file; [path] null means a pad file, which is all zeros and not on disk. */
class Slice(val path: String?, val offset: Long, val size: Long)

/** SHA-1 of the slices read from disk in 1 MiB chunks, or null if cancelled or a file is short. */
fun sha1(slices: List<Slice>, cancelled: () -> Boolean): ByteArray? {
    val md = MessageDigest.getInstance("SHA-1")
    val buf = ByteArray(1 shl 20)
    for (s in slices) {
        var left = s.size
        if (s.path == null) {
            buf.fill(0)
            while (left > 0) {
                val n = minOf(left, buf.size.toLong()).toInt()
                md.update(buf, 0, n)
                left -= n
            }
            continue
        }
        RandomAccessFile(s.path, "r").use { f ->
            f.seek(s.offset)
            while (left > 0) {
                if (cancelled()) return null
                val n = f.read(buf, 0, minOf(left, buf.size.toLong()).toInt())
                if (n < 0) return null
                md.update(buf, 0, n)
                left -= n
            }
        }
    }
    return md.digest()
}

/**
 * Whether the client has hung up, checked with a 1 ms read of [input] (the socket's stream). A byte the client sent
 * is skipped, not taken as a hang-up; only end of stream is. The socket's read timeout is restored afterwards.
 */
fun clientGone(socket: Socket, input: InputStream): Boolean {
    val timeout = socket.soTimeout
    socket.soTimeout = 1
    try {
        return input.read() < 0
    } catch (_: SocketTimeoutException) {
        return false
    } catch (_: SocketException) {
        return true // reset: the client closed with response bytes unread
    } finally {
        socket.soTimeout = timeout
    }
}

private val videoTypes = mapOf(
    "mp4" to "video/mp4", "m4v" to "video/mp4", "mkv" to "video/x-matroska", "webm" to "video/webm",
    "avi" to "video/x-msvideo", "mov" to "video/quicktime", "ts" to "video/mp2t", "m2ts" to "video/mp2t")

fun mimeOf(name: String): String = videoTypes[name.substringAfterLast('.').lowercase()] ?: "application/octet-stream"
