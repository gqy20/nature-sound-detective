import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/media/media_composer.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/storage/creation_store.dart';
import 'package:path_provider/path_provider.dart';

typedef CreationProgress = void Function(CreationUpdate update);

abstract interface class CreationService {
  Future<CreationArtifacts> create({
    required CreationSettings settings,
    required String subject,
    required String location,
    required String sourceAudioPath,
    required CreationProgress onProgress,
  });

  Future<CreationArtifacts> resume({
    required CreationSettings settings,
    required CreationRecord record,
    required CreationProgress onProgress,
  });
}

class DirectCreationService implements CreationService {
  DirectCreationService({
    http.Client? client,
    Future<Directory> Function()? directoryProvider,
    CreationStore? store,
    MediaComposer? composer,
    this.pollInterval = const Duration(seconds: 15),
    this.videoTimeout = const Duration(minutes: 7),
  }) : _client = client ?? http.Client(),
       _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory,
       _store = store ?? CreationStore(directoryProvider: directoryProvider),
       _composer = composer ?? const AndroidMediaComposer();

  final http.Client _client;
  final Future<Directory> Function() _directoryProvider;
  final CreationStore _store;
  final MediaComposer _composer;
  final Duration pollInterval;
  final Duration videoTimeout;

  @override
  Future<CreationArtifacts> create({
    required CreationSettings settings,
    required String subject,
    required String location,
    required String sourceAudioPath,
    required CreationProgress onProgress,
  }) async {
    if (!settings.canCreate) {
      AppLog.warning('creation', 'configuration_missing');
      throw const CreationException('请先配置 MiniMax 和阿里云百炼 API Key。');
    }
    final root = await _directoryProvider();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final directory = Directory('${root.path}/creations/$id');
    await directory.create(recursive: true);
    final source = File(sourceAudioPath);
    if (!await source.exists()) {
      AppLog.warning('creation', 'source_audio_missing', traceId: id);
      throw const CreationException('原始录音已经不存在，请重新录制。');
    }
    AppLog.info(
      'creation',
      'creation_started',
      traceId: id,
      fields: {
        'source_bytes': await source.length(),
        'music_model': settings.minimaxMusicModel,
        'video_model': settings.wanVideoModel,
        'region': settings.dashscopeRegion,
      },
    );
    final copiedSource = File('${directory.path}/nature_original.wav');
    await source.copy(copiedSource.path);
    final now = DateTime.now();
    final record = CreationRecord(
      id: id,
      subject: subject,
      location: location,
      createdAt: now,
      updatedAt: now,
      stage: CreationStage.idle,
      message: '准备创作',
      directoryPath: directory.path,
      sourceAudioPath: copiedSource.path,
    );
    await _store.save(record);
    return resume(settings: settings, record: record, onProgress: onProgress);
  }

