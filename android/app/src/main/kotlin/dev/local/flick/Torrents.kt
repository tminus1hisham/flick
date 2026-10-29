package dev.local.flick

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.BitSet
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.libtorrent4j.Priority
import org.libtorrent4j.SessionHandle
import org.libtorrent4j.SessionManager
import org.libtorrent4j.Sha1Hash
import org.libtorrent4j.TorrentFlags
import org.libtorrent4j.TorrentHandle
import org.libtorrent4j.swig.error_code
import org.libtorrent4j.swig.libtorrent

/**
 * One torrent. Every TorrentHandle call happens under `synchronized(this)` after checking [alive], and
 * [gen] changes whenever playback starts, stops or the torrent is removed, so stale HTTP readers stop.
 */
class Entry(val th: TorrentHandle, @Volatile var dir: String) {
    var alive = true
    var gen = 0
    var activeFile: Int? = null
    /** The file being downloaded for offline use. A pinned entry outlives release; only delete removes it. */
    var pinned: Int? = null
    var paused = false
    var done = false
    val verified = BitSet()
    val conns = mutableSetOf<Conn>()

    fun closeConns() {
        conns.forEach(Conn::cancel)
        conns.clear()
    }
}

/** MethodChannel "flick/torrent". ctl serializes calls and delayed removals; replies answer once.
 * Live hashes share an entry; release stops playback and keeps it warm for 60 seconds.
 */
