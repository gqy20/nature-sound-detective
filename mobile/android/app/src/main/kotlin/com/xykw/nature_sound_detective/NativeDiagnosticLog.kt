package com.xykw.nature_sound_detective

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.time.Instant

/** Small JSONL logger for work that can continue after the Flutter engine stops. */
object NativeDiagnosticLog {
    private const val TAG = "NatureDiagnostic"
    private const val MAX_BYTES = 512L * 1024
    private const val BACKUP_COUNT = 2

    @Synchronized
    fun emit(
        context: Context,
        level: String,
        component: String,
        event: String,
        traceId: String? = null,
        fields: Map<String, Any?> = emptyMap(),
        error: Throwable? = null,
    ) {
        try {
            val directory = File(context.filesDir, "logs").apply { mkdirs() }
            val active = File(directory, "native.jsonl")
            val payload = JSONObject().apply {
                put("timestamp", Instant.now().toString())
                put("level", level)
                put("component", component)
                put("event", event)
                if (!traceId.isNullOrBlank()) put("trace_id", traceId)
                fields.forEach { (key, value) -> put(key, safeValue(key, value)) }
                if (error != null) {
                    put("error_type", error.javaClass.simpleName)
                    put("error", redact(error.message.orEmpty()).take(500))
                }
            }
            val line = payload.toString() + "\n"
            if (active.isFile && active.length() + line.toByteArray().size > MAX_BYTES) {
                rotate(directory)
            }
            active.appendText(line)
            when (level) {
                "error" -> Log.e(TAG, "$component.$event", error)
                "warning" -> Log.w(TAG, "$component.$event", error)
                else -> Log.i(TAG, "$component.$event")
            }
        } catch (loggingError: Exception) {
            Log.w(TAG, "native_log_write_failed", loggingError)
        }
    }

    private fun rotate(directory: File) {
        for (index in BACKUP_COUNT downTo 1) {
            val source = File(directory, if (index == 1) "native.jsonl" else "native.${index - 1}.jsonl")
            val target = File(directory, "native.$index.jsonl")
            if (!source.isFile) continue
            if (target.exists()) target.delete()
            source.renameTo(target)
        }
    }

    private fun safeValue(key: String, value: Any?): Any? {
        val normalized = key.lowercase()
        if (listOf("key", "token", "authorization", "prompt", "path", "url").any(normalized::contains)) {
            return "[REDACTED]"
        }
        return when (value) {
            null, is Number, is Boolean -> value
            else -> redact(value.toString()).take(500)
        }
    }

    private fun redact(value: String): String = value
        .replace(Regex("bearer\\s+[a-z0-9._-]+", RegexOption.IGNORE_CASE), "Bearer [REDACTED]")
        .replace(Regex("sk-[a-z0-9_-]{8,}", RegexOption.IGNORE_CASE), "[REDACTED_KEY]")
        .replace(
            Regex("([?&](?:token|access_token|api_key|signature|x-oss-signature|x-oss-security-token|ossaccesskeyid|x-amz-credential|x-amz-signature|x-amz-security-token)=)[^&\\s]+", RegexOption.IGNORE_CASE),
            "\$1[REDACTED]",
        )
}
