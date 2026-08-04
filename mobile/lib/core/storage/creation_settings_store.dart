import 'dart:convert';
import 'dart:io';

import 'package:nature_sound_detective/core/models/creation.dart';
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
    if (!await file.exists()) return const CreationSettings();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        return CreationSettings.fromJson(decoded);
      }
    } on FormatException {
      // A damaged local settings file should not prevent the app from opening.
    }
    return const CreationSettings();
  }

  @override
  Future<void> save(CreationSettings settings) async {
    final file = await _settingsFile();
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }

  @override
  Future<void> clear() async {
    final file = await _settingsFile();
    if (await file.exists()) await file.delete();
  }
}
