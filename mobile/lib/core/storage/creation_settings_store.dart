import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:path_provider/path_provider.dart';

abstract interface class CreationSettingsStore {
  Future<CreationSettings> load();

  Future<void> save(CreationSettings settings);

  Future<void> clear();
}

abstract interface class CreationSecretStore {
  Future<String> load();

  Future<void> save(String value);

  Future<void> clear();
}

class AndroidKeystoreCreationSecretStore implements CreationSecretStore {
  const AndroidKeystoreCreationSecretStore();

  static const _channel = MethodChannel(
    'com.xykw.nature_sound/creation_secrets',
  );

  @override
  Future<String> load() async =>
      (await _channel.invokeMethod<String>('readDashscopeKey'))?.trim() ?? '';

  @override
  Future<void> save(String value) async {
    await _channel.invokeMethod<void>('writeDashscopeKey', {
      'value': value.trim(),
    });
  }

  @override
  Future<void> clear() async {
    await _channel.invokeMethod<void>('clearDashscopeKey');
  }
}

class FileCreationSettingsStore implements CreationSettingsStore {
  FileCreationSettingsStore({
    Future<Directory> Function()? directoryProvider,
    CreationSecretStore? secretStore,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _secretStore = secretStore ?? const AndroidKeystoreCreationSecretStore();

  final Future<Directory> Function() _directoryProvider;
  final CreationSecretStore _secretStore;

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
      return CreationSettings(dashscopeApiKey: await _secretStore.load());
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        final settings = CreationSettings.fromJson(decoded);
        var secureKey = await _secretStore.load();
        var migratedSecret = false;
        if (secureKey.isEmpty && settings.dashscopeApiKey.trim().isNotEmpty) {
          await _secretStore.save(settings.dashscopeApiKey);
          secureKey = settings.dashscopeApiKey.trim();
          migratedSecret = true;
        }
        final hadLegacyFields =
            decoded.keys.any(
              (key) => key.startsWith('minimax_') || key == 'dashscope_region',
            ) ||
            decoded['wan_video_model'] == 'wan2.7-t2v' ||
            decoded.containsKey('dashscope_api_key');
        final restored = settings.withApiKey(secureKey);
        if (hadLegacyFields || migratedSecret) {
          await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
          AppLog.info('settings', 'legacy_creation_config_removed');
        }
        AppLog.info(
          'settings',
          'creation_config_loaded',
          fields: {
            'has_dashscope_key': restored.hasVideo,
            'music_model': restored.dashscopeMusicModel,
            'speech_model': restored.dashscopeSpeechModel,
            'video_model': restored.wanVideoModel,
          },
        );
        return restored;
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
    if (settings.dashscopeApiKey.trim().isEmpty) {
      await _secretStore.clear();
    } else {
      await _secretStore.save(settings.dashscopeApiKey);
    }
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
    await _secretStore.clear();
    final file = await _settingsFile();
    if (await file.exists()) await file.delete();
    AppLog.info('settings', 'creation_config_cleared');
  }
}
