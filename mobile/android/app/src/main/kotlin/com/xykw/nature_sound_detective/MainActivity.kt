package com.xykw.nature_sound_detective

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import android.view.WindowManager
import androidx.annotation.NonNull
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.GainProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
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
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.xykw.nature_sound/audio_recorder"
        private const val MEDIA_CHANNEL = "com.xykw.nature_sound/media_composer"
        private const val BACKGROUND_CHANNEL = "com.xykw.nature_sound/creation_background"
        private const val MAP_PRIVACY_CHANNEL = AMAP_PRIVACY_CHANNEL
        private const val TAG = "NatureAudio"
        private const val PERMISSION_REQUEST = 7301
        private const val AUDIO_PICK_REQUEST = 7302
        private const val SAMPLE_RATE = 48_000
        private const val CHANNEL_COUNT = 1
        private const val BYTES_PER_SAMPLE = 2
        private const val MAX_IMPORT_BYTES = 150L * 1024 * 1024
        private const val MAX_IMPORT_DURATION_SECONDS = 600L
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
    private var audioPickResult: MethodChannel.Result? = null
    private var compositionResult: MethodChannel.Result? = null
    private var activeTransformer: Transformer? = null
    @Volatile private var currentRms = 0.0
    @Volatile private var currentPeak = 0.0
    @Volatile private var currentAudioSource = "MIC"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::handleMethodCall)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "compose" -> composeCreation(call, result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_CHANNEL)
            .setMethodCallHandler { call, result ->
                val recordId = call.argument<String>("record_id").orEmpty()
                when (call.method) {
                    "schedule" -> {
                        val taskPath = call.argument<String>("task_path").orEmpty()
                        if (recordId.isBlank() || taskPath.isBlank()) {
                            result.error("invalid_task", "缺少后台任务信息。", null)
                        } else {
                            CreationPollWorker.schedule(this, recordId, taskPath)
                            result.success(null)
                        }
                    }
                    "cancel" -> {
                        if (recordId.isNotBlank()) CreationPollWorker.cancel(this, recordId)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MAP_PRIVACY_CHANNEL)
            .setMethodCallHandler { call, result ->
                val preferences = getSharedPreferences(
                    AMAP_PRIVACY_PREFERENCES,
                    MODE_PRIVATE,
                )
                when (call.method) {
                    "isAvailable" -> result.success(BuildConfig.AMAP_NATIVE_MAP_ENABLED)
                    "hasConsent" -> result.success(
                        preferences.getBoolean(AMAP_PRIVACY_ACCEPTED, false),
                    )
                    "accept" -> {
                        preferences.edit().putBoolean(AMAP_PRIVACY_ACCEPTED, true).apply()
                        result.success(null)
                    }
                    "revoke" -> {
                        preferences.edit().putBoolean(AMAP_PRIVACY_ACCEPTED, false).apply()
                        result.success(null)
                    }
                    "openPrivacyPolicy" -> {
                        startActivity(
                            Intent(
                                Intent.ACTION_VIEW,
                                Uri.parse("https://lbs.amap.com/pages/privacy/"),
                            ),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        flutterEngine.platformViewsController.registry.registerViewFactory(
            AMAP_VIEW_TYPE,
            AmapSoundscapeViewFactory(flutterEngine.dartExecutor.binaryMessenger),
        )
    }

    @UnstableApi
    private fun composeCreation(call: MethodCall, result: MethodChannel.Result) {
        if (compositionResult != null) {
            result.error("composition_busy", "已有作品正在合成。", null)
            return
        }
        val video = requiredFile(call, "video_path", result) ?: return
        val musicValue = call.argument<String>("music_path").orEmpty()
        val music = musicValue.takeIf { it.isNotBlank() }
            ?.let(::File)
            ?.takeIf { it.isFile && it.length() > 0L }
        val nature = requiredFile(call, "nature_path", result) ?: return
        val narrationValue = call.argument<String>("narration_path").orEmpty()
        val narration = narrationValue.takeIf { it.isNotBlank() }?.let(::File)
        val outputValue = call.argument<String>("output_path").orEmpty()
        if (outputValue.isBlank()) {
            result.error("output_missing", "缺少合成输出路径。", null)
            return
        }
        val output = File(outputValue)
        output.parentFile?.mkdirs()
        output.delete()

        fun audioItem(file: File, gain: Float): EditedMediaItem =
            EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(file)))
                .setRemoveVideo(true)
                .setEffects(
                    Effects(
                        listOf(GainProcessor(ConstantGainProvider(gain))),
                        emptyList<Effect>(),
                    ),
                )
                .build()

        val videoItem = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(video)))
            .setRemoveAudio(true)
            .build()
        val sequences = mutableListOf(
            EditedMediaItemSequence.withAudioAndVideoFrom(listOf(videoItem)),
            EditedMediaItemSequence.withAudioFrom(listOf(audioItem(nature, 0.20f))),
        )
        if (music != null) {
            sequences += EditedMediaItemSequence.withAudioFrom(
                listOf(audioItem(music, 0.24f)),
            ).buildUpon().setIsLooping(true).build()
        }
        if (narration?.isFile == true && narration.length() > 0L) {
            sequences += EditedMediaItemSequence.withAudioFrom(
                listOf(audioItem(narration, 1.0f)),
            )
        }
        val composition = Composition.Builder(sequences).build()
        compositionResult = result
        activeTransformer = Transformer.Builder(this)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    compositionResult?.success(mapOf(
                        "path" to output.absolutePath,
                        "bytes" to output.length(),
                    ))
                    compositionResult = null
                    activeTransformer = null
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    output.delete()
                    compositionResult?.error(
                        "composition_failed",
                        exportException.message ?: "本机音视频合成失败。",
                        null,
                    )
                    compositionResult = null
                    activeTransformer = null
                }
            })
            .build()
        activeTransformer?.start(composition, output.absolutePath)
    }

    private fun requiredFile(
        call: MethodCall,
        name: String,
        result: MethodChannel.Result,
    ): File? {
        val value = call.argument<String>(name).orEmpty()
        val file = File(value)
        if (value.isBlank() || !file.isFile || file.length() <= 0L) {
            result.error("media_missing", "合成素材不存在：$name", null)
            return null
        }
        return file
    }

    @UnstableApi
    private class ConstantGainProvider(private val gain: Float) : GainProcessor.GainProvider {
        override fun getGainFactorAtSamplePosition(samplePosition: Long, sampleRate: Int): Float = gain

        override fun isUnityUntil(samplePosition: Long, sampleRate: Int): Long = C.TIME_UNSET
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
            "pickAudio" -> pickAudio(result)
            "getRecordingLevel" -> result.success(mapOf(
                "rms" to currentRms,
                "peak" to currentPeak,
                "source" to currentAudioSource,
            ))
            "startRecording" -> startRecording(call, result)
            "stopRecording" -> finishRecording(result, delete = false)
            "cancelRecording" -> finishRecording(result, delete = true)
            "loadDebugDemo" -> loadDebugDemo(result)
            else -> result.notImplemented()
        }
    }

    private fun pickAudio(result: MethodChannel.Result) {
        if (audioPickResult != null) {
            result.error("audio_picker_busy", "文件选择器已经打开。", null)
            return
        }
        audioPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(
                "audio/wav",
                "audio/x-wav",
                "audio/mpeg",
                "audio/mp4",
                "audio/aac",
                "audio/flac",
                "audio/ogg",
            ))
        }
        startActivityForResult(intent, AUDIO_PICK_REQUEST)
    }

    @Deprecated("Deprecated in Android SDK, retained for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != AUDIO_PICK_REQUEST) return
        val pending = audioPickResult ?: return
        audioPickResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(null)
            return
        }
        worker.execute {
            try {
                val imported = importAudio(uri)
                runOnUiThread { pending.success(imported) }
            } catch (error: Exception) {
                Log.e(TAG, "event=audio_import_failed", error)
                runOnUiThread {
                    pending.error(
                        "audio_import_failed",
                        error.message ?: "无法读取这个音频文件。",
                        null,
                    )
                }
            }
        }
    }

    private fun importAudio(uri: Uri): Map<String, Any> {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    val size = cursor.getLong(sizeIndex)
                    require(size <= MAX_IMPORT_BYTES) { "音频文件不能超过 150 MB。" }
                }
            }
        }
        val id = "import_${System.currentTimeMillis()}"
        val directory = File(cacheDir, "imports").apply { mkdirs() }
        val source = File(directory, "$id.source")
        val output = File(directory, "$id.wav")
        try {
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(source).use { destination ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var copied = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        copied += count
                        require(copied <= MAX_IMPORT_BYTES) { "音频文件不能超过 150 MB。" }
                        destination.write(buffer, 0, count)
                    }
                }
            } ?: error("无法打开所选音频。")
            require(source.length() > 0L) { "所选音频是空文件。" }
            val decoded = decodeAudioToMonoWav(source, output)
            Log.i(
                TAG,
                "event=audio_import_completed duration_ms=${decoded.durationMs} " +
                    "sample_rate=${decoded.sampleRate} byte_length=${output.length()}",
            )
            return mapOf(
                "id" to id,
                "path" to output.absolutePath,
                "duration_ms" to decoded.durationMs,
                "sample_rate" to decoded.sampleRate,
                "channel_count" to CHANNEL_COUNT,
                "byte_length" to output.length().toInt(),
            )
        } finally {
            source.delete()
            if (output.length() <= 44L) output.delete()
        }
    }

    private data class DecodedAudio(val sampleRate: Int, val durationMs: Long)

    private fun decodeAudioToMonoWav(source: File, output: File): DecodedAudio {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(source.absolutePath)
            val trackIndex = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: error("文件中没有可识别的音轨。")
            extractor.selectTrack(trackIndex)
            val inputFormat = extractor.getTrackFormat(trackIndex)
            if (inputFormat.containsKey(MediaFormat.KEY_DURATION)) {
                val durationUs = inputFormat.getLong(MediaFormat.KEY_DURATION)
                require(durationUs in 1..MAX_IMPORT_DURATION_SECONDS * 1_000_000L) {
                    "请选择 10 分钟以内的音频。"
                }
            }
            val mime = inputFormat.getString(MediaFormat.KEY_MIME)
                ?: error("无法识别音频编码。")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                inputFormat.setInteger(
                    MediaFormat.KEY_PCM_ENCODING,
                    AudioFormat.ENCODING_PCM_16BIT,
                )
            }
            val activeDecoder = MediaCodec.createDecoderByType(mime)
            decoder = activeDecoder
            activeDecoder.configure(inputFormat, null, null, 0)
            activeDecoder.start()

            var sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var pcmEncoding = AudioFormat.ENCODING_PCM_16BIT
            var inputEnded = false
            var outputEnded = false
            var dataBytes = 0L
            val bufferInfo = MediaCodec.BufferInfo()
            output.parentFile?.mkdirs()
            FileOutputStream(output).use { wav ->
                wav.write(ByteArray(44))
                while (!outputEnded) {
                    if (!inputEnded) {
                        val inputIndex = activeDecoder.dequeueInputBuffer(10_000)
                        if (inputIndex >= 0) {
                            val inputBuffer = activeDecoder.getInputBuffer(inputIndex)
                                ?: error("无法取得音频解码输入缓冲区。")
                            val size = extractor.readSampleData(inputBuffer, 0)
                            if (size < 0) {
                                activeDecoder.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    0,
                                    0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                )
                                inputEnded = true
                            } else {
                                activeDecoder.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    size,
                                    extractor.sampleTime,
                                    0,
                                )
                                extractor.advance()
                            }
                        }
                    }
                    when (val outputIndex = activeDecoder.dequeueOutputBuffer(bufferInfo, 10_000)) {
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            val format = activeDecoder.outputFormat
                            sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                            channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                            if (format.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                                pcmEncoding = format.getInteger(MediaFormat.KEY_PCM_ENCODING)
                            }
                        }
                        MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                        else -> if (outputIndex >= 0) {
                            val decoded = activeDecoder.getOutputBuffer(outputIndex)
                            if (decoded != null && bufferInfo.size > 0) {
                                decoded.position(bufferInfo.offset)
                                decoded.limit(bufferInfo.offset + bufferInfo.size)
                                dataBytes += writeMonoPcm(
                                    decoded.slice().order(ByteOrder.nativeOrder()),
                                    channels,
                                    pcmEncoding,
                                    wav,
                                )
                                require(
                                    dataBytes <= sampleRate * BYTES_PER_SAMPLE *
                                        MAX_IMPORT_DURATION_SECONDS,
                                ) { "请选择 10 分钟以内的音频。" }
                            }
                            outputEnded = bufferInfo.flags and
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            activeDecoder.releaseOutputBuffer(outputIndex, false)
                        }
                    }
                }
            }
            require(dataBytes > 0L) { "音频解码后没有有效声音数据。" }
            writeWavHeader(output, dataBytes, sampleRate, CHANNEL_COUNT)
            return DecodedAudio(
                sampleRate = sampleRate,
                durationMs = dataBytes * 1000L / (sampleRate * BYTES_PER_SAMPLE),
            )
        } finally {
            try {
                decoder?.stop()
            } catch (_: Exception) {
                // Decoder may not have reached the started state.
            }
            decoder?.release()
            extractor.release()
        }
    }

    private fun writeMonoPcm(
        buffer: ByteBuffer,
        channels: Int,
        pcmEncoding: Int,
        output: FileOutputStream,
    ): Long {
        require(channels > 0) { "音频声道信息无效。" }
        require(
            pcmEncoding == AudioFormat.ENCODING_PCM_16BIT ||
                pcmEncoding == AudioFormat.ENCODING_PCM_FLOAT,
        ) { "设备返回了暂不支持的 PCM 格式：$pcmEncoding" }
        val bytesPerInputSample = if (pcmEncoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2
        val frameCount = buffer.remaining() / (bytesPerInputSample * channels)
        val mono = ByteBuffer.allocate(frameCount * 2).order(ByteOrder.LITTLE_ENDIAN)
        repeat(frameCount) {
            var sum = 0.0
            repeat(channels) {
                sum += if (pcmEncoding == AudioFormat.ENCODING_PCM_FLOAT) {
                    buffer.float.coerceIn(-1f, 1f).toDouble()
                } else {
                    buffer.short / 32768.0
                }
            }
            val sample = ((sum / channels).coerceIn(-1.0, 1.0) * 32767).toInt()
            mono.putShort(sample.toShort())
        }
        output.write(mono.array())
        return mono.capacity().toLong()
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
        currentRms = 0.0
        currentPeak = 0.0
        recorder.startRecording()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        Log.i(
            TAG,
            "event=recording_started recording_id=$id max_duration_ms=$maxDurationMs " +
                "audio_source=$currentAudioSource",
        )
        worker.execute { captureToWav(recorder, file, id, maxDurationMs) }
        result.success(mapOf("id" to id, "started_at_ms" to startedAt))
    }

    private fun createAudioRecord(bufferSize: Int): AudioRecord {
        val audioManager = getSystemService(AudioManager::class.java)
        val supportsUnprocessed = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            audioManager.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true"
        val preferredSource = if (supportsUnprocessed) {
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
            currentAudioSource = if (preferredSource == MediaRecorder.AudioSource.UNPROCESSED) {
                "UNPROCESSED"
            } else {
                "MIC"
            }
            return preferred
        }
        preferred.release()
        currentAudioSource = "MIC"
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
                        updateRecordingLevel(buffer, allowed)
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

    private fun updateRecordingLevel(buffer: ByteArray, count: Int) {
        val samples = count / BYTES_PER_SAMPLE
        if (samples <= 0) return
        var squares = 0.0
        var peak = 0.0
        var offset = 0
        repeat(samples) {
            val value = ((buffer[offset].toInt() and 0xff) or
                (buffer[offset + 1].toInt() shl 8)).toShort().toInt() / 32768.0
            val absolute = kotlin.math.abs(value)
            squares += value * value
            peak = max(peak, absolute)
            offset += 2
        }
        currentRms = sqrt(squares / samples)
        currentPeak = peak
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

    private fun writeWavHeader(
        file: File,
        dataBytes: Long,
        sampleRate: Int = SAMPLE_RATE,
        channelCount: Int = CHANNEL_COUNT,
    ) {
        val byteRate = sampleRate * channelCount * BYTES_PER_SAMPLE
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray(Charsets.US_ASCII))
            putInt((36 + dataBytes).toInt())
            put("WAVE".toByteArray(Charsets.US_ASCII))
            put("fmt ".toByteArray(Charsets.US_ASCII))
            putInt(16)
            putShort(1.toShort())
            putShort(channelCount.toShort())
            putInt(sampleRate)
            putInt(byteRate)
            putShort((channelCount * BYTES_PER_SAMPLE).toShort())
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
        activeTransformer?.cancel()
        compositionResult?.error("composition_cancelled", "应用关闭，合成已取消。", null)
        compositionResult = null
        audioPickResult?.error("audio_picker_cancelled", "应用关闭，文件选择已取消。", null)
        audioPickResult = null
        activeTransformer = null
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        worker.shutdown()
        super.onDestroy()
    }
}
