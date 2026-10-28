package dev.local.flick

import java.io.File
import java.security.MessageDigest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HttpTest {
    @Test fun parseRangeForms() {
        assertEquals(ByteRange.Full, parseRange(null, 100))
        assertEquals(ByteRange.Part(10, 19), parseRange("bytes=10-19", 100))
        assertEquals(ByteRange.Part(10, 99), parseRange("bytes=10-", 100))
        assertEquals(ByteRange.Part(90, 99), parseRange("bytes=-10", 100))
        assertEquals(ByteRange.Part(0, 99), parseRange("bytes=-500", 100))
        assertEquals(ByteRange.Part(95, 99), parseRange("bytes=95-500", 100))
        assertEquals(ByteRange.Part(5, 5), parseRange(" bytes=5-5 ", 100))
    }

    @Test fun parseRangeIgnoresMalformedAndMultiRange() {
        assertEquals(ByteRange.Full, parseRange("bytes=0-1,5-6", 100))
        assertEquals(ByteRange.Full, parseRange("items=0-1", 100))
        assertEquals(ByteRange.Full, parseRange("bytes=20-10", 100))
        assertEquals(ByteRange.Full, parseRange("bytes=-", 100))
        assertEquals(ByteRange.Full, parseRange("bytes=99999999999999999999-", 100))
    }

    @Test fun parseRangeUnsatisfiable() {
        assertEquals(ByteRange.Unsatisfiable, parseRange("bytes=100-", 100))
        assertEquals(ByteRange.Unsatisfiable, parseRange("bytes=-0", 100))
        assertEquals(ByteRange.Unsatisfiable, parseRange("bytes=0-", 0))
        assertEquals(ByteRange.Unsatisfiable, parseRange("bytes=-5", 0))
    }

    @Test fun responseHeads() {
        assertEquals(
            "HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nContent-Length: 100\r\nAccept-Ranges: bytes\r\n" +
                "Connection: close\r\n\r\n",
            responseHead(ByteRange.Full, 100, "video/mp4"))
        val partial = responseHead(ByteRange.Part(10, 19), 100, "video/mp4")
        assert(partial.startsWith("HTTP/1.1 206 Partial Content\r\n"))
        assert("Content-Length: 10\r\n" in partial && "Content-Range: bytes 10-19/100\r\n" in partial)
        val bad = responseHead(ByteRange.Unsatisfiable, 100, "video/mp4")
        assert(bad.startsWith("HTTP/1.1 416 ") && "Content-Length: 0\r\n" in bad)
        assert("Content-Range: bytes */100\r\n" in bad)
        assert(responseHead(ByteRange.Full, 0, "x").contains("Content-Length: 0\r\n"))
    }

    @Test fun chunkHandlesFileStartingMidPiece() {
        // pieces of 100; file starts at torrent offset 250 (inside piece 2, at 50)
        val size = { _: Int -> 100 }
        assertEquals(Chunk(2, 50, 50), chunk(250, 0, 999, 100, size))
        assertEquals(Chunk(3, 0, 100), chunk(250, 50, 999, 100, size))
        assertEquals(Chunk(3, 10, 1), chunk(250, 60, 60, 100, size)) // single byte
        assertEquals(Chunk(2, 70, 5), chunk(250, 20, 24, 100, size)) // range ends inside the piece
    }

    @Test fun chunkStopsAtShortFinalPiece() {
        val size = { p: Int -> if (p == 4) 30 else 100 }
        assertEquals(Chunk(4, 10, 20), chunk(0, 410, 10_000, 100, size))
    }

    @Test fun pieceRangeCoversFile() {
        assertEquals(2..3, pieceRange(250, 100, 100))
        assertEquals(2..2, pieceRange(250, 50, 100))
        assertEquals(0..0, pieceRange(0, 1, 100))
        assertEquals(IntRange.EMPTY, pieceRange(250, 0, 100))
    }

    @Test fun sha1SpansFilesAndPadding() {
        val dir = createTempDirectory()
        try {
            val a = File(dir, "a").apply { writeBytes(ByteArray(300) { it.toByte() }) }
            val b = File(dir, "b").apply { writeBytes(ByteArray(50) { (it * 3).toByte() }) }
            val slices = listOf(Slice(a.path, 200, 100), Slice(null, 0, 7), Slice(b.path, 0, 50))
            val expected = MessageDigest.getInstance("SHA-1").run {
                update(a.readBytes().copyOfRange(200, 300)); update(ByteArray(7)); update(b.readBytes()); digest()
            }
            assertArrayEquals(expected, sha1(slices) { false })
            assertNull(sha1(listOf(Slice(b.path, 40, 20))) { false }) // short file
            assertNull(sha1(listOf(Slice(a.path, 0, 10))) { true }) // cancelled
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test fun mimeByExtension() {
        assertEquals("video/x-matroska", mimeOf("Show.S01E01.MKV"))
        assertEquals("application/octet-stream", mimeOf("readme"))
    }

    private fun createTempDirectory(): File = kotlin.io.path.createTempDirectory("httptest").toFile()
}