  @override
  Future<CreationArtifacts> resume({
    required CreationSettings settings,
    required CreationRecord record,
    required CreationProgress onProgress,
  }) async {
    if (!settings.canCreate) {
      throw const CreationException('请先配置 MiniMax 和阿里云百炼 API Key。');
    }
    var current = record;
    AppLog.info(
      'creation',
      'pipeline_started',
      traceId: record.id,
      fields: {
        'resume':
            record.stage != CreationStage.idle ||
            record.wanTaskId.isNotEmpty ||
            record.musicPath.isNotEmpty ||
            record.videoPath.isNotEmpty,
        'stage': record.stage.name,
        'has_music': record.musicPath.isNotEmpty,
        'has_video': record.videoPath.isNotEmpty,
        'has_final_video': record.finalVideoPath.isNotEmpty,
      },
    );
    final directory = Directory(record.directoryPath);
    await directory.create(recursive: true);
    final musicFile = File('${directory.path}/nature_music.mp3');
    final narrationFile = File('${directory.path}/nature_narration.mp3');
    final videoFile = File('${directory.path}/nature_video.mp4');
    final finalVideoFile = File('${directory.path}/nature_story.mp4');

    Future<void> progress(CreationStage stage, String message) async {
      current = current.copyWith(stage: stage, message: message);
      await _store.save(current);
      AppLog.info(
        'creation',
        'stage_changed',
        traceId: current.id,
        fields: {'stage': stage.name},
      );
      onProgress(
        CreationUpdate(
          stage: stage,
          message: message,
          taskId: current.wanTaskId,
          recordId: current.id,
          directoryPath: current.directoryPath,
        ),
      );
    }

    if (!await musicFile.exists()) {
      await progress(CreationStage.generatingMusic, '正在生成自然配乐');
      final stopwatch = Stopwatch()..start();
      try {
        await _generateMusic(
          settings: settings,
          prompt: _musicPrompt(current.subject, current.location),
          destination: musicFile,
          traceId: current.id,
        );
        current = current.copyWith(musicPath: musicFile.path, musicError: '');
        await _store.save(current);
        AppLog.info(
          'creation',
          'music_generation_succeeded',
          traceId: current.id,
          fields: {
            'duration_ms': stopwatch.elapsedMilliseconds,
            'byte_length': await musicFile.length(),
          },
        );
      } catch (error, stackTrace) {
        AppLog.warning(
          'creation',
          'music_generation_failed',
          traceId: current.id,
          fields: {'duration_ms': stopwatch.elapsedMilliseconds},
          error: error,
          stackTrace: stackTrace,
        );
        current = current.copyWith(musicError: _message(error));
        await _store.save(current);
      }
    }

    if (!await narrationFile.exists()) {
      await progress(CreationStage.generatingNarration, '正在生成自然科普旁白');
      final stopwatch = Stopwatch()..start();
      try {
        await _generateNarration(
          settings: settings,
          text: _narrationText(current.subject, current.location),
          destination: narrationFile,
          traceId: current.id,
        );
        current = current.copyWith(narrationPath: narrationFile.path);
        await _store.save(current);
        AppLog.info(
          'creation',
          'narration_generation_succeeded',
          traceId: current.id,
          fields: {
            'duration_ms': stopwatch.elapsedMilliseconds,
            'byte_length': await narrationFile.length(),
          },
        );
      } catch (error, stackTrace) {
        AppLog.warning(
          'creation',
          'narration_generation_failed',
          traceId: current.id,
          fields: {'duration_ms': stopwatch.elapsedMilliseconds},
          error: error,
          stackTrace: stackTrace,
        );
        // Narration is optional; a music-and-nature mix is still a valid work.
      }
    }

    if (!await videoFile.exists()) {
      final stopwatch = Stopwatch()..start();
      try {
        var taskId = current.wanTaskId;
        if (taskId.isEmpty) {
          await progress(CreationStage.submittingVideo, '正在提交自然短片');
          taskId = await _createWanTask(
            settings: settings,
            prompt: _videoPrompt(current.subject, current.location),
            traceId: current.id,
          );
          current = current.copyWith(wanTaskId: taskId, videoError: '');
          await _store.save(current);
        }
        await progress(CreationStage.waitingForVideo, '视频正在生成，通常需要 1–5 分钟');
        final videoUrl = await _waitForWanVideo(
          settings: settings,
          taskId: taskId,
          traceId: current.id,
        );
        await progress(CreationStage.downloadingVideo, '正在保存生成的视频');
        await _download(
          Uri.parse(videoUrl),
          videoFile,
          traceId: current.id,
          assetType: 'video',
        );
        current = current.copyWith(videoPath: videoFile.path, videoError: '');
        await _store.save(current);
        AppLog.info(
          'creation',
          'video_generation_succeeded',
          traceId: current.id,
          fields: {
            'duration_ms': stopwatch.elapsedMilliseconds,
            'byte_length': await videoFile.length(),
          },
        );
      } catch (error, stackTrace) {
        AppLog.warning(
          'creation',
          'video_generation_failed',
          traceId: current.id,
          fields: {'duration_ms': stopwatch.elapsedMilliseconds},
          error: error,
          stackTrace: stackTrace,
        );
        current = current.copyWith(videoError: _message(error));
        await _store.save(current);
      }
    }

    if (await videoFile.exists() &&
        await musicFile.exists() &&
        !await finalVideoFile.exists()) {
      await progress(CreationStage.composing, '正在本机合成音乐、旁白和自然原声');
      final stopwatch = Stopwatch()..start();
      try {
        await _composer.compose(
          videoPath: videoFile.path,
          musicPath: musicFile.path,
          naturePath: current.sourceAudioPath,
          narrationPath: await narrationFile.exists() ? narrationFile.path : '',
          outputPath: finalVideoFile.path,
        );
        current = current.copyWith(
          finalVideoPath: finalVideoFile.path,
          compositionError: '',
        );
        await _store.save(current);
        AppLog.info(
          'creation',
          'composition_succeeded',
          traceId: current.id,
          fields: {
            'duration_ms': stopwatch.elapsedMilliseconds,
            'byte_length': await finalVideoFile.length(),
            'has_narration': await narrationFile.exists(),
          },
        );
      } catch (error, stackTrace) {
        AppLog.warning(
          'creation',
          'composition_failed',
          traceId: current.id,
          fields: {'duration_ms': stopwatch.elapsedMilliseconds},
          error: error,
          stackTrace: stackTrace,
        );
        current = current.copyWith(compositionError: _message(error));
        await _store.save(current);
      }
    }

    final artifacts = CreationArtifacts(
      id: current.id,
      directoryPath: directory.path,
      musicPath: await musicFile.exists() ? musicFile.path : null,
      narrationPath: await narrationFile.exists() ? narrationFile.path : null,
      videoPath: await videoFile.exists() ? videoFile.path : null,
      finalVideoPath: await finalVideoFile.exists()
          ? finalVideoFile.path
          : null,
      musicError: current.musicError.isEmpty ? null : current.musicError,
      videoError: current.videoError.isEmpty ? null : current.videoError,
      wanTaskId: current.wanTaskId,
    );
    if (!artifacts.hasMusic && !artifacts.hasVideo) {
      AppLog.error(
        'creation',
        'creation_failed',
        traceId: current.id,
        fields: {
          'music_failed': current.musicError.isNotEmpty,
          'video_failed': current.videoError.isNotEmpty,
        },
      );
      throw CreationException(
        [
          current.musicError,
          current.videoError,
        ].where((value) => value.isNotEmpty).join('\n'),
      );
    }
    final finalStage = artifacts.isComplete
        ? CreationStage.completed
        : CreationStage.partial;
    final finalMessage = artifacts.isComplete ? '自然声音作品已经完成' : '部分作品已经完成，可稍后继续';
    await progress(finalStage, finalMessage);
    AppLog.info(
      'creation',
      'creation_completed',
      traceId: current.id,
      fields: {
        'complete': artifacts.isComplete,
        'has_music': artifacts.hasMusic,
        'has_video': artifacts.hasVideo,
        'has_final_video': artifacts.hasFinalVideo,
      },
    );
    return artifacts;
  }

