package com.follow.clash.common

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream

/**
 * A tombstone is built here by hand, field by field, with the numbers of AOSP tombstone.proto:
 * the parser must read the real layout, and a damaged record must give null, never throw.
 */
class TombstoneTextTest {
    private class Proto {
        private val out = ByteArrayOutputStream()

        private fun varint(value: Long) {
            var v = value
            while (true) {
                if ((v and 0x7fL.inv()) == 0L) {
                    out.write(v.toInt())
                    return
                }
                out.write(((v and 0x7fL) or 0x80L).toInt())
                v = v ushr 7
            }
        }

        fun int(number: Int, value: Long) = apply {
            varint((number shl 3).toLong())
            varint(value)
        }

        fun bytes(number: Int, value: ByteArray) = apply {
            varint(((number shl 3) or 2).toLong())
            varint(value.size.toLong())
            out.write(value)
        }

        fun str(number: Int, value: String) = bytes(number, value.toByteArray())
        fun msg(number: Int, value: Proto) = bytes(number, value.build())
        fun build(): ByteArray = out.toByteArray()
    }

    private fun frame(relPc: Long, file: String, function: String? = null, offset: Long = 0) =
        Proto().int(1, relPc).int(2, relPc + 0x7000000000).apply {
            if (function != null) str(4, function).int(5, offset)
        }.str(6, file).str(8, "abc123")

    private fun thread(id: Int, name: String, vararg frames: Proto) =
        Proto().int(1, id.toLong()).str(2, name).apply { frames.forEach { msg(4, it) } }

    private fun tombstone(abort: String? = null): ByteArray {
        val signal = Proto().int(1, 11).str(2, "SIGSEGV").int(3, 1).str(4, "SEGV_MAPERR")
            .int(8, 1).int(9, 0x10)
        val other = thread(100, "main", frame(0x10, "/system/lib64/libc.so", "epoll_wait", 8))
        val crashing = thread(
            4242, "mgla-core",
            frame(0xa1b2c, "/data/app/~~Xy==/com.mgla.app-1/lib/arm64/libclash.so", "tun_read", 40),
            frame(0x12345, "/apex/com.android.runtime/lib64/bionic/libc.so"),
        )
        return Proto().int(1, 1).str(2, "google/sdk/emu:12/SE1A/1:user/dev-keys")
            .int(5, 4200).int(6, 4242).str(9, "com.mgla.app")
            .msg(10, signal)
            .apply { if (abort != null) str(14, abort) }
            .msg(16, Proto().int(1, 100).msg(2, other))
            .msg(16, Proto().int(1, 4242).msg(2, crashing))
            .build()
    }

    @Test
    fun `signal line, crashing thread first frame and build id`() {
        val text = TombstoneText.format(tombstone())
        assertNotNull(text)
        val lines = text!!.lines()
        assertEquals("cmdline: com.mgla.app", lines[0])
        assertEquals("signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x10", lines[1])
        assertEquals("thread 4242 (mgla-core):", lines[2])
        assertEquals(
            "#00 pc 00000000000a1b2c  /data/app/~~Xy==/com.mgla.app-1/lib/arm64/libclash.so " +
                "(tun_read+40) (BuildId: abc123)",
            lines[3],
        )
        assertTrue(lines[4], lines[4].startsWith("#01 pc 0000000000012345  /apex/"))
        assertTrue("the other thread stays out", !text.contains("epoll_wait"))
    }

    @Test
    fun `abort message is kept`() {
        val text = TombstoneText.format(tombstone(abort = "Check failed: idx < size"))!!
        assertTrue(text, text.contains("Abort message: 'Check failed: idx < size'"))
    }

    @Test
    fun `damaged or foreign bytes give null, not an exception`() {
        val good = tombstone()
        assertNull(TombstoneText.format(good.copyOf(good.size / 2)))
        assertNull(TombstoneText.format("not a tombstone at all".toByteArray()))
        assertNull(TombstoneText.format(ByteArray(0)))
        assertNull(TombstoneText.format(byteArrayOf(0x0f)))
    }
}
