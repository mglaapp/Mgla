package com.follow.clash

import java.io.File

/**
 * Writes the stack of an uncaught JVM exception into the app's crash report directory, then
 * hands the crash on to the previous handler exactly as before.
 *
 * For such a crash Android tells the app only "crash" (ApplicationExitInfo), with no stack:
 * a report from 0.9.6 on 13-10 arrived exactly like that. Dart reads the file on the next
 * launch (lib/common/crash_report.dart, sideTraceFiles) and attaches it to the report.
 */
object CrashTrace {
    const val FILE_NAME = "java-crash.log"

    fun install(filesDir: File) {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            write(File(filesDir, "crash"), thread.name, error)
            previous?.uncaughtException(thread, error)
        }
    }

    /** Never throws: a failed write must not replace the crash it describes. */
    fun write(dir: File, threadName: String, error: Throwable) {
        runCatching {
            dir.mkdirs()
            File(dir, FILE_NAME).writeText("thread: $threadName\n${error.stackTraceToString()}")
        }
    }
}
