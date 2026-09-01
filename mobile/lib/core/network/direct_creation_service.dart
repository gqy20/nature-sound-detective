import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nature_sound_detective/core/ai/generated_prompts.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/media/media_composer.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/network/dashscope_capability_service.dart';
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
    CreationVisualMode visualMode = CreationVisualMode.environment,
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
    DashscopeCapabilityChecker? capabilityChecker,
    this.pollInterval = const Duration(seconds: 15),
    this.videoTimeout = const Duration(minutes: 7),
  }) : _client = client ?? http.Client(),
       _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory,
       _store = store ?? CreationStore(directoryProvider: directoryProvider),
       _composer = composer ?? const AndroidMediaComposer() {
    _capabilityChecker =
        capabilityChecker ?? DashscopeCapabilityService(client: _client);
  }

  final http.Client _client;
  final Future<Directory> Function() _directoryProvider;
  final CreationStore _store;
  final MediaComposer _composer;
  late final DashscopeCapabilityChecker _capabilityChecker;
  static const _videoDurationSeconds = 5;
  final Duration pollInterval;
  final Duration videoTimeout;

  @override
  Future<CreationArtifacts> create({
    required CreationSettings settings,
    required String subject,
    required String location,
    required String sourceAudioPath,
    required CreationProgress onProgress,
    CreationVisualMode visualMode = CreationVisualMode.environment,
  }) async {
    if (!settings.canCreate) {
      AppLog.warning('creation', 'configuration_missing');
      throw const CreationException('请先配置阿里云百炼 API Key。');
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
        'music_provider': 'dashscope',
        'music_model': settings.dashscopeMusicModel,
        'speech_model': settings.dashscopeSpeechModel,
        'video_model': settings.wanVideoModel,
        'visual_mode': visualMode.name,
        'region': 'beijing',
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
      visualMode: visualMode,
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
      throw const CreationException('请先配置阿里云百炼 API Key。');
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

    final needsMusic = !await musicFile.exists();
    final needsNarration = !await narrationFile.exists();
    final needsVideo = !await videoFile.exists();
    await progress(CreationStage.generatingMusic, '正在检查创作模型权限');
    final capabilities = await _capabilityChecker.check(settings, [
      if (needsMusic) settings.dashscopeMusicModel,
      if (needsNarration) settings.dashscopeSpeechModel,
      if (needsVideo) settings.wanVideoModel,
    ], traceId: current.id);
    final musicPermission = capabilities.statusOf(
      settings.dashscopeMusicModel.trim(),
    );
    final narrationPermission = capabilities.statusOf(
      settings.dashscopeSpeechModel.trim(),
    );
    final videoPermission = capabilities.statusOf(
      settings.wanVideoModel.trim(),
    );
    if (needsMusic && musicPermission == DashscopeCapabilityStatus.denied) {
      current = current.copyWith(musicError: funMusicPermissionDeniedMessage);
    }
    if (needsNarration &&
        narrationPermission == DashscopeCapabilityStatus.denied) {
      current = current.copyWith(
        narrationError: dashscopeModelPermissionDeniedMessage(
          '自然科普旁白',
          settings.dashscopeSpeechModel.trim(),
        ),
      );
    }
    if (needsVideo && videoPermission == DashscopeCapabilityStatus.denied) {
      final message = dashscopeModelPermissionDeniedMessage(
        '自然短片',
        settings.wanVideoModel.trim(),
      );
      current = current.copyWith(videoError: message);
      await _store.save(current);
      await progress(CreationStage.failed, '视频模型未授权');
      throw CreationException(message);
    }
    await _store.save(current);

    if (needsMusic) {
      final stopwatch = Stopwatch()..start();
      if (musicPermission == DashscopeCapabilityStatus.denied) {
        AppLog.warning(
          'creation',
          'music_generation_skipped',
          traceId: current.id,
          fields: {
            'reason': 'model_permission_denied',
            'model': settings.dashscopeMusicModel.trim(),
            'duration_ms': stopwatch.elapsedMilliseconds,
          },
        );
      } else {
        await progress(CreationStage.generatingMusic, '正在生成自然配乐');
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
    }

    if (needsNarration) {
      if (narrationPermission == DashscopeCapabilityStatus.denied) {
        AppLog.warning(
          'creation',
          'narration_generation_skipped',
          traceId: current.id,
          fields: {
            'reason': 'model_permission_denied',
            'model': settings.dashscopeSpeechModel.trim(),
          },
        );
      } else {
        await progress(CreationStage.generatingNarration, '正在生成自然科普旁白');
        final stopwatch = Stopwatch()..start();
        try {
          await _generateNarration(
            settings: settings,
            text: _narrationText(current.subject, current.location),
            destination: narrationFile,
            traceId: current.id,
          );
          current = current.copyWith(
            narrationPath: narrationFile.path,
            narrationError: '',
          );
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
          current = current.copyWith(narrationError: _message(error));
          await _store.save(current);
        }
      }
    }

    if (needsVideo) {
      final stopwatch = Stopwatch()..start();
      try {
        var taskId = current.wanTaskId;
        if (taskId.isEmpty) {
          await progress(CreationStage.submittingVideo, '正在提交自然短片');
          taskId = await _createWanTask(
            settings: settings,
            prompt: _videoPrompt(current),
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

    if (await videoFile.exists() && !await finalVideoFile.exists()) {
      final hasMusic = await musicFile.exists();
      await progress(
        CreationStage.composing,
        hasMusic ? '正在本机合成音乐、旁白和自然原声' : '正在本机合成旁白和自然原声',
      );
      final stopwatch = Stopwatch()..start();
      try {
        await _composer.compose(
          videoPath: videoFile.path,
          musicPath: hasMusic ? musicFile.path : '',
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
      narrationError: current.narrationError.isEmpty
          ? null
          : current.narrationError,
      videoError: current.videoError.isEmpty ? null : current.videoError,
      compositionError: current.compositionError.isEmpty
          ? null
          : current.compositionError,
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
          Uri.parse(
            '${settings.dashscopeBaseUrl}/api/v1/services/audio/music/generation',
          ),
          headers: {
            HttpHeaders.authorizationHeader:
                'Bearer ${settings.dashscopeApiKey.trim()}',
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          body: jsonEncode({
            'model': settings.dashscopeMusicModel.trim(),
            'input': {
              'prompt': prompt,
              'is_instrumental': true,
              'format': 'mp3',
              'enable_aigc_watermark': false,
            },
          }),
        )
        .timeout(const Duration(minutes: 5));
    AppLog.info(
      'creation',
      'provider_response_received',
      traceId: traceId,
      fields: {
        'provider': 'dashscope',
        'operation': 'music',
        'status_code': response.statusCode,
        'duration_ms': stopwatch.elapsedMilliseconds,
      },
    );
    final payload = _jsonObject(response.body, '阿里云 Fun-Music');
    _checkHttp(response, payload, '阿里云 Fun-Music');
    final output = payload['output'];
    final audio = output is Map<String, Object?> ? output['audio'] : null;
    final url = audio is Map<String, Object?> ? audio['url']?.toString() : null;
    if (url == null || url.isEmpty) {
      throw CreationException(
        _apiMessage(payload) ?? '阿里云 Fun-Music 没有返回音乐文件。',
      );
    }
    await _download(
      Uri.parse(url),
      destination,
      traceId: traceId,
      assetType: 'music',
    );
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
          Uri.parse(
            '${settings.dashscopeBaseUrl}/api/v1/services/audio/tts/SpeechSynthesizer',
          ),
          headers: {
            HttpHeaders.authorizationHeader:
                'Bearer ${settings.dashscopeApiKey.trim()}',
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          body: jsonEncode({
            'model': settings.dashscopeSpeechModel.trim(),
            'input': {
              'text': text,
              'voice': settings.dashscopeSpeechVoice.trim(),
              'format': 'mp3',
              'sample_rate': 24000,
              'instruction': '温暖、平静、有好奇心，像自然教育老师，语速稍慢，不夸张。',
              'enable_aigc_tag': true,
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
        'operation': 'narration',
        'status_code': response.statusCode,
        'duration_ms': stopwatch.elapsedMilliseconds,
      },
    );
    final payload = _jsonObject(response.body, '阿里云 Qwen-Audio-TTS');
    _checkHttp(response, payload, '阿里云 Qwen-Audio-TTS');
    final output = payload['output'];
    final audio = output is Map<String, Object?> ? output['audio'] : null;
    final url = audio is Map<String, Object?> ? audio['url']?.toString() : null;
    if (url == null || url.isEmpty) {
      throw CreationException(
        _apiMessage(payload) ?? '阿里云 Qwen-Audio-TTS 没有返回旁白文件。',
      );
    }
    await _download(
      Uri.parse(url),
      destination,
      traceId: traceId,
      assetType: 'narration',
    );
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
              'negative_prompt': AiPromptCatalog.render(
                'creation.mobile_video_negative',
                const {},
              ),
            },
            'parameters': {
              'resolution': '480P',
              'ratio': '9:16',
              'duration': _videoDurationSeconds,
              'audio': false,
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
      AiPromptCatalog.render('creation.mobile_music', {
        'subject': subject,
        'location': location,
      });

  String _videoPrompt(CreationRecord record) => switch (record.visualMode) {
    CreationVisualMode.bird => AiPromptCatalog.render(
      'creation.mobile_video_bird',
      {'subject': record.subject, 'location': record.location},
    ),
    CreationVisualMode.frog => AiPromptCatalog.render(
      'creation.mobile_video_frog',
      {'subject': record.subject, 'location': record.location},
    ),
    CreationVisualMode.environment => AiPromptCatalog.render(
      'creation.mobile_video_environment',
      {'location': record.location},
    ),
  };

  String _narrationText(String subject, String location) =>
      AiPromptCatalog.render('creation.mobile_narration', {
        'subject': subject,
        'location': location,
      });

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
        _friendlyApiMessage(payload, service) ??
            '$service 请求失败（${response.statusCode}）。',
      );
    }
  }

  String? _friendlyApiMessage(Map<String, Object?> payload, String service) {
    final code = payload['code']?.toString() ?? '';
    final requestId =
        payload['request_id']?.toString() ??
        switch (payload['output']) {
          Map<Object?, Object?> output => output['request_id']?.toString(),
          _ => null,
        };
    final requestSuffix = requestId == null || requestId.isEmpty
        ? ''
        : '（请求 ID：$requestId）';
    final normalized = code.toLowerCase();
    if (service.contains('Fun-Music') &&
        (normalized.contains('accessdenied') ||
            normalized.contains('access_denied'))) {
      return '当前阿里云百炼业务空间尚未开通 Fun-Music。请在华北 2（北京）模型广场申请权限，并确认 API Key 与业务空间一致。$requestSuffix';
    }
    if (normalized.contains('workspace.accessdenied')) {
      return '当前 API Key 无权访问这个业务空间，请检查北京地域的 Workspace ID 与模型授权。$requestSuffix';
    }
    if (normalized.contains('arrearage')) {
      return '阿里云账户当前不可用，请检查欠费、余额和百炼服务状态。$requestSuffix';
    }
    final message = _apiMessage(payload);
    if (message == null || message.isEmpty) return null;
    return '$message$requestSuffix';
  }

  String? _apiMessage(Map<String, Object?> payload) {
    final output = payload['output'];
    if (output is Map<String, Object?> && output['message'] != null) {
      return output['message'].toString();
    }
    return payload['message']?.toString();
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
