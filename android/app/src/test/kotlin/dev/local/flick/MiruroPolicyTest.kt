package dev.local.flick

import org.junit.Assert.*
import org.junit.Test

class MiruroPolicyTest {
    private val origin = "https://www.miruro.to"

    @Test fun onlyExactHttpsOriginCanUseBridge() {
        assertTrue(MiruroPolicy.sameOrigin(origin, "$origin/watch/20"))
        assertTrue(MiruroPolicy.sameOrigin(origin, "$origin:443/watch/20"))
        for (url in listOf("http://www.miruro.to", "$origin.evil.test", "$origin:444", "file:///tmp/test",
            "https://www.miruro.to@evil.test", "https://evil.test@www.miruro.to", "https://www.miruro.ru", "garbage")) {
            assertFalse(url, MiruroPolicy.sameOrigin(origin, url))
        }
        assertFalse(MiruroPolicy.sameOrigin("https://evil.test", "https://evil.test"))
    }

    @Test fun onlyPendingMainFrameRequestCanReply() {
        val request = MiruroPending("first", origin)
        assertTrue(request.accepts("first", origin, true))
        assertFalse(request.accepts("old", origin, true))
        assertFalse(request.accepts("first", origin, false))
        assertFalse(request.accepts("first", "https://evil.test", true))
        assertTrue(request.finish())
        assertFalse(request.accepts("first", origin, true))
        assertFalse(request.finish())
    }

    @Test fun onlyReadOnlyCatalogPathsCanBeRequested() {
        assertTrue(MiruroPolicy.requestPath("/api/v1/anime?q=Naruto&limit=15"))
        assertTrue(MiruroPolicy.requestPath("/api/v1/anime/opaque_ID/episodes?limit=10000"))
        assertTrue(MiruroPolicy.requestPath("/api/v1/anime/opaque_ID/episodes/1/play"))
        for (path in listOf("https://evil.test/api/v1/anime", "//evil.test/api/v1/anime", "/api/v1/identities",
            "/api/v1/anime/id/episodes/1/delete", "/api/v1/anime/../account", "/api/v1/anime#fragment")) {
            assertFalse(path, MiruroPolicy.requestPath(path))
        }
    }

    @Test fun verificationIsOnlyShownForARealBlockAndAtMostOncePerRequest() {
        val request = MiruroPending("first", origin)
        assertFalse(request.needsVerification(false))
        assertTrue(request.needsVerification(true))
        assertFalse(request.needsVerification(true))
        val cancelled = MiruroPending("cancelled", origin)
        cancelled.finish()
        assertFalse(cancelled.needsVerification(true))
    }
}
