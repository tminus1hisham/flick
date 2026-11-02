package dev.local.flick

import android.os.Handler
import android.os.Looper
import android.os.Build
import android.util.Base64
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.TreeMap
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Only the protobuf wire types used by FCTV; unknown fields are retained or skipped. */
internal class FctvMessage(bytes: ByteArray) {
    private val fields = mutableMapOf<Int, MutableList<Any>>()
    init {
        var p = 0
        fun take(n: Int): ByteArray {
            require(n >= 0 && n <= bytes.size - p) { "Truncated message" }
            return bytes.copyOfRange(p, p + n).also { p += n }
        }
        fun varint(): Long {
            var value = 0L
            for (shift in 0..63 step 7) {
                require(p < bytes.size) { "Truncated varint" }
                val b = bytes[p++].toInt() and 255
                require(shift != 63 || b <= 1) { "Varint overflow" }
                value = value or ((b and 127).toLong() shl shift)
                if (b < 128) return value
            }
            error("Varint overflow")
        }
        while (p < bytes.size) {
            val tag = varint()
            require(tag ushr 3 in 1..536870911) { "Invalid field" }
            val value: Any = when ((tag and 7).toInt()) {
                0 -> varint()
                1 -> { take(8); continue }
                2 -> {
                    val length = varint()
                    require(length in 0..(bytes.size - p).toLong()) { "Invalid length" }
                    take(length.toInt())
                }
                5 -> { take(4); continue }
                else -> error("Unsupported wire type")
            }
            fields.getOrPut((tag ushr 3).toInt()) { mutableListOf() }.add(value)
        }
    }
    fun number(field: Int) = fields[field]?.firstOrNull()?.let { it as? Long ?: error("Invalid number field") } ?: 0L
    fun blobs(field: Int) = fields[field].orEmpty().map { it as? ByteArray ?: error("Invalid bytes field") }
    fun blob(field: Int) = blobs(field).firstOrNull() ?: byteArrayOf()
    fun text(field: Int): String = Charsets.UTF_8.newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(blob(field))).toString()
    fun messages(field: Int) = blobs(field).map(::FctvMessage)
}

internal fun fctvRot47(s: String) = s.map { if (it.code in 33..126) ((it.code - 33 + 47) % 94 + 33).toChar() else it }.joinToString("")

internal fun fctvUrl(raw: String): String {
    val decoded = if (raw.startsWith("http://") || raw.startsWith("https://")) raw else {
        require(raw.length > 8) { "Unavailable stream" }
        fctvRot47(raw).drop(8)
    }
    val uri = URI(decoded)
    require(uri.scheme in listOf("http", "https") && !uri.host.isNullOrEmpty() && uri.userInfo == null) { "Unsupported stream" }
    return decoded
}

