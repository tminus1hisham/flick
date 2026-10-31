package dev.local.flick

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.AtomicFile
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.BitSet
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.json.JSONArray
import org.json.JSONObject
import org.libtorrent4j.Priority
import org.libtorrent4j.SessionHandle
import org.libtorrent4j.SessionManager
import org.libtorrent4j.SettingsPack
import org.libtorrent4j.Sha1Hash
import org.libtorrent4j.TorrentFlags
import org.libtorrent4j.TorrentHandle
import org.libtorrent4j.swig.error_code
import org.libtorrent4j.swig.libtorrent
import org.libtorrent4j.swig.settings_pack

/**
 * One torrent. Every TorrentHandle call happens under `synchronized(this)` after checking [alive], and
 * [gen] changes whenever playback starts, stops or the torrent is removed, so stale HTTP readers stop.
 */
class Entry(val th: TorrentHandle, var dir: String, val hash: String, val magnet: String) {
    var alive = true
    var gen = 0
    var activeFile: Int? = null
    var pinned: Int? = null
    var paused = false
    var keptFile: Int? = null
    var titleJson = ""
    var keptName = ""
    var keptSize = 0L
    var keptConfigured = false
    var done = false
    val verified = BitSet()
    val conns = mutableSetOf<Conn>()
    /** Piece of the latest non-probe read, the player's bytes/s, and the absolute ms each deadline was set for. */
    var reader = 0
    var rate = DEFAULT_RATE
    val due = mutableMapOf<Int, Long>()

    fun closeConns() {
        conns.forEach(Conn::cancel)
        conns.clear()
    }

    /** Forgets had and passed deadlines, then sets new ones ahead of [reader]. Under the lock, alive and streaming. */
    fun reschedule() {
        val ti = th.torrentFile() ?: return
        val file = activeFile ?: return
        val last = pieceRange(ti.files().fileOffset(file), ti.files().fileSize(file), ti.pieceLength()).last
        val now = System.currentTimeMillis()
        // One call into libtorrent for the whole bitfield instead of one havePiece per piece.
        val have = th.status(TorrentHandle.QUERY_PIECES).pieces()
        due.keys.removeAll { it < reader || have.getBit(it) }
        for ((p, ms) in schedule(reader, last, ti.pieceLength(), rate, now, have::getBit, due)) {
            th.setPieceDeadline(p, ms)
            due[p] = now + ms
        }
    }

    companion object {
        const val DEFAULT_RATE = 1L shl 20
    }
}

