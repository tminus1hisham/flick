package dev.local.flick

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.BitSet
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import org.libtorrent4j.Priority
import org.libtorrent4j.SessionHandle
import org.libtorrent4j.SessionManager
import org.libtorrent4j.TorrentFlags
import org.libtorrent4j.TorrentHandle
import org.libtorrent4j.swig.error_code
import org.libtorrent4j.swig.libtorrent

/**
 * One torrent. Every TorrentHandle call happens under `synchronized(this)` after checking [alive], and
 * [gen] changes whenever playback starts, stops or the torrent is removed, so stale HTTP readers stop.
 */
class Entry(val th: TorrentHandle, val dir: String) {
    var alive = true
    var gen = 0
    var activeFile: Int? = null
    val verified = BitSet()
    val conns = mutableSetOf<Conn>()

    fun closeConns() {
        conns.forEach(Conn::cancel)
        conns.clear()
    }
}

/** MethodChannel "flick/torrent". Calls run one at a time off the main thread and answer exactly once. */
class Torrents : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val ctl = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val entries = ConcurrentHashMap<Int, Entry>()
    private val nextId = AtomicInteger(1)
    private var session: SessionManager? = null
    private var server: StreamServer? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "flick/torrent")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        ctl.execute {
            server?.close()
            entries.keys.toList().forEach(::remove)
            session?.stop()
        }
        ctl.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        ctl.execute {
            val r = runCatching { handle(call) }
            main.post {
                r.fold({ result.success(it) }, { result.error("torrent", it.message ?: it.toString(), null) })
            }
        }
    }

    private fun handle(call: MethodCall): Any? {
        val id = call.argument<Int>("id")
        return when (call.method) {
            "add" -> add(call.argument<String>("magnet")!!, call.argument<String>("dir")!!)
            "status" -> entries[id]?.let { e -> synchronized(e) { if (e.alive) status(e) else null } }
            "files" -> entries[id]?.let { e -> synchronized(e) { if (e.alive) files(e) else null } } ?: emptyList<Any>()
            "stream" -> stream(entries[id] ?: error("torrent was removed"), id!!, call.argument<Int>("file")!!)
            // The channel cannot encode Unit, so these answer null explicitly.
            "stopStream" -> { entries[id]?.let(::stop); null }
            "remove" -> { remove(id!!); null }
            else -> throw IllegalArgumentException("unknown method ${call.method}")
        }
    }

    private fun add(magnet: String, dir: String): Int {
        val sm = session ?: SessionManager().also {
            // No native torrent exists before this session, so sibling session directories are leftovers
            // from a killed process. Swept here, not in Dart: a hot restart resets Dart but not this plugin.
            File(dir).parentFile?.listFiles()?.filter { f -> f.path != File(dir).path }?.forEach { f -> f.deleteRecursively() }
            it.start()
            session = it
        }
        val ec = error_code()
        val p = libtorrent.parse_magnet_uri(magnet, ec)
        if (ec.value() != 0) throw IllegalArgumentException(ec.message())
        p.setSave_path(dir)
        // Nothing downloads until a file is picked; a re-add during a pending removal fails rather than sharing it.
        p.setFlags(p.getFlags().or_(TorrentFlags.DEFAULT_DONT_DOWNLOAD).or_(TorrentFlags.DUPLICATE_IS_ERROR))
        val th = TorrentHandle(sm.swig().add_torrent(p, ec))
        if (ec.value() != 0) throw IllegalStateException(ec.message())
        th.unsetFlags(TorrentFlags.AUTO_MANAGED)
        th.resume()
        val id = nextId.getAndIncrement()
        entries[id] = Entry(th, dir)
        return id
    }

    private fun status(e: Entry): Map<String, Any?> {
        val s = e.th.status()
        val err = s.errorCode()
        return mapOf(
            // status().name() is empty unless libtorrent is asked to query it; the metadata has it.
            "name" to (e.th.torrentFile()?.name() ?: ""), "peers" to s.numPeers(), "rate" to s.downloadRate(),
            "hasMetadata" to s.hasMetadata(), "error" to if (err.isError) err.message else null)
    }

    private fun files(e: Entry): List<Map<String, Any>> {
        val fs = e.th.torrentFile()?.files() ?: return emptyList()
        return (0 until fs.numFiles()).filterNot(fs::padFileAt).map {
            mapOf("index" to it, "name" to fs.filePath(it), "size" to fs.fileSize(it))
        }
    }

    private fun stream(e: Entry, id: Int, file: Int): String {
        // Server first: if it cannot start, nothing has been activated yet.
        val s = server ?: StreamServer { entries[it] }.also { server = it }
        try {
            synchronized(e) {
                check(e.alive) { "torrent was removed" }
                val ti = e.th.torrentFile() ?: error("metadata not ready")
                require(ti.hasV1()) { "v2-only torrents are not supported" }
                require(ti.pieceLength() <= 32 shl 20) { "piece size ${ti.pieceLength()} not supported" }
                val fs = ti.files()
                require(file in 0 until fs.numFiles()) { "no file $file" }
                e.closeConns()
                e.gen++
                e.activeFile = file
                // Real priorities for every file, so boundary pieces land in real files (not libtorrent's part
                // file) and can be hash-verified; piece priorities then limit the download to this file.
                e.th.prioritizeFiles(Array(fs.numFiles()) { Priority.DEFAULT })
                val wanted = pieceRange(fs.fileOffset(file), fs.fileSize(file), ti.pieceLength())
                e.th.prioritizePieces(Array(ti.numPieces()) { if (it in wanted) Priority.DEFAULT else Priority.IGNORE })
                e.th.setFlags(TorrentFlags.SEQUENTIAL_DOWNLOAD)
            }
        } catch (t: Throwable) {
            stop(e) // roll back a partial activation so nothing keeps downloading behind the error
            throw t
        }
        return s.url(id, file)
    }

    private fun stop(e: Entry) = synchronized(e) {
        e.gen++
        e.activeFile = null
        e.closeConns()
        if (e.alive) {
            e.th.clearPieceDeadlines()
            e.th.torrentFile()?.let { ti -> e.th.prioritizePieces(Array(ti.numPieces()) { Priority.IGNORE }) }
        }
    }

    private fun remove(id: Int) {
        val e = entries.remove(id) ?: return
        synchronized(e) {
            e.alive = false
            e.gen++
            e.closeConns()
        }
        session?.remove(e.th, SessionHandle.DELETE_FILES)
    }
}
