package dev.local.flick

import java.io.BufferedInputStream
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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

    /** [check] gets the server side of a loopback connection, its buffered input, and the client socket. */
    private fun loopback(check: (Socket, BufferedInputStream, Socket) -> Unit) {
        ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { server ->
            Socket(server.inetAddress, server.localPort).use { client ->
                server.accept().use { s -> check(s, BufferedInputStream(s.getInputStream()), client) }
            }
        }
    }

    @Test fun clientGoneFalseWhileIdle() = loopback { s, input, _ ->
        assertFalse(clientGone(s, input))
        assertEquals(0, s.soTimeout) // restored
    }

    @Test fun clientGoneTrueAfterHangUp() = loopback { s, input, client ->
        client.close()
        val deadline = System.nanoTime() + 2_000_000_000L // the FIN can take a moment to arrive
        while (!clientGone(s, input) && System.nanoTime() < deadline) Thread.sleep(5)
        assertTrue(clientGone(s, input))
    }

    @Test fun clientGoneIgnoresStrayBytes() = loopback { s, input, client ->
        client.getOutputStream().apply { write('x'.code); flush() }
        Thread.sleep(50)
        assertFalse(clientGone(s, input)) // reads the byte, client still open
        assertFalse(clientGone(s, input))
    }

    @Test fun windowClampsBothEndsAndKeepsTwo() {
        val mib = 1L shl 20
        assertEquals(8, window(0, 1 shl 20)) // 8 MiB floor
        assertEquals(64, window(100 * mib, 1 shl 20)) // 64 MiB ceiling
        assertEquals(30, window(mib, 1 shl 20)) // 30 s at 1 MiB/s
        assertEquals(8, window(mib, 4 shl 20)) // 30 MiB of 4 MiB pieces rounds up
        assertEquals(2, window(0, 32 shl 20)) // one piece would cover 8 MiB; at least 2
    }

    private val mib = 1 shl 20

    @Test fun scheduleSkipsHadPiecesAndSpacesDeadlinesByBitrate() {
        // 1 MiB pieces at 2 MiB/s: the player reaches each piece 500 ms after the one before.
        assertEquals(listOf(10 to 0, 12 to 1000, 13 to 1500),
            schedule(10, 13, mib, 2L * mib, 0, { it == 11 }, emptyMap()))
        // Bounded by the window (30 pieces at 1 MiB/s), not the file's end.
        assertEquals(30, schedule(0, 1000, mib, 1L * mib, 0, { false }, emptyMap()).last().first)
    }

    @Test fun scheduleNeverPostponesAnExistingDeadline() {
        val due = mapOf(10 to 0L, 11 to 500L, 12 to 1000L, 13 to 1500L) // set at 0 ms
        assertEquals(emptyList<Pair<Int, Int>>(), schedule(10, 13, mib, 2L * mib, 500, { false }, due))
    }

    @Test fun scheduleMovesADeadlineEarlier() {
        // The bitrate doubles: 11–13 come due sooner; 10 stays as it was.
        val due = mapOf(10 to 0L, 11 to 500L, 12 to 1000L, 13 to 1500L)
        assertEquals(listOf(11 to 250, 12 to 500, 13 to 750), schedule(10, 13, mib, 4L * mib, 0, { false }, due))
    }

    @Test fun isSeekOnlyOutsideTheWindow() {
        assertFalse(isSeek(15, 10, 30, 1000)) // inside
        assertFalse(isSeek(9, 10, 30, 1000)) // behind by one
        assertFalse(isSeek(40, 10, 30, 1000)) // window's end
        assertTrue(isSeek(500, 10, 30, 1000)) // far ahead
        assertTrue(isSeek(8, 10, 30, 1000)) // back
    }

    @Test fun tailProbeIsNeverASeek() {
        assertFalse(isSeek(1000, 10, 30, 1000)) // the last piece
        assertFalse(isSeek(999, 10, 30, 1000))
        assertTrue(isSeek(998, 10, 30, 1000))
    }

    private fun createTempDirectory(): File = kotlin.io.path.createTempDirectory("httptest").toFile()
}