  Future<void> _generateMusic({
    required CreationSettings settings,
    required String prompt,
    required File destination,
    required String traceId,
  }) async {
    final stopwatch = Stopwatch()..start();
    final response = await _client
        .post(
          Uri.parse('https://api.minimaxi.com/v1/music_generation'),
          headers: {
            HttpHeaders.authorizationHeader:
                'Bearer ${settings.minimaxApiKey.trim()}',
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          body: jsonEncode({
            'model': settings.minimaxMusicModel.trim(),
            'prompt': prompt,
            'is_instrumental': true,
            'stream': false,
            'output_format': 'url',
            'aigc_watermark': true,
            'audio_setting': {
              'sample_rate': 44100,
              'bitrate': 256000,
              'format': 'mp3',
            },
          }),
        )
        .timeout(const Duration(minutes: 5));
    AppLog.info(
      'creation',
      'provider_response_received',
      traceId: traceId,
      fields: {
        'provider': 'minimax',
        'operation': 'music',
        'status_code': response.statusCode,
        'duration_ms': stopwatch.elapsedMilliseconds,
      },
    );
    final payload = _jsonObject(response.body, 'MiniMax 音乐');
    _checkHttp(response, payload, 'MiniMax 音乐');
    _checkMiniMax(payload, 'MiniMax 音乐');
    final data = payload['data'];
    final audio = data is Map<String, Object?>
        ? data['audio']?.toString()
        : null;
    if (audio == null || audio.isEmpty) {
      throw const CreationException('MiniMax 没有返回音乐文件。');
    }
    if (audio.startsWith('http://') || audio.startsWith('https://')) {
      await _download(
        Uri.parse(audio),
        destination,
        traceId: traceId,
        assetType: 'music',
      );
    } else {
      await destination.writeAsBytes(_decodeHex(audio), flush: true);
    }
  }

  Future<void> _generateNarration({
    required CreationSettings settings,
    required String text,
    required File destination,
    required String traceId,
  }) async {
    final stopwatch = Stopwatch()..start();
    final response = await _client
        .post(
          Uri.parse('https://api.minimaxi.com/v1/t2a_v2'),
          headers: {
            HttpHeaders.authorizationHeader:
                'Bearer ${settings.minimaxApiKey.trim()}',
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          body: jsonEncode({
            'model': settings.minimaxSpeechModel.trim(),
            'text': text,
            'stream': false,
            'voice_setting': {
              'voice_id': settings.minimaxSpeechVoice.trim(),
              'speed': 0.95,
              'vol': 1.0,
              'pitch': 0,
              'emotion': 'calm',
            },
            'audio_setting': {
              'sample_rate': 32000,
              'bitrate': 128000,
              'format': 'mp3',
              'channel': 1,
            },
            'language_boost': 'Chinese',
          }),
        )
        .timeout(const Duration(seconds: 90));
    AppLog.info(
      'creation',
      'provider_response_received',
      traceId: traceId,
      fields: {
        'provider': 'minimax',
        'operation': 'narration',
        'status_code': response.statusCode,
        'duration_ms': stopwatch.elapsedMilliseconds,
      },
    );
    final payload = _jsonObject(response.body, 'MiniMax 旁白');
    _checkHttp(response, payload, 'MiniMax 旁白');
    _checkMiniMax(payload, 'MiniMax 旁白');
    final data = payload['data'];
    final audio = data is Map<String, Object?>
        ? data['audio']?.toString()
        : null;
    if (audio == null || audio.isEmpty) {
      throw const CreationException('MiniMax 没有返回旁白音频。');
    }
    await destination.writeAsBytes(_decodeHex(audio), flush: true);
  }

  Future<String> _createWanTask({
    required CreationSettings settings,
    required String prompt,
    required String traceId,
  }) async {
    final stopwatch = Stopwatch()..start();
    final response = await _client
        .post(
          Uri.parse(
            '${settings.dashscopeBaseUrl}/api/v1/services/aigc/video-generation/video-synthesis',
          ),
          headers: {
            HttpHeaders.authorizationHeader:
                'Bearer ${settings.dashscopeApiKey.trim()}',
            HttpHeaders.contentTypeHeader: 'application/json',
            'X-DashScope-Async': 'enable',
          },
          body: jsonEncode({
            'model': settings.wanVideoModel.trim(),
            'input': {
              'prompt': prompt,
              'negative_prompt': '字幕，文字，儿童正脸，捕捉动物，触摸动物，畸形，低清晰度',
            },
            'parameters': {
              'resolution': '720P',
              'ratio': '9:16',
              'duration': 10,
              'prompt_extend': true,
              'watermark': true,
            },
          }),
        )
        .timeout(const Duration(seconds: 90));
    AppLog.info(
      'creation',
      'provider_response_received',
      traceId: traceId,
      fields: {
        'provider': 'dashscope',
        'operation': 'submit_video',
        'status_code': response.statusCode,
        'duration_ms': stopwatch.elapsedMilliseconds,
      },
    );
    final payload = _jsonObject(response.body, 'Wan 视频');
    _checkHttp(response, payload, 'Wan 视频');
    final output = payload['output'];
    final taskId = output is Map<String, Object?>
        ? output['task_id']?.toString()
        : null;
    if (taskId == null || taskId.isEmpty) {
      throw CreationException(_apiMessage(payload) ?? 'Wan 没有返回任务 ID。');
    }
    return taskId;
  }

  Future<String> _waitForWanVideo({
    required CreationSettings settings,
    required String taskId,
    required String traceId,
  }) async {
    final deadline = DateTime.now().add(videoTimeout);
    String? previousStatus;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
      final response = await _client
          .get(
            Uri.parse('${settings.dashscopeBaseUrl}/api/v1/tasks/$taskId'),
            headers: {
              HttpHeaders.authorizationHeader:
                  'Bearer ${settings.dashscopeApiKey.trim()}',
            },
          )
          .timeout(const Duration(seconds: 60));
      final payload = _jsonObject(response.body, 'Wan 视频');
      _checkHttp(response, payload, 'Wan 视频');
      final output = payload['output'];
      if (output is! Map<String, Object?>) {
        throw const CreationException('Wan 返回了无法识别的任务状态。');
      }
      final status = output['task_status']?.toString().toUpperCase();
      if (status != previousStatus) {
        AppLog.info(
          'creation',
          'video_status_changed',
          traceId: traceId,
          fields: {'status': status ?? 'MISSING'},
        );
        previousStatus = status;
      }
      if (status == 'SUCCEEDED') {
        final url = output['video_url']?.toString();
        if (url == null || url.isEmpty) {
          throw const CreationException('Wan 视频完成但没有返回下载地址。');
        }
        return url;
      }
      if ({'FAILED', 'CANCELED', 'UNKNOWN'}.contains(status)) {
        throw CreationException(
          output['message']?.toString() ?? 'Wan 视频任务失败：$status',
        );
      }
    }
    throw const CreationException('Wan 视频生成超过 7 分钟，可稍后重试。');
  }

  Future<void> _download(
    Uri uri,
    File destination, {
    required String traceId,
    required String assetType,
  }) async {
    final stopwatch = Stopwatch()..start();
    final request = http.Request('GET', uri);
    final response = await _client
        .send(request)
        .timeout(const Duration(minutes: 3));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CreationException('素材下载失败（${response.statusCode}）。');
    }
    final sink = destination.openWrite();
    try {
      await response.stream.pipe(sink);
    } finally {
      await sink.close();
    }
    if (!await destination.exists() || await destination.length() == 0) {
      throw const CreationException('下载的素材文件为空。');
    }
    AppLog.info(
      'creation',
      'asset_downloaded',
      traceId: traceId,
      fields: {
        'asset_type': assetType,
        'duration_ms': stopwatch.elapsedMilliseconds,
        'byte_length': await destination.length(),
      },
    );
  }

