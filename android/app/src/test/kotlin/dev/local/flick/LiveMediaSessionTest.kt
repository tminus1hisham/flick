package dev.local.flick

import org.junit.Assert.*
import org.junit.Test

class LiveMediaSessionTest {
    private class Media : AutoCloseable {
        var closes = 0
        override fun close() { closes++ }
    }

    @Test fun stagingAndCancellationKeepTheCurrentBroadcastAlive() {
        val session = LiveMediaSession<Media>()
        val current = Media()
        val candidate = Media()
        session.stage("current", current)
        session.commit("current")
        session.stage("candidate", candidate)
        assertEquals(0, current.closes)
        session.cancel()
        assertEquals(1, candidate.closes)
        assertEquals(0, current.closes)
        assertThrows(IllegalStateException::class.java) { session.commit("candidate") }
        session.close()
        assertEquals(1, current.closes)
    }

    @Test fun commitReleasesOnlyTheOutgoingBroadcastAndRejectsStaleSelection() {
        val session = LiveMediaSession<Media>()
        val first = Media()
        val replaced = Media()
        val next = Media()
        session.stage("first", first)
        session.commit("first")
        session.stage("old", replaced)
        session.stage("next", next)
        assertEquals(1, replaced.closes)
        assertThrows(IllegalStateException::class.java) { session.commit("old") }
        assertEquals(0, first.closes)
        session.commit("next")
        assertEquals(1, first.closes)
        assertEquals(0, next.closes)
        session.close()
        session.close()
        assertEquals(1, next.closes)
    }

    @Test fun directSourcesAlsoCommitAndCloseThePreviousProxy() {
        val session = LiveMediaSession<Media>()
        val proxy = Media()
        session.stage("proxy", proxy)
        session.commit("proxy")
        session.stage("direct", null)
        assertEquals(0, proxy.closes)
        session.commit("direct")
        assertEquals(1, proxy.closes)
        session.close()
    }
}
