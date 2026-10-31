package dev.local.flick

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadsTest {
    @Test fun sweepNeverLeavesTheStreamingRoot() {
        val base = Files.createTempDirectory("flick").toFile()
        try {
            val root = File(base, "cache/flick-torrents").apply { mkdirs() }
            val s1 = File(root, "s1").apply { mkdir() }
            val s2 = File(root, "s2").apply { mkdir() }
            val downloads = File(base, "files/downloads").apply { mkdirs() }
            val mine = File(downloads, "aaaa").apply { mkdir() }
            File(downloads, "bbbb").mkdir()
            assertEquals(setOf(s2), leftovers(root, s1).toSet())
            // The first add of a process is a download: other downloads are not leftovers.
            assertEquals(setOf(s1, s2), leftovers(root, mine).toSet())
            assertEquals(emptyList<File>(), leftovers(File(base, "missing"), mine))
        } finally {
            base.deleteRecursively()
        }
    }

    @Test fun restoredSelectionWaitsForMetadataAndIsValidatedWhenItArrives() {
        assertTrue(validDownloadFile(3, null))
        assertTrue(validDownloadFile(3, 4))
        assertFalse(validDownloadFile(3, 3))
        assertFalse(validDownloadFile(-1, null))
        assertFalse(validDownloadFile(0, 0))
    }

    @Test fun isUnderIsStrict() {
        val root = File("/data/files/downloads")
        assertTrue(isUnder(File(root, "abc"), root))
        assertFalse(isUnder(root, root))
        assertFalse(isUnder(File("/data/files/downloads2/abc"), root))
        assertFalse(isUnder(File("/data/cache/flick-torrents/s1"), root))
    }
}
