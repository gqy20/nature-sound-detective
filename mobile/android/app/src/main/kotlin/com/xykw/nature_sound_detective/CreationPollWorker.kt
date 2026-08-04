package com.xykw.nature_sound_detective

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/** Polls an already-submitted Wan task after Flutter leaves the foreground. */
class CreationPollWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {
    override fun doWork(): Result {
        val taskFile = File(inputData.getString(KEY_TASK_PATH).orEmpty())
        if (!taskFile.isFile) {
            NativeDiagnosticLog.emit(
                applicationContext,
                "error",
                "creation_worker",
                "task_file_missing",
                fields = mapOf("attempt" to runAttemptCount),
            )
            return Result.failure()
        }

        var activeRecordId: String? = null
        return try {
            var record = JSONObject(taskFile.readText())
            val recordId = record.optString("id")
            activeRecordId = recordId
            NativeDiagnosticLog.emit(
                applicationContext,
                "info",
                "creation_worker",
                "started",
                traceId = recordId,
                fields = mapOf("attempt" to runAttemptCount),
            )
            val existingVideo = record.optString("video_path")
            if (existingVideo.isNotBlank() && File(existingVideo).isFile) {
                NativeDiagnosticLog.emit(
                    applicationContext,
                    "info",
                    "creation_worker",
                    "video_already_available",
                    traceId = recordId,
                )
                return Result.success()
            }

            val taskId = record.optString("wan_task_id")
            if (taskId.isBlank()) {
                NativeDiagnosticLog.emit(
                    applicationContext,
                    "error",
                    "creation_worker",
                    "task_id_missing",
                    traceId = recordId,
                )
                return Result.failure()
            }
            val settingsFile = File(applicationContext.filesDir, "config/creation_settings.json")
            if (!settingsFile.isFile) {
                NativeDiagnosticLog.emit(
                    applicationContext,
                    "error",
                    "creation_worker",
                    "settings_missing",
                    traceId = recordId,
                )
                return Result.failure()
            }
            val settings = JSONObject(settingsFile.readText())
            val apiKey = settings.optString("dashscope_api_key").trim()
            if (apiKey.isBlank()) {
                NativeDiagnosticLog.emit(
                    applicationContext,
                    "error",
                    "creation_worker",
                    "api_key_missing",
                    traceId = recordId,
                )
                return Result.failure()
            }

            val deadline = System.currentTimeMillis() + POLL_TIMEOUT_MS
            var previousStatus = ""
            while (!isStopped && System.currentTimeMillis() < deadline) {
                val output = poll(baseUrl(settings), apiKey, taskId)
                val status = output.optString("task_status").uppercase()
                if (status != previousStatus) {
                    NativeDiagnosticLog.emit(
                        applicationContext,
                        "info",
                        "creation_worker",
                        "video_status_changed",
                        traceId = recordId,
                        fields = mapOf("status" to status.ifBlank { "MISSING" }),
                    )
                    previousStatus = status
                }
                when (status) {
                    "SUCCEEDED" -> {
                        val videoUrl = output.optString("video_url")
                        if (videoUrl.isBlank()) {
                            mark(record, taskFile, "partial", "视频完成但未返回下载地址", "Wan 未返回视频地址")
                            NativeDiagnosticLog.emit(
                                applicationContext,
                                "error",
                                "creation_worker",
                                "video_url_missing",
                                traceId = recordId,
                            )
                            return Result.failure()
                        }
                        val destination = File(taskFile.parentFile, "nature_video.mp4")
                        val downloadStarted = System.currentTimeMillis()
                        download(videoUrl, destination)
                        NativeDiagnosticLog.emit(
                            applicationContext,
                            "info",
                            "creation_worker",
                            "video_downloaded",
                            traceId = recordId,
                            fields = mapOf(
                                "duration_ms" to System.currentTimeMillis() - downloadStarted,
                                "byte_length" to destination.length(),
                            ),
                        )
                        record = JSONObject(taskFile.readText())
                        if (record.optString("stage") in setOf("composing", "completed") ||
                            record.optString("final_video_path").isNotBlank()
                        ) return Result.success()
                        record.put("video_path", destination.absolutePath)
                        record.put("video_error", "")
                        mark(record, taskFile, "partial", "视频已在后台完成，打开作品继续合成", null)
                        NativeDiagnosticLog.emit(
                            applicationContext,
                            "info",
                            "creation_worker",
                            "completed",
                            traceId = recordId,
                        )
                        return Result.success()
                    }
                    "FAILED", "CANCELED", "UNKNOWN" -> {
                        val message = output.optString("message", "Wan 视频任务失败")
                        mark(record, taskFile, "partial", message, message)
                        NativeDiagnosticLog.emit(
                            applicationContext,
                            "error",
                            "creation_worker",
                            "provider_task_failed",
                            traceId = recordId,
                            fields = mapOf("status" to status),
                        )
                        return Result.failure()
                    }
                }
                Thread.sleep(POLL_INTERVAL_MS)
                record = JSONObject(taskFile.readText())
            }
            if (isStopped) {
                NativeDiagnosticLog.emit(
                    applicationContext,
                    "info",
                    "creation_worker",
                    "stopped",
                    traceId = recordId,
                )
                Result.success()
            } else {
                NativeDiagnosticLog.emit(
                    applicationContext,
                    "warning",
                    "creation_worker",
                    "poll_timeout_retrying",
                    traceId = recordId,
                    fields = mapOf("attempt" to runAttemptCount),
                )
                Result.retry()
            }
        } catch (error: IOException) {
            NativeDiagnosticLog.emit(
                applicationContext,
                "warning",
                "creation_worker",
                "io_failure_retrying",
                traceId = activeRecordId,
                fields = mapOf("attempt" to runAttemptCount),
                error = error,
            )
            Result.retry()
        } catch (error: Exception) {
            NativeDiagnosticLog.emit(
                applicationContext,
                "error",
                "creation_worker",
                "unexpected_failure",
                traceId = activeRecordId,
                fields = mapOf("attempt" to runAttemptCount),
                error = error,
            )
            Result.failure()
        }
    }

