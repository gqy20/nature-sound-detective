import 'dart:io';

import 'package:nature_sound_detective/core/mode/exploration_mode.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ExplorationModeStore {
  ExplorationModeStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<ExplorationMode> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return ExplorationMode.child;
      return ExplorationMode.parse((await file.readAsString()).trim());
    } catch (_) {
      return ExplorationMode.child;
    }
  }

  Future<void> save(ExplorationMode mode) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(mode.storageValue, flush: true);
  }

  Future<File> _file() async {
    final directory = await _directoryProvider();
    return File(p.join(directory.path, 'config', 'exploration_mode.txt'));
  }
}
