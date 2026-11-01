package dev.local.flick

import org.junit.Assert.*
import org.junit.Test

class FctvTest {
    private fun hex(s: String) = s.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    @Test fun acceptsCurrentBootstrapOriginsAndRejectsUntrustedTargets() {
        for (origin in listOf("https://apis-data10.tcpwe138stya.ru", "https://apis-data-defra10.tcpwe138stya.ru/")) {
            assertEquals(origin.trimEnd('/'), fctvApiOrigin(origin))
        }
        for (bad in listOf("http://apis-data10.tcpwe138stya.ru", "https://127.0.0.1", "https://localhost/",
            "https://apis-data10.tcpwe138stya.ru.evil.example", "https://apis-data10.tcpwe138stya.ru:443/",
            "https://apis-data10.tcpwe138stya.ru/api", "https://apis-data10.tcpwe138stya.ru/?token=secret",
            "https://user:secret@apis-data10.tcpwe138stya.ru", "https://apis-data10.tcpwe138stya.ru/#fragment")) {
            assertThrows("Accepted $bad", Exception::class.java) { fctvApiOrigin(bad) }
        }
    }

    @Test fun playbackErrorsDistinguishMediaRejectionFromPlaylistFailure() {
        val media = FctvPlaybackException("media", 401)
        assertEquals("media", media.stage)
        assertEquals(401, media.status)
        assertTrue(media.userMessage.contains("HTTP 401"))
        assertTrue(FctvPlaybackException("playlist", 503).userMessage.contains("playlist request failed (HTTP 503)"))
        assertFalse(FctvPlaybackException("playlist depth").userMessage.contains("rejected playback"))
    }

    @Test fun readsEnvelopeAndVersionMap() {
        val response = FctvMessage(hex("1a075375636365737352260a24086412206139353436666539363566346163353364316362336665643734643563366534"))
        assertEquals(0L, response.number(2))
        assertEquals("Success", response.text(3))
        val version = FctvMessage(response.blob(10)).messages(1).single()
        assertEquals(100L, version.number(1))
        assertEquals("a9546fe965f4ac53d1cb3fed74d5c6e4", version.text(2))
    }

    @Test fun retainsRepeatedFieldsAndSkipsFixedFields() {
        val m = FctvMessage(hex("080108021100000000000000001d00000000220141"))
        assertEquals(1L, m.number(1))
        assertEquals("A", m.text(4))
        assertEquals(0L, m.number(99))
    }

    @Test fun rejectsMalformedMessages() {
        for (s in listOf("00", "01", "80", "120441", "0b", "09", "0d", "08ffffffffffffffffff02", "12ffffffffffffffffff01")) {
            assertThrows("Accepted $s", Exception::class.java) { FctvMessage(hex(s)) }
        }
        assertThrows(Exception::class.java) { FctvMessage(hex("1201ff")).text(2) }
    }

    @Test fun decodesUrlsWithoutChangingPathOrQuery() {
        val url = "https://media.example/live/test.m3u8?key=a%2Fb&x=1"
        assertEquals(url, fctvUrl(fctvRot47("12345678$url")))
        assertEquals(url, fctvUrl(url))
        assertEquals("http://media.example/a.m3u8", fctvSessionUrl("http://media.example/a.m3u8", "session"))
        assertEquals(url, fctvSessionUrl(url, ""))
        for (bad in listOf("tiny", "file:///etc/passwd", "https://user:secret@example.com/a", "https:///missing")) {
            assertThrows(Exception::class.java) { fctvUrl(bad) }
        }
    }

    @Test fun resolvesNestedPlaylistsAndRejectsUnsafeMedia() {
        val master = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\nlow/live.m3u8?key=a%2Fb\n"
        assertEquals("https://media.example/low/live.m3u8?key=a%2Fb", fctvPlaylistChild("https://media.example/master.m3u8", master))
        assertEquals("https://media.example/seg.ts", fctvPlaylistChild("https://media.example/live.m3u8", "#EXTM3U\n#EXTINF:6,\nseg.ts\n"))
        for (body in listOf("<!doctype html>", "#EXTM3U\n", "#EXTM3U\nfile:///local")) {
            assertThrows(Exception::class.java) { fctvPlaylistChild("https://media.example/live.m3u8", body) }
        }
    }
}
