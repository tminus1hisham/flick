package dev.local.flick

import java.net.ServerSocket
import java.net.Socket
import java.net.InetAddress
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import java.util.TreeMap
import java.util.concurrent.ConcurrentLinkedQueue
import org.junit.Assert.*
import org.junit.Test
import kotlin.io.encoding.Base64
import kotlin.concurrent.thread

class FctvMediaTest {
    private val ts = ByteArray(376) { if (it % 188 == 0) 0x47 else 0x11 }

    private fun bru(text: String): String = "12345678" + URLEncoder.encode(Base64.encode(text.toByteArray()).map {
        when (it) { in 'a'..'z' -> 'a' + (it - 'a' + 13) % 26; in 'A'..'Z' -> 'A' + (it - 'A' + 13) % 26; else -> it }
    }.joinToString(""), "UTF-8")

    private fun source(domains: String = "WW:cf@cdn.example") = "https://relay.example/chunk.ts?" +
        mapOf("_ctump" to bru(domains), "_ctuph" to bru("/video/chunk.ts?_ver=12"), "_ctutt" to bru("3.2"))
            .entries.joinToString("&") { "${it.key}=${URLEncoder.encode(it.value, "UTF-8")}" }

    private class Request(val socket: Socket, val requestURI: URI, val requestHeaders: TreeMap<String, String>) {
        val responseHeaders = TreeMap<String, String>(String.CASE_INSENSITIVE_ORDER)
    }

    private fun reply(exchange: Request, body: ByteArray, status: Int = 200) {
        val out = exchange.socket.getOutputStream()
        val headers = exchange.responseHeaders.entries.joinToString("") { "${it.key}: ${it.value}\r\n" }
        out.write("HTTP/1.1 $status Test\r\nContent-Length: ${body.size}\r\n${headers}Connection: close\r\n\r\n".toByteArray())
        out.write(body)
    }

