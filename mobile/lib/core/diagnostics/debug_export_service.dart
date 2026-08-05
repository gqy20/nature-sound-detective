import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/storage/creation_settings_store.dart';
import 'package:nature_sound_detective/core/storage/exploration_record.dart';
import 'package:nature_sound_detective/core/storage/exploration_store.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef DebugDirectoryProvider = Future<Directory> Function();
typedef DebugInfoProvider = Future<Map<String, Object?>> Function();
typedef DebugLogExporter = Future<String?> Function();

class DebugSessionSnapshot {
  const DebugSessionSnapshot({
    required this.id,
    required this.createdAt,
    required this.audioPath,
    required this.duration,
    required this.quality,
    required this.detections,
    required this.location,
    this.sampleRate,
    this.channelCount,
    this.byteLength,
  });

  factory DebugSessionSnapshot.current({
    required RecordedAudio recording,
    required AudioQuality quality,
    required List<SoundDetection> detections,
    String location = '杭州',
  }) => DebugSessionSnapshot(
    id: recording.id,
    createdAt: DateTime.now().toUtc(),
    audioPath: recording.path,
    duration: recording.duration,
    quality: quality,
    detections: List.unmodifiable(detections),
    location: location,
    sampleRate: recording.sampleRate,
    channelCount: recording.channelCount,
    byteLength: recording.byteLength,
  );

  factory DebugSessionSnapshot.saved(ExplorationRecord record) =>
      DebugSessionSnapshot(
        id: record.id,
        createdAt: record.createdAt,
        audioPath: record.audioPath,
        duration: record.duration,
        quality: record.audioQuality,
        detections: record.detections,
        location: record.location,
      );

  final String id;
  final DateTime createdAt;
  final String audioPath;
  final Duration duration;
  final AudioQuality quality;
  final List<SoundDetection> detections;
  final String location;
  final int? sampleRate;
  final int? channelCount;
  final int? byteLength;

  Map<String, Object?> toJson({required bool audioIncluded}) => {
    'id': id,
    'created_at': createdAt.toUtc().toIso8601String(),
    'location': location,
    'duration_ms': duration.inMilliseconds,
    if (sampleRate != null) 'sample_rate': sampleRate,
    if (channelCount != null) 'channel_count': channelCount,
    if (byteLength != null) 'byte_length': byteLength,
    'audio_included': audioIncluded,
    if (audioIncluded)
      'audio_file': 'session/recording${p.extension(audioPath)}',
    'audio_quality': quality.toJson(),
    'detections': detections.map((item) => item.toJson()).toList(),
  };
}

class DebugExportResult {
  const DebugExportResult({
    required this.file,
    required this.sessionId,
    required this.audioIncluded,
  });

  final File file;
  final String? sessionId;
  final bool audioIncluded;

  Future<int> get byteLength => file.length();
}

class DebugExportService {
  DebugExportService({
    ExplorationStore? explorationStore,
    CreationSettingsStore? settingsStore,
    DebugDirectoryProvider? cacheDirectoryProvider,
    DebugInfoProvider? appInfoProvider,
    DebugInfoProvider? deviceInfoProvider,
    DebugLogExporter? logExporter,
    DateTime Function()? now,
  }) : _explorationStore = explorationStore ?? FileExplorationStore(),
       _settingsStore = settingsStore ?? FileCreationSettingsStore(),
       _cacheDirectoryProvider =
           cacheDirectoryProvider ?? getTemporaryDirectory,
       _appInfoProvider = appInfoProvider ?? _defaultAppInfo,
       _deviceInfoProvider = deviceInfoProvider ?? _defaultDeviceInfo,
       _logExporter = logExporter ?? AppLog.exportDiagnostics,
       _now = now ?? DateTime.now;

  final ExplorationStore _explorationStore;
  final CreationSettingsStore _settingsStore;
  final DebugDirectoryProvider _cacheDirectoryProvider;
  final DebugInfoProvider _appInfoProvider;
  final DebugInfoProvider _deviceInfoProvider;
  final DebugLogExporter _logExporter;
  final DateTime Function() _now;

  Future<DebugSessionSnapshot?> latestSavedSession() async {
    final records = await _explorationStore.list();
    return records.isEmpty ? null : DebugSessionSnapshot.saved(records.first);
  }

