import 'dart:convert';
import 'dart:io';

import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:path_provider/path_provider.dart';

abstract interface class CreationSettingsStore {
  Future<CreationSettings> load();

  Future<void> save(CreationSettings settings);

  Future<void> clear();
}

class FileCreationSettingsStore implements CreationSettingsStore {
  FileCreationSettingsStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<File> _settingsFile() async {
    final directory = await _directoryProvider();
    final configDirectory = Directory('${directory.path}/config');
    await configDirectory.create(recursive: true);
    return File('${configDirectory.path}/creation_settings.json');
  }

  @override
  Future<CreationSettings> load() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      AppLog.info('settings', 'creation_config_not_found');
      return const CreationSettings();
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        final settings = CreationSettings.fromJson(decoded);
        final hadLegacyFields = decoded.keys.any(
          (key) => key.startsWith('minimax_') || key == 'dashscope_region',
        );
        if (hadLegacyFields) {
          await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
          AppLog.info('settings', 'legacy_creation_config_removed');
        }
        AppLog.info(
          'settings',
          'creation_config_loaded',
          fields: {
            'has_dashscope_key': settings.hasVideo,
            'music_model': settings.dashscopeMusicModel,
            'speech_model': settings.dashscopeSpeechModel,
            'video_model': settings.wanVideoModel,
          },
        );
        return settings;
      }
    } on FormatException catch (error, stackTrace) {
      AppLog.warning(
        'settings',
        'creation_config_damaged',
        error: error,
        stackTrace: stackTrace,
      );
      // A damaged local settings file should not prevent the app from opening.
    }
    return const CreationSettings();
  }

  @override
  Future<void> save(CreationSettings settings) async {
    final file = await _settingsFile();
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
    AppLog.info(
      'settings',
      'creation_config_saved',
      fields: {
        'has_dashscope_key': settings.hasVideo,
        'music_model': settings.dashscopeMusicModel,
        'speech_model': settings.dashscopeSpeechModel,
        'video_model': settings.wanVideoModel,
      },
    );
  }

  @override
  Future<void> clear() async {
    final file = await _settingsFile();
    if (await file.exists()) await file.delete();
    AppLog.info('settings', 'creation_config_cleared');
  }
}