  String _musicPrompt(String subject, String location) =>
      '为儿童自然观察创作一段温柔、清澈、富有呼吸感的纯音乐。地点是$location，声音主题是$subject。'
      '以木琴、轻柔弦乐、原声打击乐和空气感铺底，不要人声，不要歌词，不要戏剧化高潮，给自然原声留出空间。';

  String _videoPrompt(String subject, String location) =>
      '生成一支10秒的竖屏儿童自然科普短片。地点氛围：中国$location的城市公园，主题声音：$subject。'
      '清晨薄雾、柔和自然光、真实纪录片质感、缓慢稳定镜头。只展示环境和声音线索，不出现文字、字幕、儿童正脸，'
      '不表现捕捉或触摸野生动物。不确定具体物种时不要生成动物近景。';

  String _narrationText(String subject, String location) =>
      '在$location，我们听见了$subject。每一种自然声音，都在告诉我们环境正在发生什么。'
      '再安静听一听，它的节奏有没有变化？';

  Map<String, Object?> _jsonObject(String body, String service) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      // Handled with a user-facing provider error below.
    }
    throw CreationException('$service 返回了无法识别的数据。');
  }

  void _checkHttp(
    http.Response response,
    Map<String, Object?> payload,
    String service,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CreationException(
        _apiMessage(payload) ?? '$service 请求失败（${response.statusCode}）。',
      );
    }
  }

  void _checkMiniMax(Map<String, Object?> payload, String service) {
    final base = payload['base_resp'];
    if (base is Map<String, Object?>) {
      final code = base['status_code'];
      if (code != null && code != 0) {
        throw CreationException(
          base['status_msg']?.toString() ?? '$service 调用失败：$code',
        );
      }
    }
  }

  String? _apiMessage(Map<String, Object?> payload) {
    final output = payload['output'];
    if (output is Map<String, Object?> && output['message'] != null) {
      return output['message'].toString();
    }
    return payload['message']?.toString();
  }

  Uint8List _decodeHex(String value) {
    if (value.length.isOdd) {
      throw const CreationException('MiniMax 返回的音乐数据不完整。');
    }
    final bytes = Uint8List(value.length ~/ 2);
    for (var index = 0; index < value.length; index += 2) {
      final parsed = int.tryParse(value.substring(index, index + 2), radix: 16);
      if (parsed == null) {
        throw const CreationException('MiniMax 返回了无效的音乐数据。');
      }
      bytes[index ~/ 2] = parsed;
    }
    return bytes;
  }

  String _message(Object error) => switch (error) {
    CreationException() => error.message,
    TimeoutException() => '请求超时，请检查网络后重试。',
    SocketException() => '网络不可用，请检查连接后重试。',
    _ => '生成失败：$error',
  };
}

class CreationException implements Exception {
  const CreationException(this.message);

  final String message;

  @override
  String toString() => message;
}