/** MethodChannel "flick/torrent". ctl serializes calls and delayed removals; replies answer once.
 * Live hashes share an entry; release stops playback and keeps unkept torrents warm for 60 seconds.
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
    private var restored = false
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
            entries.keys.toList().forEach { remove(it, preserveKept = true) }
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
                val intent = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                // A TV usually has no browser; the caller then shows the URL instead.
                if (intent.resolveActivity(context.packageManager) == null) return@runCatching false
                context.startActivity(intent)
                true
            }.fold({ if (it) result.success(null) else result.error("noHandler", "No app can open this link", null) },
                { result.error("external", it.message ?: it.toString(), null) })
            return
        }
        if (call.method == "tv") {
            val ui = context.getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
            result.success(ui.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
            return
        }
        // Also on the main thread: the buffering panel polls it while a torrent call may be slow.
        if (call.method == "online") {
            val cm = context.getSystemService(ConnectivityManager::class.java)
            result.success(cm.getNetworkCapabilities(cm.activeNetwork)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true)
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
            "keep" -> keep(id!!, call.argument<Int>("file")!!, call.argument<String>("titleJson")!!)
            "resumeKept" -> resumeKept()
            "status" -> entries[id]?.let { e -> synchronized(e) { if (e.alive) status(e) else null } }
            "files" -> entries[id]?.let { e -> synchronized(e) { if (e.alive) files(e) else null } } ?: emptyList<Any>()
            "stream" -> stream(entries[id] ?: error("torrent was removed"), id!!, call.argument<Int>("file")!!)
            // The channel cannot encode Unit, so these answer null explicitly.
            "stopStream" -> { entries[id]?.let(::stop); null }
            "release" -> { release(id!!); null }
            "bitrate" -> {
                entries[id]?.let { e ->
                    synchronized(e) {
                        if (e.alive) {
                            e.rate = maxOf(call.argument<Number>("bytesPerSec")!!.toLong(), 256L shl 10)
                            if (e.activeFile != null) e.reschedule()
                        }
                    }
                }
                null
            }
            "remove" -> {
                val e = entries[id]
                val protected = e != null && synchronized(e) {
                    e.alive && (e.pinned != null || (e.keptFile != null && call.argument<Boolean>("unlessKept") == true))
                }
                if (!protected) remove(id!!)
                null
            }
            "download" -> { download(entries[id] ?: error("torrent was removed"), id!!, call.argument<Int>("file")!!); null }
            "progress" -> entries[id]?.let { e -> synchronized(e) { if (e.alive) progress(e) else null } }
            "pause" -> { entries[id]?.let { e -> setPaused(e, true) }; null }
            "resume" -> { entries[id]?.let { e -> setPaused(e, false) }; null }
            "delete" -> { delete(id!!); null }
            else -> throw IllegalArgumentException("unknown method ${call.method}")
        }
    }

    private fun engine(): SessionManager = session ?: SessionManager().also {
        // Only streaming sessions are disposable. Kept data is always under filesDir.
        File(context.cacheDir, "flick-torrents").listFiles()?.forEach { f -> f.deleteRecursively() }
        it.start()
        // stop() ignores every piece, which makes a torrent "finished", and libtorrent then drops its seeds as
        // redundant and won't redial them for 60 s (min_reconnect_time). Keep them, so reusing the torrent (a
        // reopen, or the next episode of a season pack) starts at once instead of a minute later.
        it.applySettings(SettingsPack().setBoolean(settings_pack.bool_types.close_redundant_connections.swigValue(), false))
        session = it
        timer.scheduleWithFixedDelay({ ctl.execute(::tick) }, 1, 1, TimeUnit.SECONDS)
    }

    private fun add(magnet: String, dir: String): Int {
        val ec = error_code()
        val p = libtorrent.parse_magnet_uri(magnet, ec)
        if (ec.value() != 0) throw IllegalArgumentException(ec.message())
        val hash = Sha1Hash(p.getInfo_hashes().getV1()).toHex().lowercase()
        for ((id, e) in entries) {
            val same = synchronized(e) {
                e.alive && hash != "0".repeat(40) && e.hash == hash
            }
            if (same) {
                releases.remove(id)?.cancel(false)
                // delete() only removes an empty directory; never delete the live entry's data.
                if (File(dir).canonicalPath != File(e.dir).canonicalPath) File(dir).delete()
                return id
            }
        }
        val sm = engine()
        File(dir).mkdirs()
        p.setSave_path(dir)
        // Nothing downloads until a file is picked.
        p.setFlags(p.getFlags().or_(TorrentFlags.DEFAULT_DONT_DOWNLOAD).or_(TorrentFlags.DUPLICATE_IS_ERROR))
        val th = TorrentHandle(sm.swig().add_torrent(p, ec))
        if (ec.value() != 0) throw IllegalStateException(ec.message())
        val e = Entry(th, dir, hash, magnet)
        synchronized(e) {
            check(e.alive) { "torrent was removed" }
            e.th.unsetFlags(TorrentFlags.AUTO_MANAGED)
            e.th.resume()
        }
        val id = nextId.getAndIncrement()
        entries[id] = e
        return id
    }

    private fun keptDir(hash: String): File {
        require(Regex("[0-9a-f]{40}").matches(hash) && hash != "0".repeat(40)) { "a v1 info-hash is required" }
        return File(context.filesDir, "downloads/torrents/$hash")
    }

    private fun dataFile(e: Entry): File? {
        if (e.keptName.isEmpty()) return null
        val root = File(e.dir).canonicalFile
        val file = File(root, e.keptName).canonicalFile
        require(file.path.startsWith(root.path + File.separator)) { "invalid torrent file path" }
        return file
    }

    private fun keptRecord(id: Int, e: Entry): Map<String, Any> = mapOf(
        "id" to id, "infoHash" to e.hash, "magnet" to e.magnet,
        "file" to e.keptFile!!, "dir" to e.dir, "titleJson" to e.titleJson,
        "name" to e.keptName, "size" to e.keptSize, "done" to e.done)

    private fun persistKept() {
        val records = JSONArray()
        for ((id, e) in entries) {
            synchronized(e) {
                if (e.alive && e.keptFile != null) records.put(JSONObject(keptRecord(id, e)))
            }
        }
        val file = AtomicFile(File(context.filesDir, "torrent-downloads.json"))
        val out = file.startWrite()
        try {
            out.write(records.toString().toByteArray(Charsets.UTF_8))
            file.finishWrite(out)
        } catch (t: Throwable) {
            file.failWrite(out)
            throw t
        }
    }

    private fun keep(id: Int, file: Int, titleJson: String): Map<String, Any> {
        val e = entries[id] ?: error("torrent was removed")
        return synchronized(e) {
            check(e.alive) { "torrent was removed" }
            require(e.pinned == null) { "This torrent is already registered in Downloads" }
            JSONObject(titleJson)
            val ti = e.th.torrentFile() ?: error("metadata not ready")
            val fs = ti.files()
            require(file in 0 until fs.numFiles() && !fs.padFileAt(file)) { "no file $file" }
            require(e.keptFile == null || e.keptFile == file) {
                "Another file from this torrent is already saved. Delete it in Downloads before choosing another."
            }
            require(e.activeFile == null) { "Stop playback before downloading this torrent" }
            val dir = keptDir(e.hash)
            dir.mkdirs()
            e.keptName = fs.filePath(file)
            e.keptSize = fs.fileSize(file)
            val previousDir = e.dir
            e.dir = dir.path
            try {
                dataFile(e)
            } catch (t: Throwable) {
                e.dir = previousDir
                throw t
            }
            if (File(previousDir).canonicalPath != dir.canonicalPath) e.th.moveStorage(dir.path)
            releases.remove(id)?.cancel(false)
            e.keptFile = file
            e.titleJson = titleJson
            e.keptConfigured = false
            configureKept(e)
            persistKept()
            keptRecord(id, e)
        }
    }

    private fun resumeKept(): List<Map<String, Any>> {
        if (!restored) {
            val file = AtomicFile(File(context.filesDir, "torrent-downloads.json"))
            val text = try {
                file.openRead().bufferedReader(Charsets.UTF_8).use { it.readText() }
            } catch (_: java.io.FileNotFoundException) {
                "[]"
            }
            val records = JSONArray(text)
            for (n in 0 until records.length()) {
                val r = records.getJSONObject(n)
                val hash = r.getString("infoHash")
                val dir = keptDir(hash)
                require(File(r.getString("dir")).canonicalPath == dir.canonicalPath) { "invalid download directory" }
                val title = r.getString("titleJson")
                JSONObject(title)
                val id = add(r.getString("magnet"), dir.path)
                val e = entries[id]!!
                synchronized(e) {
                    check(e.alive) { "torrent was removed" }
                    require(e.hash == hash) { "download info-hash mismatch" }
                    val selected = r.getInt("file")
                    require(selected >= 0 && (e.keptFile == null || e.keptFile == selected)) { "conflicting download file" }
                    if (File(e.dir).canonicalPath != dir.canonicalPath) {
                        e.th.moveStorage(dir.path)
                        e.dir = dir.path
                    }
                    e.keptFile = selected
                    e.titleJson = title
                    e.keptName = r.getString("name")
                    e.keptSize = r.getLong("size")
                    e.done = r.getBoolean("done")
                    dataFile(e)
                    e.keptConfigured = false
                    configureKept(e)
                }
            }
            restored = true
        }
        return entries.mapNotNull { (id, e) ->
            synchronized(e) { if (e.alive && e.keptFile != null) keptRecord(id, e) else null }
        }
    }

    /** Under the entry lock on ctl. Metadata can arrive after resumeKept has returned. */
    private fun configureKept(e: Entry) {
        val file = e.keptFile ?: return
        if (e.done) {
            e.th.pause()
            return
        }
        if (e.keptConfigured) return
        val ti = e.th.torrentFile() ?: return
        val fs = ti.files()
        require(file in 0 until fs.numFiles() && !fs.padFileAt(file)) { "no file $file" }
        require(fs.filePath(file) == e.keptName && fs.fileSize(file) == e.keptSize) { "download file changed" }
        e.th.clearPieceDeadlines()
        e.due.clear()
        // Reset streaming piece priorities before applying the single selected file.
        e.th.prioritizePieces(Array(ti.numPieces()) { Priority.DEFAULT })
        e.th.prioritizeFiles(Array(fs.numFiles()) { if (it == file) Priority.DEFAULT else Priority.IGNORE })
        e.th.setFlags(TorrentFlags.SEQUENTIAL_DOWNLOAD)
        e.th.resume()
        e.keptConfigured = true
    }

    private fun keptBytes(e: Entry): Long {
        val file = e.keptFile ?: return 0
        configureKept(e)
        val local = dataFile(e)
        if (e.done) return if (local?.isFile == true && local.length() == e.keptSize) e.keptSize else 0
        if (!e.keptConfigured) return 0
        val bytes = e.th.fileProgress().getOrNull(file) ?: 0
        if (e.keptSize > 0 && bytes >= e.keptSize && local?.isFile == true && local.length() == e.keptSize) {
            e.th.pause()
            e.done = true
            persistKept()
        }
        return bytes
    }

    private fun status(e: Entry): Map<String, Any?> {
        val downloaded = if (e.keptFile != null) keptBytes(e) else 0L
        val s = e.th.status()
        val err = s.errorCode()
        val complete = e.done && e.keptSize > 0 && downloaded >= e.keptSize
        return mapOf(
            // status().name() is empty unless libtorrent is asked to query it; the metadata has it.
            "name" to (e.th.torrentFile()?.name() ?: e.keptName), "peers" to s.numPeers(), "rate" to s.downloadRate(),
            "hasMetadata" to s.hasMetadata(),
            "error" to when {
                e.done && !complete -> "Downloaded file is missing"
                err.isError -> err.message
                else -> null
            },
            "downloaded" to downloaded, "total" to e.keptSize, "done" to complete,
            "path" to if (complete) dataFile(e)?.path else null)
    }

    private fun files(e: Entry): List<Map<String, Any>> {
        val fs = e.th.torrentFile()?.files() ?: return emptyList()
        return (0 until fs.numFiles()).filterNot(fs::padFileAt).map {
            mapOf("index" to it, "name" to fs.filePath(it), "size" to fs.fileSize(it))
        }
    }

    private fun stream(e: Entry, id: Int, file: Int): String {
        synchronized(e) {
            check(e.alive) { "torrent was removed" }
            if (e.keptFile != null) {
                require(e.keptFile == file) { "Another file from this torrent is saved in Downloads" }
                keptBytes(e)
                check(e.done && dataFile(e)?.isFile == true) { "This torrent is downloading. Play it from Downloads when it is ready." }
                return dataFile(e)!!.path
            }
        }
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
                e.th.resume()
                val wanted = pieceRange(fs.fileOffset(file), fs.fileSize(file), ti.pieceLength())
                e.th.setFlags(TorrentFlags.SEQUENTIAL_DOWNLOAD)
                // The window covers the head mpv reads first; the last piece holds MKV cues or an MP4 moov,
                // which mpv probes at startup. The player reports the real bitrate once it knows the duration.
                e.th.clearPieceDeadlines()
                e.due.clear()
                e.rate = Entry.DEFAULT_RATE
                e.reader = wanted.first
                e.reschedule()
                if (!e.th.havePiece(wanted.last)) {
                    e.th.setPieceDeadline(wanted.last, 0)
                    e.due[wanted.last] = System.currentTimeMillis()
                }
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
            if (e.keptFile != null) {
                configureKept(e)
            } else {
                e.th.clearPieceDeadlines()
                e.due.clear()
                want(e)
            }
        }
    }

    private fun tick() {
        runCatching { downloadTick() }.onFailure { Log.w("torrent", "download tick failed", it) }
        for (e in entries.values) {
            try {
                synchronized(e) {
                    if (e.alive) {
                        if (e.keptFile != null) keptBytes(e)
                        if (e.activeFile != null) e.reschedule()
                    }
                }
            } catch (t: Exception) {
                Log.w("torrent", "torrent tick failed", t) // an uncaught throw on ctl would kill the app
            }
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
            require(file in 0 until ti.files().numFiles() && !ti.files().padFileAt(file)) { "no file $file" }
            require(e.keptFile == null) { "This torrent is already saved in Downloads" }
            require(e.pinned == null || e.pinned == file) { "Delete the existing download before choosing another file from this torrent" }
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
                if (e.activeFile == null) e.th.pause() // no seeding
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
        require(isUnder(File(e.dir), File(context.filesDir, "downloads"))) { "invalid download directory" }
        e.pinned = null
        remove(id)
        File(e.dir).deleteRecursively()
        tick()
    }

    /** Runs the foreground service while a download is running, and refreshes its notification. */
    private fun downloadTick() {
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
        if (synchronized(e) { !e.alive || e.keptFile != null || e.pinned != null }) return
        lateinit var pending: ScheduledFuture<*>
        pending = timer.schedule({
            ctl.execute {
                if (releases[id] === pending && synchronized(e) { e.alive && e.keptFile == null && e.pinned == null }) remove(id)
            }
        }, 60, TimeUnit.SECONDS)
        releases[id] = pending
    }

    private fun remove(id: Int, preserveKept: Boolean = false) {
        releases.remove(id)?.cancel(false)
        val e = entries[id] ?: return
        var kept = false
        synchronized(e) {
            if (!e.alive) return
            kept = e.keptFile != null
            if (kept && !preserveKept) {
                e.keptFile = null
                try {
                    persistKept()
                } catch (t: Throwable) {
                    e.keptFile = keptFileFromDisk(id)
                    throw t
                }
            }
            e.th.pause()
            if ((kept || e.pinned != null) && preserveKept) session?.remove(e.th)
            else session?.remove(e.th, SessionHandle.DELETE_FILES)
            e.alive = false
            e.gen++
            e.closeConns()
        }
        entries.remove(id)
        if (kept && !preserveKept) File(e.dir).deleteRecursively()
    }

    private fun keptFileFromDisk(id: Int): Int? {
        val file = AtomicFile(File(context.filesDir, "torrent-downloads.json"))
        val records = JSONArray(file.openRead().bufferedReader(Charsets.UTF_8).use { it.readText() })
        for (n in 0 until records.length()) {
            val r = records.getJSONObject(n)
            if (r.getInt("id") == id) return r.getInt("file")
        }
        return null
    }

    private companion object {
        const val NOTIFY_REQUEST = 7301
    }
}
