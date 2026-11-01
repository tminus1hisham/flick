package dev.local.flick

import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.IOException
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.net.URLDecoder
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.Executors
import kotlin.concurrent.thread
import kotlin.io.encoding.Base64

private fun queryValues(url: String) = URI(url).rawQuery.orEmpty().split('&').filter(String::isNotEmpty).associate {
    val pair = it.split('=', limit = 2)
    URLDecoder.decode(pair[0], "UTF-8") to URLDecoder.decode(pair.getOrElse(1) { "" }, "UTF-8")
}

private fun bruDecode(raw: String): String {
    require(raw.length in 9..16384)
    val text = URLDecoder.decode(raw.drop(8), "UTF-8").map {
        when (it) { in 'a'..'z' -> 'a' + (it - 'a' + 13) % 26; in 'A'..'Z' -> 'A' + (it - 'A' + 13) % 26; else -> it }
    }.joinToString("")
    return String(Base64.decode(text), Charsets.UTF_8).trim()
}

/** The provider's bundled AS/ID fallback also accepts worldwide CDN entries. */
internal fun fctvCdnCandidates(url: String, salt: String): List<String> {
    val query = queryValues(url)
    if (query["_ctump"] == null || query["_ctuph"] == null || query["_ctutt"] == null) return emptyList()
    val path = bruDecode(query.getValue("_ctuph"))
    require(path.startsWith('/') && !path.startsWith("//") && '#' !in path)
    return bruDecode(query.getValue("_ctump")).split(',').take(16).mapNotNull { item ->
        val parts = item.trim().split('@', limit = 2)
        require(parts.size == 2)
        if (parts[0].substringBefore(':').trim() !in listOf("AS", "AS-ID", "WW")) return@mapNotNull null
        val domain = parts[1].trim()
        require(domain.matches(Regex("[A-Za-z0-9.-]+")) && '.' in domain)
        val target = fctvUrl("https://$domain$path")
        val version = queryValues(target)["_ver"].orEmpty()
        val name = URI(target).path.substringAfterLast('/')
        val signature = MessageDigest.getInstance("MD5").digest("$name,$version,$salt".toByteArray()).joinToString("") { "%02x".format(it) }
        target + (if (URI(target).rawQuery == null) "?" else "&") + "_s2=$signature"
    }.distinct()
}

internal fun fctvRewritePlaylist(base: String, text: String, local: (String) -> String): String {
    require(text.trimStart('\uFEFF', ' ', '\n', '\r').startsWith("#EXTM3U"))
    return text.lineSequence().joinToString("\n") { raw ->
        val line = raw.trim()
        fun link(value: String) = local(fctvUrl(URI(base).resolve(value).toString()))
        when {
            line.isEmpty() -> ""
            !line.startsWith('#') -> link(line)
            else -> Regex("URI=\"([^\"]+)\"").replace(line) { "URI=\"${link(it.groupValues[1])}\"" }
        }
    }
}

internal fun fctvMediaConnection(url: String): HttpURLConnection {
    val uri = URI(fctvUrl(url))
    require(uri.rawFragment == null)
    require(InetAddress.getAllByName(uri.host).all {
        !it.isAnyLocalAddress && !it.isLoopbackAddress && !it.isLinkLocalAddress && !it.isSiteLocalAddress && !it.isMulticastAddress &&
            !(it.address.size == 16 && (it.address[0].toInt() and 254) == 252)
    }) { "Invalid media host" }
    return uri.toURL().openConnection() as HttpURLConnection
}

internal data class FctvResource(val url: String, val status: Int, val bytes: ByteArray, val type: String, val range: String?)

