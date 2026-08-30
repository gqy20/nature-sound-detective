import 'dart:convert';
import 'dart:io';

import 'package:nature_sound_detective/core/mode/exploration_mode.dart';
import 'package:nature_sound_detective/features/navigation/primary_feature.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PrimaryFeatureStore {
  PrimaryFeatureStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<PrimaryFeature?> load(ExplorationMode mode) async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<Object?, Object?>) return null;
      final name = value[mode.name] as String?;
      return PrimaryFeature.values
          .where((feature) => feature.name == name)
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(ExplorationMode mode, PrimaryFeature feature) async {
    final file = await _file();
    Map<String, Object?> values = {};
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<Object?, Object?>) {
          values = decoded.cast<String, Object?>();
        }
      }
    } catch (_) {}
    values[mode.name] = feature.name;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(values), flush: true);
  }

  Future<File> _file() async {
    final directory = await _directoryProvider();
    return File(p.join(directory.path, 'config', 'primary_navigation.json'));
  }
}