class Torrents : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val ctl = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private val releases = mutableMapOf<Int, ScheduledFuture<*>>()
    private val main = Handler(Looper.getMainLooper())
    private val entries = ConcurrentHashMap<Int, Entry>()
    private val nextId = AtomicInteger(1)
    private var session: SessionManager? = null
    private var server: StreamServer? = null
    private var ticker: ScheduledFuture<*>? = null
    private var serviceOn = false
    private var activity: ActivityPluginBinding? = null
    private var permission: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "flick/torrent")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        timer.shutdownNow()
        ctl.execute {
            server?.close()
            // Downloads keep their files: Dart re-adds them on the next launch and libtorrent rechecks the data.
            entries.forEach { (id, e) -> remove(id, files = e.pinned == null) }
            session?.stop()
            if (serviceOn) context.stopService(Intent(context, DownloadService::class.java))
        }
        ctl.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity?.removeRequestPermissionsResultListener(this)
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray): Boolean {
        if (code != NOTIFY_REQUEST) return false
        permission?.success(results.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        permission = null
        return true
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33) return result.success(true)
        val granted = context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val a = activity?.activity
        // One prompt at a time; a second caller gets the current answer.
        if (granted || a == null || permission != null) return result.success(granted)
        permission = result
        a.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFY_REQUEST)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // On the main thread, so opening a link never waits behind a slow torrent call.
        if (call.method == "openExternal") {
            runCatching {
                val uri = Uri.parse(call.argument<String>("url")!!)
                require(uri.scheme?.lowercase() in listOf("http", "https")) { "only http/https URLs are allowed" }
                context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }.fold({ result.success(null) }, { result.error("external", it.message ?: it.toString(), null) })
            return
        }
        if (call.method == "requestNotifications") return requestNotifications(result)
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
            "release" -> { release(id!!); null }
            // A pinned entry is the user's download: leaving the player must not delete it.
            "remove" -> { entries[id]?.let { e -> if (e.pinned != null) stop(e) else remove(id!!) }; null }
            "download" -> { download(entries[id] ?: error("torrent was removed"), id!!, call.argument<Int>("file")!!); null }
            "progress" -> entries[id]?.let { e -> synchronized(e) { if (e.alive) progress(e) else null } }
            "pause" -> { entries[id]?.let { e -> setPaused(e, true) }; null }
            "resume" -> { entries[id]?.let { e -> setPaused(e, false) }; null }
            "delete" -> { delete(id!!); null }
            else -> throw IllegalArgumentException("unknown method ${call.method}")
        }
    }

    private fun add(magnet: String, dir: String): Int {
        val sm = session ?: SessionManager().also {
            // No native torrent exists before this session, so streaming session directories are leftovers
            // from a killed process. Swept here, not in Dart: a hot restart resets Dart but not this plugin.
            // Only the streaming root, never the passed dir's parent: that may hold the user's downloads.
            leftovers(File(context.cacheDir, "flick-torrents"), File(dir)).forEach { f -> f.deleteRecursively() }
            it.start()
            session = it
        }
        val ec = error_code()
        val p = libtorrent.parse_magnet_uri(magnet, ec)
        if (ec.value() != 0) throw IllegalArgumentException(ec.message())
        val hash = Sha1Hash(p.getInfo_hashes().getV1()).toHex().lowercase()
        for ((id, e) in entries) {
            val same = synchronized(e) {
                e.alive && hash != "0".repeat(40) && e.th.infoHash().toHex().lowercase() == hash
            }
            if (same) {
                releases.remove(id)?.cancel(false)
                // delete() only removes an empty directory; never delete the live entry's data.
                if (File(dir).canonicalPath != File(e.dir).canonicalPath) File(dir).delete()
                return id
            }
        }
        p.setSave_path(dir)
        // Nothing downloads until a file is picked.
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
                want(e)
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
            e.th.unsetFlags(TorrentFlags.SEQUENTIAL_DOWNLOAD)
            want(e) // a pinned file keeps downloading
        }
    }

    /** Real priorities for every file, so boundary pieces land in real files (not libtorrent's part file) and
     * can be hash-verified; piece priorities then limit the download to the played and the pinned file. */
    private fun want(e: Entry) {
        val ti = e.th.torrentFile() ?: return
        val fs = ti.files()
        e.th.prioritizeFiles(Array(fs.numFiles()) { Priority.DEFAULT })
        val wanted = listOfNotNull(e.activeFile, e.pinned).map { pieceRange(fs.fileOffset(it), fs.fileSize(it), ti.pieceLength()) }
        e.th.prioritizePieces(Array(ti.numPieces()) { p -> if (wanted.any { p in it }) Priority.DEFAULT else Priority.IGNORE })
    }

    private fun download(e: Entry, id: Int, file: Int) {
        releases.remove(id)?.cancel(false)
        synchronized(e) {
            check(e.alive) { "torrent was removed" }
            val ti = e.th.torrentFile() ?: error("metadata not ready")
            require(file in 0 until ti.files().numFiles()) { "no file $file" }
            // A hash already live from streaming sits in the cache, which Android may clear.
            val root = File(context.filesDir, "downloads")
            if (!isUnder(File(e.dir), root)) {
                val to = File(root, e.th.infoHash().toHex().lowercase()).path
                e.th.moveStorage(to)
                e.dir = to
            }
            if (e.pinned != file) e.done = false
            e.pinned = file
            want(e)
        }
        if (ticker == null) ticker = timer.scheduleWithFixedDelay({ ctl.execute(::tick) }, 2, 2, TimeUnit.SECONDS)
        tick()
    }

    private fun progress(e: Entry): Map<String, Any?> {
        val s = e.th.status()
        val err = s.errorCode()
        val ti = e.th.torrentFile()
        val file = e.pinned
        var bytes = 0L
        var total = 0L
        var path: String? = null
        if (ti != null && file != null) {
            val fs = ti.files()
            total = fs.fileSize(file)
            bytes = e.th.fileProgress()[file]
            path = fs.filePath(file, e.dir)
            // Done needs every piece verified and the move into downloads finished, so path is final.
            if (!e.done && bytes == total && File(e.th.savePath()).canonicalPath == File(e.dir).canonicalPath &&
                pieceRange(fs.fileOffset(file), total, ti.pieceLength()).all(e.th::havePiece)) {
                e.done = true
                e.th.pause() // no seeding
            }
        }
        val state = when {
            e.done -> "done"
            err.isError -> "error"
            e.paused -> "paused"
            else -> "downloading"
        }
        return mapOf("bytes" to bytes, "total" to total, "rate" to s.downloadRate(), "peers" to s.numPeers(),
            "state" to state, "error" to if (err.isError) err.message else null, "path" to path)
    }

    private fun setPaused(e: Entry, paused: Boolean) {
        synchronized(e) {
            if (!e.alive || e.done) return // a done torrent stays paused
            e.paused = paused
            if (paused) e.th.pause() else e.th.resume()
        }
        tick()
    }

    private fun delete(id: Int) {
        val e = entries[id] ?: return
        remove(id)
        File(e.dir).deleteRecursively()
        tick()
    }

    /** Runs the foreground service while a download is running, and refreshes its notification. */
    private fun tick() {
        val running = entries.values.mapNotNull { e ->
            synchronized(e) { if (e.alive && e.pinned != null) progress(e) else null }
        }.filter { it["state"] != "done" && it["state"] != "paused" }
        val intent = Intent(context, DownloadService::class.java)
        if (running.isEmpty()) {
            if (serviceOn) context.stopService(intent)
            serviceOn = false
            return
        }
        val total = running.sumOf { it["total"] as Long }
        val percent = if (total > 0) (running.sumOf { it["bytes"] as Long } * 100 / total).toInt() else 0
        if (!serviceOn) {
            intent.putExtra("count", running.size).putExtra("percent", percent)
            // Android 12+ refuses to start a foreground service from the background; the next tick retries.
            serviceOn = runCatching {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            }.isSuccess
        }
        if (serviceOn) DownloadService.show(context, running.size, percent)
    }

    private fun release(id: Int) {
        val e = entries[id] ?: return
        stop(e)
        releases.remove(id)?.cancel(false)
        if (e.pinned != null) return
        lateinit var pending: ScheduledFuture<*>
        pending = timer.schedule({
            ctl.execute {
                if (releases[id] === pending) remove(id)
            }
        }, 60, TimeUnit.SECONDS)
        releases[id] = pending
    }

    private fun remove(id: Int, files: Boolean = true) {
        releases.remove(id)?.cancel(false)
        val e = entries.remove(id) ?: return
        synchronized(e) {
            e.alive = false
            e.gen++
            e.closeConns()
        }
        if (files) session?.remove(e.th, SessionHandle.DELETE_FILES) else session?.remove(e.th)
    }

    private companion object {
        const val NOTIFY_REQUEST = 7301
    }
}