/** Only registered playlist resources are exposed on this session's loopback URL. */
internal class FctvMedia(
    private val root: String,
    private val headers: Map<String, String>,
    private val salt: String,
    private val cdnEnabled: Boolean,
    private val connect: (String) -> HttpURLConnection = ::fctvMediaConnection,
) : Closeable {
    private val server = ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))
    private val token = UUID.randomUUID().toString()
    private val pool = ThreadPoolExecutor(4, 4, 0, TimeUnit.SECONDS, SynchronousQueue<Runnable>())
    private val clients = ConcurrentHashMap<Socket, Long>()
    private val watchdog = Executors.newSingleThreadScheduledExecutor()
    private val upstream = ConcurrentHashMap.newKeySet<HttpURLConnection>()
    private val resources = object : LinkedHashMap<String, String>(128, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String>?) = size > 4096
    }
    @Volatile private var closed = false
    val url = local(root)

    init {
        watchdog.scheduleWithFixedDelay({
            val now = System.nanoTime()
            clients.forEach { (socket, progress) ->
                if (now - progress > TimeUnit.SECONDS.toNanos(30)) runCatching { socket.close() }
            }
        }, 5, 5, TimeUnit.SECONDS)
        thread(isDaemon = true, name = "live-http") {
            while (!closed) {
                val client = try { server.accept() } catch (_: IOException) { break }
                clients[client] = System.nanoTime()
                try {
                    pool.execute {
                        client.use {
                            try { serve(client) } catch (_: Exception) {
                                runCatching { client.getOutputStream().write("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray()) }
                            } finally { clients.remove(client) }
                        }
                    }
                } catch (_: java.util.concurrent.RejectedExecutionException) { clients.remove(client); client.close() }
            }
        }
    }

    private fun local(target: String): String {
        fctvUrl(target)
        val id = MessageDigest.getInstance("SHA-256").digest(target.toByteArray()).joinToString("") { "%02x".format(it) }
        val extension = URI(target).path.substringAfterLast('.', "bin").takeIf { it.matches(Regex("[a-zA-Z0-9]{1,8}")) } ?: "bin"
        val key = "$id.$extension"
        synchronized(resources) { resources[key] = target }
        return "http://127.0.0.1:${server.localPort}/$token/$key"
    }

    internal fun load(url: String, range: String? = null): FctvResource {
        val cdn = if (cdnEnabled) fctvCdnCandidates(url, salt) else emptyList()
        val candidates = (if (cdn.isEmpty()) emptyList() else List(3) { cdn[it % cdn.size] }) + url
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(25)
        var failure: Exception = FctvPlaybackException("media")
        for (candidate in candidates) {
            if (closed || System.nanoTime() >= deadline) break
            try { return fetch(candidate, range, deadline) } catch (e: IOException) { failure = e }
            catch (e: FctvPlaybackException) { failure = e }
        }
        throw failure
    }

    private fun fetch(url: String, range: String?, deadline: Long): FctvResource {
        var target = url
        repeat(5) {
            check(!closed)
            if (System.nanoTime() >= deadline) throw java.net.SocketTimeoutException("Live request timed out")
            val c = connect(fctvUrl(target))
            upstream += c
            try {
                check(!closed)
                c.connectTimeout = 8000
                c.readTimeout = 8000
                c.instanceFollowRedirects = false
                val uri = URI(target)
                val sameOrigin = uri.scheme == URI(root).scheme && uri.rawAuthority == URI(root).rawAuthority
                val publicHeaders = setOf("user-agent", "origin", "referer", "accept", "accept-language", "cache-control")
                headers.filterKeys { sameOrigin || it.lowercase() in publicHeaders }.forEach { (k, v) ->
                    require(k.matches(Regex("[!#$%&'*+.^_`|~0-9A-Za-z-]+")) && '\r' !in v && '\n' !in v)
                    require(k.lowercase() !in setOf("host", "connection", "transfer-encoding", "content-length"))
                    c.setRequestProperty(k, v)
                }
                c.setRequestProperty("Accept-Encoding", "identity")
                val playlist = uri.path.endsWith(".m3u8", true)
                if (range != null && !playlist) {
                    require(range.matches(Regex("bytes=\\d*-\\d*")) && range != "bytes=-")
                    c.setRequestProperty("Range", range)
                }
                val status = c.responseCode
                if (status in listOf(301, 302, 303, 307, 308)) {
                    val next = fctvUrl(uri.resolve(c.getHeaderField("Location") ?: throw FctvPlaybackException("redirect", status)).toString())
                    require(uri.scheme != "https" || URI(next).scheme == "https")
                    target = next
                    return@repeat
                }
                if (status !in listOf(200, 206)) throw FctvPlaybackException(if (playlist) "playlist" else "media", status)
                // shortcut: buffer at most 32 MiB per resource, stream bodies if larger segments are needed.
                val limit = if (playlist) 4 * 1024 * 1024 else 32 * 1024 * 1024
                require(c.contentLengthLong <= limit)
                val bytes = c.inputStream.use { input ->
                    val out = ByteArrayOutputStream()
                    val chunk = ByteArray(8192)
                    while (true) {
                        check(!closed)
                        if (System.nanoTime() >= deadline) throw java.net.SocketTimeoutException("Live request timed out")
                        val n = input.read(chunk)
                        if (n < 0) break
                        require(out.size() + n <= limit)
                        out.write(chunk, 0, n)
                    }
                    out.toByteArray()
                }
                if (bytes.isEmpty()) throw FctvPlaybackException("empty media")
                return FctvResource(target, status, bytes, c.contentType?.substringBefore(';') ?: "application/octet-stream", c.getHeaderField("Content-Range"))
            } finally { upstream -= c; c.disconnect() }
        }
        throw FctvPlaybackException("redirect limit")
    }

    fun checkPlaylist() {
        var target = root
        repeat(4) { depth ->
            val resource = load(target)
            val text = String(resource.bytes, Charsets.UTF_8)
            if (!text.trimStart('\uFEFF', ' ', '\n', '\r').startsWith("#EXTM3U")) {
                val html = text.trimStart().startsWith('<')
                if (depth == 0 || html) throw FctvPlaybackException("playlist")
                return
            }
            for (line in text.lineSequence().filter { it.startsWith("#EXT-X-KEY:") || it.startsWith("#EXT-X-MAP:") }) {
                val child = Regex("URI=\"([^\"]+)\"").find(line)?.groupValues?.get(1) ?: continue
                val dependency = load(fctvUrl(URI(resource.url).resolve(child).toString()))
                if (line.contains("METHOD=AES-128")) require(dependency.bytes.size == 16)
            }
            val links = text.lineSequence().map(String::trim).filter { it.isNotEmpty() && !it.startsWith('#') }.toList()
            if (links.isEmpty()) throw FctvPlaybackException("empty playlist")
            val child = if (text.contains("#EXT-X-STREAM-INF:")) links.first() else links.last()
            target = fctvUrl(URI(resource.url).resolve(child).toString())
        }
        throw FctvPlaybackException("playlist depth")
    }

    private fun serve(client: Socket) {
        client.soTimeout = 10000
        val input = client.getInputStream().buffered()
        val head = StringBuilder()
        while (!head.endsWith("\r\n\r\n")) {
            val b = input.read()
            require(b >= 0 && head.length < 8192)
            head.append(b.toChar())
        }
        val lines = head.toString().split("\r\n")
        val request = lines.first().split(' ')
        require(request.size == 3 && request[0] in listOf("GET", "HEAD"))
        val path = request[1].removePrefix("/$token/")
        val target = if (request[1].startsWith("/$token/")) synchronized(resources) { resources[path] } else null
        val out = client.getOutputStream()
        if (target == null) {
            out.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray())
            return
        }
        val range = lines.drop(1).firstOrNull { it.startsWith("Range:", true) }?.substringAfter(':')?.trim()
        val resource = load(target, range)
        val playlist = String(resource.bytes.take(16).toByteArray(), Charsets.UTF_8).trimStart('\uFEFF', ' ', '\n', '\r').startsWith("#EXTM3U")
        val bytes = if (playlist) fctvRewritePlaylist(resource.url, String(resource.bytes, Charsets.UTF_8), ::local).toByteArray() else resource.bytes
        val type = if (playlist) "application/vnd.apple.mpegurl" else resource.type
        require(type.matches(Regex("[a-zA-Z0-9.+-]+/[a-zA-Z0-9.+-]+")))
        val contentRange = resource.range?.takeIf { !playlist && it.matches(Regex("bytes \\d+-\\d+/(\\d+|\\*)")) }
        val status = if (contentRange != null) "206 Partial Content" else "200 OK"
        val extra = contentRange?.let { "Content-Range: $it\r\n" }.orEmpty()
        out.write("HTTP/1.1 $status\r\nContent-Type: $type\r\nContent-Length: ${bytes.size}\r\nCache-Control: no-store\r\n${extra}Connection: close\r\n\r\n".toByteArray())
        if (request[0] == "GET") {
            var offset = 0
            while (offset < bytes.size) {
                clients[client] = System.nanoTime()
                val count = minOf(8192, bytes.size - offset)
                out.write(bytes, offset, count)
                offset += count
            }
        }
    }

    override fun close() {
        closed = true
        server.close()
        clients.keys.forEach { runCatching { it.close() } }
        upstream.forEach { it.disconnect() }
        pool.shutdownNow()
        watchdog.shutdownNow()
        synchronized(resources) { resources.clear() }
    }
}
