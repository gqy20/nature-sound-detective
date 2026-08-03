package com.xykw.nature_sound_detective

import android.Manifest
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import kotlin.math.max

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.xykw.nature_sound/audio_recorder"
        private const val TAG = "NatureAudio"
        private const val PERMISSION_REQUEST = 7301
        private const val SAMPLE_RATE = 48_000
        private const val CHANNEL_COUNT = 1
        private const val BYTES_PER_SAMPLE = 2
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val stateLock = Any()
    @Volatile private var recording = false
    private var activeRecorder: AudioRecord? = null
    private var activeFile: File? = null
    private var activeId: String? = null
    private var completedRecording: Map<String, Any>? = null
    private var completedFailure: Map<String, String>? = null
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasRecordPermission())
            "getDiagnostics" -> result.success(mapOf(
                "manufacturer" to Build.MANUFACTURER,
                "model" to Build.MODEL,
                "android_sdk" to Build.VERSION.SDK_INT,
            ))
            "requestPermission" -> requestRecordPermission(result)
            "startRecording" -> startRecording(call, result)
            "stopRecording" -> finishRecording(result, delete = false)
            "cancelRecording" -> finishRecording(result, delete = true)
            "loadDebugDemo" -> loadDebugDemo(result)
            else -> result.notImplemented()
        }
    }

    private fun loadDebugDemo(result: MethodChannel.Result) {
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
            result.notImplemented()
            return
        }
        val file = File(cacheDir, "demo/demo.wav")
        if (!file.isFile || file.length() <= 44L) {
            result.error(
                "demo_missing",
                "请先通过 ADB 将演示 WAV 放入应用私有缓存。",
                null,
            )
            return
        }
        try {
            RandomAccessFile(file, "r").use { wav ->
                val header = ByteArray(44)
                wav.readFully(header)
                if (String(header, 0, 4) != "RIFF" || String(header, 8, 4) != "WAVE") {
                    throw IllegalArgumentException("演示文件不是 WAV。")
                }
                val values = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
                val channels = values.getShort(22).toInt()
                val sampleRate = values.getInt(24)
                val bitsPerSample = values.getShort(34).toInt()
                if (channels <= 0 || sampleRate <= 0 || bitsPerSample != 16) {
                    throw IllegalArgumentException("演示文件必须是 16-bit PCM WAV。")
                }
                val dataBytes = file.length() - 44L
                val bytesPerSecond = sampleRate.toLong() * channels * 2L
                val durationMs = dataBytes * 1000L / bytesPerSecond
                result.success(mapOf(
                    "id" to "demo_${System.currentTimeMillis()}",
                    "path" to file.absolutePath,
                    "duration_ms" to durationMs,
                    "sample_rate" to sampleRate,
                    "channel_count" to channels,
                    "byte_length" to file.length().toInt(),
                ))
                Log.i(
                    TAG,
                    "event=debug_demo_loaded duration_ms=$durationMs byte_length=${file.length()}",
                )
            }
        } catch (error: Exception) {
            Log.e(TAG, "event=debug_demo_load_failed", error)
            result.error("demo_invalid", error.message ?: "演示声音无效。", null)
        }
    }

    private fun hasRecordPermission(): Boolean =
        checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun requestRecordPermission(result: MethodChannel.Result) {
        if (hasRecordPermission()) {
            result.success(true)
            return
        }
        if (permissionResult != null) {
            result.error("permission_in_progress", "麦克风权限请求正在进行。", null)
            return
        }
        permissionResult = result
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) {
            val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            Log.i(TAG, "event=permission_result granted=$granted")
            permissionResult?.success(granted)
            permissionResult = null
        }
    }

    private fun startRecording(call: MethodCall, result: MethodChannel.Result) {
        if (!hasRecordPermission()) {
            result.error("permission_denied", "需要麦克风权限才能录音。", null)
            return
        }
        synchronized(stateLock) {
            if (recording) {
                result.error("already_recording", "当前已有录音正在进行。", null)
                return
            }
        }

        val maxDurationMs = (call.argument<Number>("max_duration_ms")?.toLong() ?: 20_000L)
            .coerceIn(1_000L, 60_000L)
        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) {
            result.error("unsupported_audio", "设备不支持 48 kHz 单声道录音。", null)
            return
        }

        val recorder = createAudioRecord(max(minBuffer, SAMPLE_RATE / 5 * BYTES_PER_SAMPLE))
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            result.error("recorder_init_failed", "无法初始化设备麦克风。", null)
            return
        }
        val id = "rec_${System.currentTimeMillis()}"
        val directory = File(cacheDir, "recordings").apply { mkdirs() }
        val file = File(directory, "$id.wav")
        val startedAt = System.currentTimeMillis()

        synchronized(stateLock) {
            activeRecorder = recorder
            activeFile = file
            activeId = id
            completedRecording = null
            completedFailure = null
            recording = true
        }
        recorder.startRecording()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        Log.i(TAG, "event=recording_started recording_id=$id max_duration_ms=$maxDurationMs")
        worker.execute { captureToWav(recorder, file, id, maxDurationMs) }
        result.success(mapOf("id" to id, "started_at_ms" to startedAt))
    }

    private fun createAudioRecord(bufferSize: Int): AudioRecord {
        val preferredSource = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            MediaRecorder.AudioSource.UNPROCESSED
        } else {
            MediaRecorder.AudioSource.MIC
        }
        val preferred = AudioRecord(
            preferredSource,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize,
        )
        if (preferred.state == AudioRecord.STATE_INITIALIZED || preferredSource == MediaRecorder.AudioSource.MIC) {
            return preferred
        }
        preferred.release()
        return AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize,
        )
    }

    private fun captureToWav(
        recorder: AudioRecord,
        file: File,
        id: String,
        maxDurationMs: Long,
    ) {
        val buffer = ByteArray(max(AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        ), 4096))
        val maxDataBytes = maxDurationMs * SAMPLE_RATE * CHANNEL_COUNT * BYTES_PER_SAMPLE / 1000
        var dataBytes = 0L
        var failure: Exception? = null
        try {
            FileOutputStream(file).use { output ->
                output.write(ByteArray(44))
                while (recording && dataBytes < maxDataBytes) {
                    val count = recorder.read(buffer, 0, buffer.size)
                    if (count > 0) {
                        val allowed = minOf(count.toLong(), maxDataBytes - dataBytes).toInt()
                        output.write(buffer, 0, allowed)
                        dataBytes += allowed
                    } else if (count < 0) {
                        throw IllegalStateException("AudioRecord read failed: $count")
                    }
                }
            }
            writeWavHeader(file, dataBytes)
        } catch (error: Exception) {
            failure = error
            Log.e(TAG, "event=recording_capture_failed recording_id=$id", error)
            file.delete()
        } finally {
            try {
                recorder.stop()
            } catch (_: IllegalStateException) {
                // The recorder may already have stopped after a device interruption.
            }
            recorder.release()
            synchronized(stateLock) {
                recording = false
                activeRecorder = null
                if (failure == null) {
                    completedRecording = mapOf(
                        "id" to id,
                        "path" to file.absolutePath,
                        "duration_ms" to (dataBytes * 1000 / (SAMPLE_RATE * CHANNEL_COUNT * BYTES_PER_SAMPLE)),
                        "sample_rate" to SAMPLE_RATE,
                        "channel_count" to CHANNEL_COUNT,
                        "byte_length" to file.length().toInt(),
                    )
                    Log.i(
                        TAG,
                        "event=recording_completed recording_id=$id duration_ms=${dataBytes * 1000 / (SAMPLE_RATE * CHANNEL_COUNT * BYTES_PER_SAMPLE)} byte_length=${file.length()}",
                    )
                } else {
                    completedFailure = mapOf(
                        "code" to "recording_capture_failed",
                        "message" to (failure.message ?: "录音设备读取失败。"),
                    )
                }
            }
        }
    }

    private fun finishRecording(result: MethodChannel.Result, delete: Boolean) {
        recording = false
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        worker.execute {
            val value = synchronized(stateLock) {
                val completed = completedRecording
                completedRecording = null
                activeId = null
                activeFile = null
                completed
            }
            val failure = synchronized(stateLock) {
                val value = completedFailure
                completedFailure = null
                value
            }
            if (delete && value != null) {
                File(value["path"] as String).delete()
            }
            runOnUiThread {
                when {
                    delete -> result.success(null)
                    value != null -> result.success(value)
                    failure != null -> result.error(
                        failure["code"] ?: "recording_failed",
                        failure["message"] ?: "录音失败。",
                        null,
                    )
                    else -> result.error("no_recording", "没有可保存的录音。", null)
                }
            }
        }
    }

    private fun writeWavHeader(file: File, dataBytes: Long) {
        val byteRate = SAMPLE_RATE * CHANNEL_COUNT * BYTES_PER_SAMPLE
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray(Charsets.US_ASCII))
            putInt((36 + dataBytes).toInt())
            put("WAVE".toByteArray(Charsets.US_ASCII))
            put("fmt ".toByteArray(Charsets.US_ASCII))
            putInt(16)
            putShort(1.toShort())
            putShort(CHANNEL_COUNT.toShort())
            putInt(SAMPLE_RATE)
            putInt(byteRate)
            putShort((CHANNEL_COUNT * BYTES_PER_SAMPLE).toShort())
            putShort(16.toShort())
            put("data".toByteArray(Charsets.US_ASCII))
            putInt(dataBytes.toInt())
        }.array()
        RandomAccessFile(file, "rw").use { wav ->
            wav.seek(0)
            wav.write(header)
        }
    }

    override fun onDestroy() {
        recording = false
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        worker.shutdown()
        super.onDestroy()
    }
}
