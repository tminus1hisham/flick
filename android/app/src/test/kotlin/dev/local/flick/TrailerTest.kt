package dev.local.flick

import org.junit.Assert.*
import org.junit.Test

class TrailerTest {
    @Test fun validatesSourcesAtNativeBoundary() {
        assertTrue(validTrailerSource("P6AaSMfXHbA", true))
        assertFalse(validTrailerSource("</script>", true))
        assertTrue(validTrailerSource("https://example.test/trailer.mp4", false))
        assertFalse(validTrailerSource("file:///video.mp4", false))
        assertFalse(validTrailerSource("javascript:alert(1)", false))
        assertFalse(validTrailerSource("https://user:secret@example.test/video", false))
    }
}
