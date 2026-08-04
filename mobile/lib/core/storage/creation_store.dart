import 'dart:convert';
import 'dart:io';

import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CreationStore {
  CreationStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<Directory> root() async {
    final base = await _directoryProvider();
    return Directory(p.join(base.path, 'creations'))
      ..createSync(recursive: true);
  }

  Future<void> save(CreationRecord record) async {
    final directory = Directory(record.directoryPath);
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, 'task.json'));
    final temporary = File(p.join(directory.path, 'task.json.tmp'));
    await temporary.writeAsString(jsonEncode(record.toJson()), flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  Future<CreationRecord?> load(String id) async {
    final directory = await root();
    return _read(File(p.join(directory.path, id, 'task.json')));
  }

  Future<List<CreationRecord>> list() async {
    final directory = await root();
    final records = <CreationRecord>[];
    await for (final entity in directory.list()) {
      if (entity is! Directory) continue;
      final record = await _read(File(p.join(entity.path, 'task.json')));
      if (record != null) records.add(record);
    }
    records.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return records;
  }

  Future<void> delete(CreationRecord record) async {
    final rootDirectory = await root();
    final rootPath = rootDirectory.absolute.path;
    final target = Directory(record.directoryPath).absolute;
    if (p.equals(target.path, rootPath) || !p.isWithin(rootPath, target.path)) {
      throw ArgumentError('作品目录不在应用创作目录中。');
    }
    if (await target.exists()) await target.delete(recursive: true);
  }

  Future<CreationRecord?> _read(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        final record = CreationRecord.fromJson(decoded);
        return record.id.isEmpty ? null : record;
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
