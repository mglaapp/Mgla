package com.follow.clash.common

/**
 * Turns an Android tombstone into the familiar text: the signal line, the abort message and the
 * backtrace of the crashing thread.
 *
 * Why: for a native crash Android tells the app only "crash". Group #1 in the Mgla admin
 * collected 16 such reports from 0.9.6 to 0.9.15 without a single frame. Since Android 12
 * ApplicationExitInfo.getTraceInputStream() of a REASON_CRASH_NATIVE record is the tombstone,
 * as protobuf: the frames were there all along, nobody read them.
 *
 * No protobuf library: the format needs only varints and length-delimited fields. A damaged or
 * unexpected record gives null (the report then goes out as before), never an exception: a
 * failed read must not replace the crash it describes.
 * Field numbers: AOSP system/core/debuggerd/proto/tombstone.proto.
 */
object TombstoneText {
    const val LIMIT = 12000
    private const val MAX_FRAMES = 48

    // Tombstone
    private const val T_TID = 6
    private const val T_COMMAND_LINE = 9
    private const val T_SIGNAL = 10
    private const val T_ABORT = 14
    private const val T_THREADS = 16

    // Signal
    private const val S_NUMBER = 1
    private const val S_NAME = 2
    private const val S_CODE = 3
    private const val S_CODE_NAME = 4
    private const val S_HAS_FAULT = 8
    private const val S_FAULT = 9

    // Thread
    private const val TH_ID = 1
    private const val TH_NAME = 2
    private const val TH_BACKTRACE = 4

    // BacktraceFrame
    private const val F_REL_PC = 1
    private const val F_FUNCTION = 4
    private const val F_OFFSET = 5
    private const val F_FILE = 6
    private const val F_BUILD_ID = 8

    fun format(bytes: ByteArray): String? = runCatching { formatOrThrow(bytes) }.getOrNull()

    private class Field(val number: Int, val value: Long, val bytes: ByteArray?) {
        fun text(): String = bytes?.toString(Charsets.UTF_8) ?: ""
    }

    private fun List<Field>.first(number: Int): Field? = firstOrNull { it.number == number }

    private fun parse(buf: ByteArray): List<Field> {
        val out = ArrayList<Field>()
        var i = 0
        fun varint(): Long {
            var result = 0L
            var shift = 0
            while (true) {
                require(i < buf.size) { "truncated varint" }
                val b = buf[i++].toInt() and 0xff
                result = result or ((b and 0x7f).toLong() shl shift)
                if ((b and 0x80) == 0) return result
                shift += 7
                require(shift < 64) { "varint too long" }
            }
        }
        fun fixed(size: Int): Long {
            require(i + size <= buf.size) { "truncated fixed" }
            var v = 0L
            for (k in 0 until size) v = v or ((buf[i + k].toLong() and 0xffL) shl (8 * k))
            i += size
            return v
        }
        while (i < buf.size) {
            val key = varint()
            val number = (key ushr 3).toInt()
            when ((key and 7L).toInt()) {
                0 -> out.add(Field(number, varint(), null))
                1 -> out.add(Field(number, fixed(8), null))
                2 -> {
                    val len = varint()
                    require(len >= 0 && len <= (buf.size - i).toLong()) { "bad length" }
                    out.add(Field(number, 0, buf.copyOfRange(i, i + len.toInt())))
                    i += len.toInt()
                }
                5 -> out.add(Field(number, fixed(4), null))
                else -> throw IllegalArgumentException("wire type ${key and 7L}")
            }
        }
        return out
    }

    private fun formatOrThrow(bytes: ByteArray): String? {
        val top = parse(bytes)
        val signal = top.first(T_SIGNAL)?.bytes?.let(::parse)
        val tid = top.first(T_TID)?.value?.toInt()
        val threads = top.filter { it.number == T_THREADS }.mapNotNull { entry ->
            val kv = parse(entry.bytes ?: return@mapNotNull null)
            val thread = kv.first(2)?.bytes?.let(::parse) ?: return@mapNotNull null
            (kv.first(1)?.value?.toInt() ?: thread.first(TH_ID)?.value?.toInt() ?: -1) to thread
        }
        if (signal == null && threads.isEmpty()) return null

        val sb = StringBuilder()
        top.filter { it.number == T_COMMAND_LINE }.joinToString(" ") { it.text() }
            .takeIf { it.isNotBlank() }?.let { sb.append("cmdline: ").append(it).append('\n') }
        if (signal != null) {
            sb.append("signal ").append(signal.first(S_NUMBER)?.value ?: "?")
                .append(" (").append(signal.first(S_NAME)?.text() ?: "?").append("), code ")
                .append(signal.first(S_CODE)?.value?.toInt() ?: "?")
                .append(" (").append(signal.first(S_CODE_NAME)?.text() ?: "?").append(')')
            if ((signal.first(S_HAS_FAULT)?.value ?: 0L) != 0L) {
                sb.append(", fault addr 0x").append(
                    java.lang.Long.toHexString(signal.first(S_FAULT)?.value ?: 0L)
                )
            }
            sb.append('\n')
        }
        top.first(T_ABORT)?.text()?.takeIf { it.isNotBlank() }
            ?.let { sb.append("Abort message: '").append(it).append("'\n") }

        val crashing = threads.firstOrNull { it.first == tid } ?: threads.firstOrNull()
        if (crashing != null) {
            val (id, thread) = crashing
            sb.append("thread ").append(id).append(" (")
                .append(thread.first(TH_NAME)?.text() ?: "?").append("):\n")
            thread.filter { it.number == TH_BACKTRACE }.take(MAX_FRAMES).forEachIndexed { n, f ->
                val frame = parse(f.bytes ?: return@forEachIndexed)
                sb.append(String.format(java.util.Locale.ROOT, "#%02d pc %016x  ", n,
                    frame.first(F_REL_PC)?.value ?: 0L))
                    .append(frame.first(F_FILE)?.text()?.ifBlank { null } ?: "<unknown>")
                val function = frame.first(F_FUNCTION)?.text()
                if (!function.isNullOrBlank()) {
                    sb.append(" (").append(function).append('+')
                        .append(frame.first(F_OFFSET)?.value ?: 0L).append(')')
                }
                frame.first(F_BUILD_ID)?.text()?.takeIf { it.isNotBlank() }
                    ?.let { sb.append(" (BuildId: ").append(it).append(')') }
                sb.append('\n')
            }
        }
        val text = sb.toString().trimEnd()
        return if (text.length > LIMIT) text.substring(0, LIMIT) else text
    }
}