    private fun poll(baseUrl: String, apiKey: String, taskId: String): JSONObject {
        val connection = URL("$baseUrl/api/v1/tasks/$taskId").openConnection() as HttpURLConnection
        return connection.useConnection {
            requestMethod = "GET"
            connectTimeout = 30_000
            readTimeout = 60_000
            setRequestProperty("Authorization", "Bearer $apiKey")
            val stream = if (responseCode in 200..299) inputStream else errorStream
            val payload = JSONObject(stream?.bufferedReader()?.use { it.readText() }.orEmpty())
            if (responseCode !in 200..299) {
                throw IOException(payload.optString("message", "DashScope HTTP $responseCode"))
            }
            payload.optJSONObject("output") ?: throw IOException("Wan 返回了无法识别的状态")
        }
    }

    private fun download(source: String, destination: File) {
        val temporary = File(destination.parentFile, "${destination.name}.part")
        temporary.delete()
        val connection = URL(source).openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = true
        connection.connectTimeout = 30_000
        connection.readTimeout = 120_000
        connection.useConnection {
            if (responseCode !in 200..299) throw IOException("视频下载失败：HTTP $responseCode")
            inputStream.use { input -> temporary.outputStream().use { input.copyTo(it) } }
        }
        if (temporary.length() <= 0L) throw IOException("下载的视频为空")
        destination.delete()
        if (!temporary.renameTo(destination)) {
            temporary.copyTo(destination, overwrite = true)
            temporary.delete()
        }
    }

    private fun mark(
        record: JSONObject,
        taskFile: File,
        stage: String,
        message: String,
        videoError: String?,
    ) {
        record.put("stage", stage)
        record.put("message", message)
        record.put("updated_at", java.time.Instant.now().toString())
        if (videoError != null) record.put("video_error", videoError)
        val temporary = File(taskFile.parentFile, "task.json.worker.tmp")
        temporary.writeText(record.toString())
        taskFile.delete()
        if (!temporary.renameTo(taskFile)) {
            temporary.copyTo(taskFile, overwrite = true)
            temporary.delete()
        }
    }

    private fun baseUrl(settings: JSONObject): String {
        val workspace = settings.optString("dashscope_workspace_id").trim()
        return if (settings.optString("dashscope_region") == "singapore") {
            if (workspace.isEmpty()) "https://dashscope-intl.aliyuncs.com"
            else "https://$workspace.ap-southeast-1.maas.aliyuncs.com"
        } else {
            if (workspace.isEmpty()) "https://dashscope.aliyuncs.com"
            else "https://$workspace.cn-beijing.maas.aliyuncs.com"
        }
    }

    private inline fun <T> HttpURLConnection.useConnection(block: HttpURLConnection.() -> T): T =
        try { block() } finally { disconnect() }

    companion object {
        private const val KEY_TASK_PATH = "task_path"
        private const val POLL_INTERVAL_MS = 15_000L
        private const val POLL_TIMEOUT_MS = 7 * 60_000L

        fun schedule(context: Context, recordId: String, taskPath: String) {
            val request = OneTimeWorkRequestBuilder<CreationPollWorker>()
                .setInputData(Data.Builder().putString(KEY_TASK_PATH, taskPath).build())
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .setInitialDelay(30, TimeUnit.SECONDS)
                .setBackoffCriteria(BackoffPolicy.LINEAR, 30, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                "creation_$recordId",
                ExistingWorkPolicy.KEEP,
                request,
            )
            NativeDiagnosticLog.emit(
                context,
                "info",
                "creation_worker",
                "scheduled",
                traceId = recordId,
            )
        }

        fun cancel(context: Context, recordId: String) {
            WorkManager.getInstance(context).cancelUniqueWork("creation_$recordId")
            NativeDiagnosticLog.emit(
                context,
                "info",
                "creation_worker",
                "cancel_requested",
                traceId = recordId,
            )
        }
    }
}