    private class TestServer(handler: (Request) -> Unit) {
        private val socket = ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))
        val port = socket.localPort
        private val errors = ConcurrentLinkedQueue<Throwable>()
        private val worker = thread(isDaemon = true) {
            while (!socket.isClosed) {
                val client = try { socket.accept() } catch (_: java.io.IOException) { break }
                client.use {
                    try {
                        client.soTimeout = 5000
                        val reader = client.getInputStream().bufferedReader()
                        val uri = URI(reader.readLine().split(' ')[1])
                        val headers = TreeMap<String, String>(String.CASE_INSENSITIVE_ORDER)
                        while (true) {
                            val line = reader.readLine() ?: break
                            if (line.isEmpty()) break
                            headers[line.substringBefore(':')] = line.substringAfter(':').trim()
                        }
                        handler(Request(client, uri, headers))
                    } catch (e: Throwable) { errors += e }
                }
            }
        }
        fun stop() {
            socket.close()
            worker.join(6000)
            errors.firstOrNull()?.let { throw AssertionError("Fixture server failed", it) }
        }
    }

    private fun server(handler: (Request) -> Unit) = TestServer(handler)

    private fun proxy(server: TestServer, root: String = "https://relay.example/live.m3u8", connectLog: MutableList<String> = mutableListOf()) =
        FctvMedia(root, mapOf("Authorization" to "private", "Cookie" to "private", "Referer" to "https://player.example/"), "00", true) { url ->
            connectLog += url
            val u = URI(url)
            URI("http://127.0.0.1:${server.port}${u.rawPath}${u.rawQuery?.let { "?$it" }.orEmpty()}").toURL().openConnection() as HttpURLConnection
        }

    @Test fun decodesCdnCandidatesAndFiltersOtherRegions() {
        val candidates = fctvCdnCandidates(source("EU:one@eu.example,WW:cf@cdn.example,AS:two@as.example"), "00")
        assertEquals(2, candidates.size)
        assertTrue(candidates[0].startsWith("https://cdn.example/video/chunk.ts?_ver=12&_s2="))
        assertEquals("4f5a603972875d842b37c18d90101854", candidates[0].substringAfter("_s2="))
        assertEquals(emptyList<String>(), fctvCdnCandidates("https://cdn.example/plain.ts", "00"))
        assertThrows(Exception::class.java) { fctvCdnCandidates(source("WW:cf@127.0.0.1:80"), "00") }
    }

    @Test fun rewritesVariantsAudioKeysAndInitializationResources() {
        val links = mutableListOf<String>()
        val playlist = "#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,URI=\"audio.m3u8\"\n#EXT-X-KEY:METHOD=AES-128,URI=\"/key\"\n" +
            "#EXT-X-MAP:URI=\"init.mp4\"\n#EXT-X-STREAM-INF:BANDWIDTH=100\nlow/live.m3u8\n"
        val rewritten = fctvRewritePlaylist("https://media.example/root/master.m3u8", playlist) { links += it; "http://127.0.0.1/${links.size}" }
        assertEquals(listOf("https://media.example/root/audio.m3u8", "https://media.example/key",
            "https://media.example/root/init.mp4", "https://media.example/root/low/live.m3u8"), links)
        assertFalse(rewritten.contains("media.example"))
        assertTrue(rewritten.contains("URI=\"http://127.0.0.1/2\""))
        assertThrows(Exception::class.java) { fctvRewritePlaylist("https://media.example/a", "#EXTM3U\nfile:///secret") { it } }
    }

    @Test fun servesTransformedSegmentsAndDropsCredentialsAtCdnBoundary() {
        val requests = mutableListOf<String>()
        val server = server { exchange ->
            when (exchange.requestURI.path) {
                "/live.m3u8" -> {
                    assertEquals("private", exchange.requestHeaders["Authorization"])
                    reply(exchange, "#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\n${source()}\n".toByteArray())
                }
                "/video/chunk.ts" -> {
                    assertNull(exchange.requestHeaders["Authorization"])
                    assertNull(exchange.requestHeaders["Cookie"])
                    assertEquals("https://player.example/", exchange.requestHeaders["Referer"])
                    assertTrue(exchange.requestURI.query.contains("_s2="))
                    reply(exchange, ts)
                }
                else -> reply(exchange, "rejected".toByteArray(), 401)
            }
        }
        try {
            proxy(server, connectLog = requests).use { media ->
                media.checkPlaylist()
                val playlist = URI(media.url).toURL().readText()
                val child = playlist.lineSequence().first { it.startsWith("http://") }
                assertArrayEquals(ts, URI(child).toURL().readBytes())
                assertTrue(requests.any { URI(it).host == "cdn.example" })
                val unknown = URI(media.url.replace(Regex("/[^/]+$"), "/unknown")).toURL().openConnection() as HttpURLConnection
                assertEquals(404, unknown.responseCode)
                unknown.disconnect()
            }
        } finally { server.stop() }
    }

    @Test fun followsRedirectsPreservesRangesAndClosesLocalServer() {
        val server = server { exchange ->
            if (exchange.requestURI.path == "/segment.ts") {
                exchange.responseHeaders["Location"] = "https://cdn.example/actual.ts"
                reply(exchange, byteArrayOf(1), 302)
            } else {
                assertNull(exchange.requestHeaders["Authorization"])
                assertEquals("bytes=5-9", exchange.requestHeaders["Range"])
                exchange.responseHeaders["Content-Range"] = "bytes 5-9/376"
                reply(exchange, ts.copyOfRange(5, 10), 206)
            }
        }
        val media = proxy(server, "https://relay.example/segment.ts")
        try {
            val request = URI(media.url).toURL().openConnection() as HttpURLConnection
            request.setRequestProperty("Range", "bytes=5-9")
            assertEquals(206, request.responseCode)
            assertEquals("bytes 5-9/376", request.getHeaderField("Content-Range"))
            assertArrayEquals(ts.copyOfRange(5, 10), request.inputStream.readBytes())
            request.disconnect()
            media.close()
            assertThrows(Exception::class.java) { URI(media.url).toURL().readBytes() }
        } finally { media.close(); server.stop() }
    }

    @Test fun preflightRejectsUnauthorizedSegmentsHtmlAndRedirectLoops() {
        for (mode in listOf("unauthorized", "html", "redirect")) {
            val server = server { exchange ->
                if (mode == "redirect") {
                    exchange.responseHeaders["Location"] = "/live.m3u8"
                    reply(exchange, byteArrayOf(1), 302)
                } else if (exchange.requestURI.path.endsWith("m3u8")) {
                    reply(exchange, "#EXTM3U\n#EXTINF:6,\nseg.ts\n".toByteArray())
                } else {
                    reply(exchange, "<html>error</html>".toByteArray(), if (mode == "unauthorized") 401 else 200)
                }
            }
            try { proxy(server).use { media -> assertThrows(FctvPlaybackException::class.java) { media.checkPlaylist() } } }
            finally { server.stop() }
        }
    }

    @Test fun preflightChecksEncryptionKeysAndInitializationFiles() {
        val requested = mutableListOf<String>()
        val server = server { exchange ->
            requested += exchange.requestURI.path
            val body = when (exchange.requestURI.path) {
                "/live.m3u8" -> ("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\"\n" +
                    "#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:6,\nseg.ts\n").toByteArray()
                "/key.bin" -> ByteArray(16)
                else -> ts
            }
            reply(exchange, body)
        }
        try {
            proxy(server).use { it.checkPlaylist() }
            assertTrue(requested.containsAll(listOf("/key.bin", "/init.mp4", "/seg.ts")))
        } finally { server.stop() }
    }

    @Test fun rejectsPrivateMediaDestinations() {
        for (bad in listOf("http://127.0.0.1/x", "http://[::1]/x", "http://[fd00::1]/x", "http://192.168.1.1/x", "http://169.254.169.254/x")) {
            assertThrows(Exception::class.java) { fctvMediaConnection(bad) }
        }
    }
}
