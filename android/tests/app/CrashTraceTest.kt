package com.follow.clash

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * The file name and directory are a contract with Dart (`sideTraceFiles` in
 * lib/common/crash_report.dart): a crash written anywhere else is a crash nobody reads.
 */
class CrashTraceTest {
    private lateinit var home: File
    private var saved: Thread.UncaughtExceptionHandler? = null

    @Before
    fun setUp() {
        home = Files.createTempDirectory("crash-trace").toFile()
        saved = Thread.getDefaultUncaughtExceptionHandler()
    }

    @After
    fun tearDown() {
        Thread.setDefaultUncaughtExceptionHandler(saved)
        home.deleteRecursively()
    }

    @Test
    fun `write puts thread, exception and frames into crash slash java-crash log`() {
        CrashTrace.write(File(home, "crash"), "main", IllegalStateException("probe 13-10"))

        val text = File(home, "crash/java-crash.log").readText()
        assertTrue(text, text.startsWith("thread: main\n"))
        assertTrue(text, text.contains("java.lang.IllegalStateException: probe 13-10"))
        assertTrue(text, text.contains("\tat com.follow.clash.CrashTraceTest"))
    }

    @Test
    fun `installed handler writes the trace and still hands the crash on`() {
        var handedOn: Throwable? = null
        Thread.setDefaultUncaughtExceptionHandler { _, error -> handedOn = error }
        CrashTrace.install(home)

        val error = RuntimeException("uncaught probe")
        Thread.getDefaultUncaughtExceptionHandler()!!.uncaughtException(Thread.currentThread(), error)

        assertSame(error, handedOn)
        assertTrue(File(home, "crash/${CrashTrace.FILE_NAME}").readText().contains("uncaught probe"))
    }

    @Test
    fun `a failed write does not throw`() {
        val blocker = File(home, "crash")
        blocker.writeText("a file where the directory should be")

        CrashTrace.write(blocker, "main", RuntimeException("x"))

        assertFalse(File(blocker, CrashTrace.FILE_NAME).exists())
        assertEquals("a file where the directory should be", blocker.readText())
    }
}