  Future<DebugExportResult> export({
    DebugSessionSnapshot? session,
    bool includeAudio = true,
  }) async {
    final selected = session ?? await latestSavedSession();
    final cache = await _cacheDirectoryProvider();
    final outputDirectory = Directory(p.join(cache.path, 'diagnostics'));
    await outputDirectory.create(recursive: true);
    final timestamp = _fileTimestamp(_now().toUtc());
    final suffix = selected == null ? 'no-session' : _safeId(selected.id);
    final staging = Directory(p.join(cache.path, 'debug-stage-$timestamp'));
    final output = File(
      p.join(outputDirectory.path, 'nature-sound-debug-$timestamp-$suffix.zip'),
    );

    await staging.create(recursive: true);
    try {
      final appInfo = await _appInfoProvider();
      final deviceInfo = await _deviceInfoProvider();
      final settings = await _settingsStore.load();
      final sourceAudio = selected == null ? null : File(selected.audioPath);
      final audioIncluded =
          includeAudio && sourceAudio != null && await sourceAudio.exists();

      await _writeJson(File(p.join(staging.path, 'device.json')), deviceInfo);
      await _writeJson(File(p.join(staging.path, 'config.json')), {
        'minimax_configured': settings.hasMusic,
        'dashscope_configured': settings.hasVideo,
        'dashscope_workspace_configured': settings.dashscopeWorkspaceId
            .trim()
            .isNotEmpty,
        'dashscope_region': settings.dashscopeRegion,
        'music_model': settings.minimaxMusicModel,
        'speech_model': settings.minimaxSpeechModel,
        'speech_voice': settings.minimaxSpeechVoice,
        'video_model': settings.wanVideoModel,
      });

      if (selected != null) {
        final sessionDirectory = Directory(p.join(staging.path, 'session'));
        await sessionDirectory.create(recursive: true);
        await _writeJson(
          File(p.join(sessionDirectory.path, 'result.json')),
          selected.toJson(audioIncluded: audioIncluded),
        );
        if (audioIncluded) {
          final extension = p.extension(selected.audioPath).isEmpty
              ? '.wav'
              : p.extension(selected.audioPath);
          await sourceAudio.copy(
            p.join(sessionDirectory.path, 'recording$extension'),
          );
        }
      }

      final logPath = await _logExporter();
      var sessionLogCount = 0;
      if (logPath != null) {
        final sourceLog = File(logPath);
        if (await sourceLog.exists()) {
          final logsDirectory = Directory(p.join(staging.path, 'logs'));
          await logsDirectory.create(recursive: true);
          final allLogs = File(p.join(logsDirectory.path, 'app.jsonl'));
          await sourceLog.copy(allLogs.path);
          if (selected != null) {
            sessionLogCount = await _writeSessionLogs(
              sourceLog,
              File(p.join(logsDirectory.path, 'session.jsonl')),
              selected.id,
            );
          }
        }
      }

      await _writeJson(File(p.join(staging.path, 'manifest.json')), {
        'schema_version': 1,
        'exported_at': _now().toUtc().toIso8601String(),
        'diagnostics_enabled': true,
        'build_mode': kReleaseMode
            ? 'release'
            : (kProfileMode ? 'profile' : 'debug'),
        'app': appInfo,
        'session_id': selected?.id,
        'session_included': selected != null,
        'audio_included': audioIncluded,
        'session_log_count': sessionLogCount,
        'privacy': {
          'credentials_included': false,
          'raw_settings_included': false,
          'cloud_response_bodies_included': false,
        },
      });
      await File(p.join(staging.path, 'README.txt')).writeAsString(
        '自然声探员内测诊断包\n'
        '此文件用于排查录音、音质判断和识别问题。\n'
        '配置只记录是否完成配置，不包含 API 密钥。\n'
        '${audioIncluded ? '本包包含原始录音，请仅分享给可信的开发人员。' : '本包不包含原始录音。'}\n',
        flush: true,
      );

      await _assertNoSecrets(staging);
      await ZipFileEncoder().zipDirectory(
        staging,
        filename: output.path,
        level: ZipFileEncoder.gzip,
      );
      await _cleanOldExports(outputDirectory, keep: 3);
      AppLog.info(
        'diagnostics',
        'bundle_exported',
        traceId: selected?.id,
        fields: {
          'audio_included': audioIncluded,
          'session_included': selected != null,
          'session_log_count': sessionLogCount,
          'byte_length': await output.length(),
        },
      );
      return DebugExportResult(
        file: output,
        sessionId: selected?.id,
        audioIncluded: audioIncluded,
      );
    } catch (error, stackTrace) {
      if (await output.exists()) await output.delete();
      AppLog.error(
        'diagnostics',
        'bundle_export_failed',
        traceId: selected?.id,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  static Future<Map<String, Object?>> _defaultAppInfo() async {
    final info = await PackageInfo.fromPlatform();
    return {
      'name': info.appName,
      'package_name': info.packageName,
      'version': info.version,
      'build_number': info.buildNumber,
    };
  }

  static Future<Map<String, Object?>> _defaultDeviceInfo() async {
    final result = <String, Object?>{
      'platform': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
      'processors': Platform.numberOfProcessors,
    };
    if (Platform.isAndroid) {
      final android = await DeviceInfoPlugin().androidInfo;
      result.addAll({
        'manufacturer': android.manufacturer,
        'brand': android.brand,
        'model': android.model,
        'device': android.device,
        'product': android.product,
        'hardware': android.hardware,
        'android_sdk': android.version.sdkInt,
        'android_release': android.version.release,
        'supported_abis': android.supportedAbis,
        'is_physical_device': android.isPhysicalDevice,
      });
      try {
        final native = await const MethodChannel(
          'com.xykw.nature_sound/audio_recorder',
        ).invokeMapMethod<Object?, Object?>('getDiagnostics');
        if (native != null) {
          result['audio_recorder'] = native.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      } on PlatformException {
        result['audio_recorder'] = {'available': false};
      }
    }
    return result;
  }

  static Future<void> _writeJson(File file, Map<String, Object?> value) async {
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(value)}\n', flush: true);
  }

  static Future<int> _writeSessionLogs(
    File source,
    File destination,
    String traceId,
  ) async {
    final output = destination.openWrite();
    var count = 0;
    await for (final line
        in source
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      try {
        final value = jsonDecode(line);
        if (value is Map<String, Object?> && value['trace_id'] == traceId) {
          output.writeln(line);
          count++;
        }
      } on FormatException {
        // The complete log is still included; malformed lines are not copied
        // into the session-specific view.
      }
    }
    await output.flush();
    await output.close();
    return count;
  }

  static Future<void> _assertNoSecrets(Directory directory) async {
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File || !_isTextFile(entity.path)) continue;
      final contents = await entity.readAsString();
      for (final pattern in _secretPatterns) {
        if (pattern.hasMatch(contents)) {
          throw StateError('诊断包检测到疑似敏感信息，已停止导出。');
        }
      }
    }
  }

  static bool _isTextFile(String path) => const {
    '.json',
    '.jsonl',
    '.txt',
  }.contains(p.extension(path).toLowerCase());

  static Future<void> _cleanOldExports(
    Directory directory, {
    required int keep,
  }) async {
    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.zip'))
        .cast<File>()
        .toList();
    final dated = <({File file, DateTime modified})>[];
    for (final file in files) {
      dated.add((file: file, modified: (await file.stat()).modified));
    }
    dated.sort((left, right) => right.modified.compareTo(left.modified));
    for (final item in dated.skip(keep)) {
      await item.file.delete();
    }
  }

  static String _fileTimestamp(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}-'
      '${value.hour.toString().padLeft(2, '0')}'
      '${value.minute.toString().padLeft(2, '0')}'
      '${value.second.toString().padLeft(2, '0')}'
      '${value.millisecond.toString().padLeft(3, '0')}';

  static String _safeId(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (sanitized.isEmpty) return 'session';
    return sanitized.length <= 40 ? sanitized : sanitized.substring(0, 40);
  }

  static final _secretPatterns = <RegExp>[
    RegExp(r'Bearer\s+(?!\[REDACTED\])[a-z0-9._-]{8,}', caseSensitive: false),
    RegExp(r'\bsk-[a-z0-9_-]{8,}\b', caseSensitive: false),
    RegExp(
      r'"(?:minimax_api_key|dashscope_api_key|api_key|access_token|authorization)"\s*:\s*"(?!\[REDACTED\])[^"\r\n]{4,}"',
      caseSensitive: false,
    ),
    RegExp(
      r'[?&](?:token|access_token|api_key|signature)=(?!\[REDACTED\])[^&\s]+',
      caseSensitive: false,
    ),
  ];
}
