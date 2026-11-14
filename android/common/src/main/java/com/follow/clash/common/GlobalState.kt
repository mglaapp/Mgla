package com.follow.clash.common

import android.app.ActivityManager
import android.app.Application
import android.app.ApplicationExitInfo
import android.os.Build
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

object GlobalState : CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Default) {
    const val NOTIFICATION_CHANNEL = "FlClash"
    const val NOTIFICATION_ID = 1
    private const val ANY_PID = 0
    private const val EVERY_EXIT_RECORD = 0

    val packageName: String
        get() = application.packageName

    val receiveBroadcastPermission: String
        get() = "$packageName.permission.RECEIVE_BROADCASTS"

    val application: Application
        get() = checkNotNull(appInstance) { "GlobalState is not initialized" }

    @Volatile
    private var appInstance: Application? = null

    fun init(application: Application) {
        appInstance = application
    }

    fun log(text: String) {
        Log.d("FlClash", text)
    }

    fun lastExitInfo(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val manager = application.getSystemService(ActivityManager::class.java) ?: return null
        val info = runCatching {
            manager.getHistoricalProcessExitReasons(
                application.packageName,
                ANY_PID,
                EVERY_EXIT_RECORD,
            )
        }.getOrNull()?.firstOrNull { it.processName == application.packageName } ?: return null
        return mapOf(
            "reason" to info.reason,
            "timestamp" to info.timestamp,
            "description" to info.description,
            "trace" to exitTrace(info),
        )
    }

    /**
     * What the system kept about the death: since Android 12 a native crash leaves a tombstone
     * (protobuf, TombstoneText), an ANR leaves the thread dump as text. Read only for these two
     * reasons and never more than [TRACE_READ_LIMIT]: this runs on every launch.
     */
    private fun exitTrace(info: ApplicationExitInfo): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        val native = info.reason == ApplicationExitInfo.REASON_CRASH_NATIVE
        if (!native && info.reason != ApplicationExitInfo.REASON_ANR) return null
        return runCatching {
            val bytes = info.traceInputStream?.use { input ->
                val out = java.io.ByteArrayOutputStream()
                val buf = ByteArray(64 * 1024)
                while (out.size() < TRACE_READ_LIMIT) {
                    val n = input.read(buf)
                    if (n < 0) break
                    out.write(buf, 0, n)
                }
                out.toByteArray()
            } ?: return null
            if (native) {
                TombstoneText.format(bytes)?.let { "== tombstone ==\n$it" }
            } else {
                val text = bytes.toString(Charsets.UTF_8).trim()
                if (text.isEmpty()) null
                else "== anr ==\n" + text.take(TombstoneText.LIMIT)
            }
        }.getOrNull()
    }

    private const val TRACE_READ_LIMIT = 4 * 1024 * 1024
}