internal fun fctvSessionUrl(url: String, session: String): String {
    val uri = URI(fctvUrl(url))
    // The app signs HTTPS relay URLs; ordinary HTTP origin streams remain direct.
    if (uri.scheme != "https" || session.isEmpty()) return url
    val cipher = Cipher.getInstance("AES/CTR/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec("a7981cc9eb2f4d19dcfea57b101ecd89".toByteArray(), "AES"),
        IvParameterSpec("8017d3a8f1400d2f".toByteArray()))
    val token = URLEncoder.encode(Base64.encodeToString(cipher.doFinal(session.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP), "UTF-8")
    return "${uri.scheme}://${uri.rawAuthority}/token-${token}a${uri.rawPath.ifEmpty { "/" }}${uri.rawQuery?.let { "?$it" } ?: ""}"
}

internal fun fctvPlaylistChild(url: String, text: String): String {
    require(text.trimStart('\uFEFF', ' ', '\n', '\r').startsWith("#EXTM3U")) { "Invalid playlist" }
    val child = text.lineSequence().map(String::trim).firstOrNull { it.isNotEmpty() && !it.startsWith('#') }
        ?: error("Empty playlist")
    return fctvUrl(URI(url).resolve(child).toString())
}

internal fun fctvApiOrigin(raw: String): String {
    val uri = URI(fctvUrl(raw))
    require(uri.scheme == "https" && uri.port == -1 && uri.rawPath in listOf("", "/") &&
        uri.rawQuery == null && uri.rawFragment == null) { "Invalid API origin" }
    // Bootstrap may migrate between these provider domains, never to local/private services.
    require(uri.host.matches(Regex("apis-data[a-z0-9-]*\\.[a-z0-9-]+\\.(ru|cfd)"))) { "Invalid API host" }
    return raw.trimEnd('/')
}

internal class FctvPlaybackException(val stage: String, val status: Int? = null) : Exception() {
    val userMessage: String get() = when {
        status in listOf(401, 403) -> "This channel's video server rejected playback (HTTP $status). Try another channel."
        status != null -> "The live $stage request failed (HTTP $status). Try again or choose another channel."
        else -> "This channel returned an unsupported live playlist. Try another channel."
    }
}

/** A direct-stream adapter, independent of FCTV's ads, WebViews and P2P engine. */
internal class Fctv(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "flick/live")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var disposed = false
    @Volatile private var connection: HttpURLConnection? = null
    private var mediaHeaders: Map<String, String>? = null
    private var cdnSalt = "00"
    private var cdnEnabled = false
    private val media = LiveMediaSession<FctvMedia>()
    private var selectionGeneration = 0
    private var base = "https://apis-data10.tcpwe138stya.ru"
    private var configCheckedAt = 0L
    private val userAgent = "rbapp/--dg-foth-app-323/3.0.323/android_${Build.VERSION.SDK_INT}_${Build.VERSION.RELEASE}/Flick_Android_${Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"}/UTC/en"

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "cancelPrepared") {
                synchronized(this) { selectionGeneration++; media.cancel() }
                result.success(null)
                return@setMethodCallHandler
            }
            val generation = synchronized(this) {
                if (call.method in setOf("resolve", "prepare", "stop")) selectionGeneration++
                selectionGeneration
            }
            worker.execute {
                try {
                    if (call.method !in setOf("stop", "commit")) configure()
                    val sport = call.argument<Number>("sport")?.toInt() ?: 1
                    val value: Any? = when (call.method) {
                        "stop" -> { synchronized(this) { media.close() }; null }
                        "commit" -> { synchronized(this) { media.commit(call.argument<String>("url")!!) }; null }
                        "events" -> events(sport)
                        "channels" -> channels(sport, call.argument<Number>("eventId")!!.toLong())
                        "resolve", "prepare" -> resolve(sport, call.argument<Number>("eventId")!!.toLong(),
                            call.argument<Number>("id")!!.toLong(), call.argument<Number>("site")!!.toInt(),
                            generation, call.method == "prepare")
                        else -> throw IllegalArgumentException("Unknown live operation")
                    }
                    main.post { if (!disposed) result.success(value) }
                } catch (e: Exception) {
                    Log.w("flick-live", "operation=${call.method} failure=${e.javaClass.simpleName}")
                    if (e is FctvPlaybackException) mediaHeaders = null
                    if (e is FctvPlaybackException) Log.w("flick-live", "stage=${e.stage} status=${e.status}")
                    val code = when (e) { is FctvPlaybackException -> "unsupported"; is java.io.IOException -> "unreachable"; else -> "unavailable" }
                    val message = when (code) {
                        "unsupported" -> (e as FctvPlaybackException).userMessage
                        "unreachable" -> "Could not reach the live source. Check your connection and try again."
                        else -> "This live source is unavailable or has changed."
                    }
                    val detail = if (e is FctvPlaybackException) mapOf("stage" to e.stage, "status" to e.status) else null
                    main.post { if (!disposed) result.error(code, message, detail) }
                }
            }
        }
    }

    private fun query(params: Map<String, Any>) = params.entries.joinToString("&") {
        "${URLEncoder.encode(it.key, "UTF-8")}=${URLEncoder.encode(it.value.toString(), "UTF-8")}"
    }

    private fun request(path: String, params: Map<String, Any> = emptyMap()): Pair<ByteArray, String> {
        return fetch(base + path + if (params.isEmpty()) "" else "?" + query(params), mediaHeaders.orEmpty())
    }

    private fun configure() {
        val now = System.nanoTime()
        if (mediaHeaders != null && configCheckedAt != 0L && now - configCheckedAt < TimeUnit.MINUTES.toNanos(15)) return
        configCheckedAt = now
        try {
            val url = "https://firestore.googleapis.com/v1/projects/rbapp-672ea/databases/(default)/documents/foth_APP_KVS/params_production"
            val fields = JSONObject(String(fetch(url).first, Charsets.UTF_8)).getJSONObject("fields")
            base = fctvApiOrigin(fields.getJSONObject("DATA_API").getString("stringValue"))
        } catch (_: Exception) {
            if (disposed) return
            Log.w("flick-live", "Bootstrap unavailable; retaining last API origin")
        }
        mediaHeaders = null
        headers()
    }

    private fun fetch(url: String, headers: Map<String, String> = emptyMap()): Pair<ByteArray, String> {
        check(!disposed)
        val c = URI(url).toURL().openConnection() as HttpURLConnection
        connection = c
        try {
            c.connectTimeout = 15000
            c.readTimeout = 15000
            c.instanceFollowRedirects = false
            c.setRequestProperty("User-Agent", userAgent)
            c.setRequestProperty("Origin", "https://www.rbtv77.com")
            headers.forEach { (key, value) -> c.setRequestProperty(key, value) }
            require(c.responseCode in 200..299) { "Live source rejected request" }
            require(c.contentLengthLong <= 4 * 1024 * 1024) { "Response too large" }
            val out = ByteArrayOutputStream()
            c.inputStream.use { input ->
                val chunk = ByteArray(8192)
                while (true) {
                    check(!disposed)
                    val n = input.read(chunk)
                    if (n < 0) break
                    require(out.size() + n <= 4 * 1024 * 1024) { "Response too large" }
                    out.write(chunk, 0, n)
                }
            }
            return out.toByteArray() to (c.getHeaderField("rb-session") ?: "")
        } finally {
            connection = null
            c.disconnect()
        }
    }

    private fun payload(bytes: ByteArray): FctvMessage {
        val envelope = FctvMessage(bytes)
        require(envelope.number(2) == 0L && envelope.blob(10).isNotEmpty()) { "Unavailable response" }
        return FctvMessage(envelope.blob(10))
    }

    private fun versioned(code: Int, sport: Int, event: Long? = null): FctvMessage {
        val bs = linkedMapOf<String, Any>("code" to code, "sportType" to sport, "stream" to true)
        if (event != null) bs["matchId"] = event
        val versions = payload(request("/api/common/bs", bs).first).messages(1)
        val version = versions.firstOrNull { it.number(1) == code.toLong() }?.text(2) ?: error("Missing version")
        require(version.matches(Regex("[a-zA-Z0-9_-]{1,128}")))
        val params = sortedMapOf<String, Any>("language" to 0, "sportType" to sport, "stream" to true)
        if (event != null) params["matchId"] = event
        val hash = MessageDigest.getInstance("MD5").digest(query(params).toByteArray()).joinToString("") { "%02x".format(it) }.take(6)
        return payload(request("/sfver$hash$version/api/match/${if (event == null) "live" else "detail"}", params).first)
    }

    private fun events(sport: Int): List<Map<String, Any>> {
        require(sport in listOf(1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 90))
        val data = versioned(100, sport)
        return data.messages(1).mapNotNull { event ->
            val id = event.number(1)
            if (id <= 0) return@mapNotNull null
            val name = event.text(19).ifEmpty {
                event.messages(30).firstOrNull { it.number(1) == 0L }?.text(2).orEmpty()
            }.ifEmpty { "Event $id" }
            val league = event.messages(10).firstOrNull()?.messages(3)?.let { names ->
                (names.firstOrNull { it.number(1) == 0L } ?: names.firstOrNull())?.text(2)
            }.orEmpty()
            mapOf("id" to id, "sport" to sport, "name" to name, "league" to league,
                "start" to event.number(3), "status" to event.number(4))
        }.sortedWith(compareBy<Map<String, Any>> {
            val status = it["status"] as Long
            when { status in 10..9999 -> 0; status == 0L -> 1; else -> 2 }
        }.thenBy { it["start"] as Long })
    }

    private fun channels(sport: Int, event: Long): List<Map<String, Any>> {
        require(event > 0)
        return versioned(102, sport, event).messages(2).mapNotNull { stream ->
            val id = stream.number(1)
            if (id <= 0) return@mapNotNull null
            mapOf("id" to id, "sport" to sport, "eventId" to event, "site" to stream.number(9),
                "name" to stream.text(3).ifEmpty { "Channel $id" },
                "available" to (stream.number(5) == 1L && stream.number(6) == 0L))
        }
    }

    private fun headers(): Map<String, String> {
        mediaHeaders?.let { return it }
        val config = JSONObject(fctvRot47(String(request("/api/common/params").first, Charsets.UTF_8)))
        val cdn = config.opt("common:cdnSmartLink:app") ?: config.opt("common:cdnSmartLink")
        val cdnConfig = if (cdn is String) JSONObject(cdn) else cdn as? JSONObject
        cdnSalt = cdnConfig?.optJSONObject("auth")?.optString("salt", "00") ?: "00"
        cdnEnabled = cdnConfig?.optBoolean("enable", false) == true
        val p2p = config.get("common:p2p:v3").let { if (it is String) JSONObject(it) else it as JSONObject }
        val headers = p2p.getJSONObject("basicConfig").getJSONObject("rbHeaders")
        val all = TreeMap<String, String>(String.CASE_INSENSITIVE_ORDER)
        headers.keys().forEach { all[it] = headers.getString(it) }
        val web = config.opt("common:web:client")?.let { if (it is String) JSONObject(it) else it as? JSONObject }
        val domain = web?.optJSONObject("trd")?.optJSONArray("iframePlayerDomains")?.optString(0)?.trim().orEmpty()
        if (domain.isNotEmpty()) {
            val origin = fctvUrl(if (domain.startsWith("http")) domain else "https://$domain").trimEnd('/')
            all["Referer"] = "$origin/"
            all["Origin"] = origin
        }
        all["User-Agent"] = userAgent
        require(all.all { (k, v) -> k.matches(Regex("[!#$%&'*+.^_`|~0-9A-Za-z-]+")) && !v.contains('\r') && !v.contains('\n') })
        return all.also { mediaHeaders = it }
    }

    private fun resolve(sport: Int, event: Long, id: Long, site: Int, generation: Int, prepare: Boolean): Map<String, Any> {
        require(event > 0 && id > 0 && site >= 0)
        val response = request("/api/stream/detail", mapOf("matchId" to event, "sportType" to sport,
            // Empty region fields produce placeholder streams; use the APK's bundled fallback without a location lookup.
            "streamId" to id, "siteType" to site, "continent" to "AS", "country" to "ID", "digit" to "foth", "withOriginal" to true))
        val stream = payload(response.first).messages(2).firstOrNull() ?: error("Missing stream")
        require(stream.number(5) == 1L && stream.number(6) == 0L)
        val url = fctvSessionUrl(fctvUrl(stream.text(4)), response.second)
        val supplied = stream.messages(20).associate { it.text(1) to it.text(2) }
        val all = TreeMap<String, String>(String.CASE_INSENSITIVE_ORDER).apply { putAll(headers()); putAll(supplied) }
        require(all.all { (k, v) -> k.matches(Regex("[!#$%&'*+.^_`|~0-9A-Za-z-]+")) && !v.contains('\r') && !v.contains('\n') })
        fun publish(key: String, candidate: FctvMedia?) {
            synchronized(this) {
                check(!disposed && generation == selectionGeneration) { "Live selection cancelled" }
                media.stage(key, candidate)
                if (!prepare) media.commit(key)
            }
        }
        if (!URI(url).path.endsWith(".m3u8", ignoreCase = true)) {
            publish(url, null)
            return mapOf("url" to url, "headers" to all)
        }
        val candidate = FctvMedia(url, all, cdnSalt, cdnEnabled)
        try {
            // Preflight and user cancellation leave the active broadcast untouched.
            candidate.checkPlaylist()
            publish(candidate.url, candidate)
            return mapOf("url" to candidate.url, "headers" to emptyMap<String, String>())
        } catch (e: Exception) {
            candidate.close()
            throw e
        }
    }

    fun dispose() {
        synchronized(this) {
            disposed = true
            selectionGeneration++
            media.close()
        }
        channel.setMethodCallHandler(null)
        connection?.disconnect()
        worker.shutdownNow()
    }
}
