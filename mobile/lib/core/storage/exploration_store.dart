import 'dart:convert';
import 'dart:io';

import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/storage/exploration_record.dart';
import 'package:path_provider/path_provider.dart';

abstract interface class ExplorationStore {
  Future<ExplorationRecord> save({
    required RecordedAudio recording,
    required AudioQuality quality,
    required List<SoundDetection> detections,
    required String location,
  });

  Future<List<ExplorationRecord>> list();

  Future<void> setConfirmed(String id, bool confirmed);

  Future<void> delete(String id);
}

typedef DirectoryProvider = Future<Directory> Function();

class FileExplorationStore implements ExplorationStore {
  FileExplorationStore({DirectoryProvider? rootProvider})
    : _rootProvider = rootProvider ?? _defaultRoot;

  final DirectoryProvider _rootProvider;

  static Future<Directory> _defaultRoot() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(
      '${documents.path}${Platform.pathSeparator}nature_sound_detective',
    );
  }

  @override
  Future<ExplorationRecord> save({
    required RecordedAudio recording,
    required AudioQuality quality,
    required List<SoundDetection> detections,
    required String location,
  }) async {
    _validateId(recording.id);
    final root = await _rootProvider();
    final audioDirectory = Directory(
      '${root.path}${Platform.pathSeparator}audio',
    );
    final recordDirectory = Directory(
      '${root.path}${Platform.pathSeparator}records',
    );
    await audioDirectory.create(recursive: true);
    await recordDirectory.create(recursive: true);
    final audioPath =
        '${audioDirectory.path}${Platform.pathSeparator}${recording.id}.wav';
    final source = File(recording.path);
    if (!await source.exists()) throw const FileSystemException('录音文件不存在。');
    if (source.absolute.path != File(audioPath).absolute.path) {
      await source.copy(audioPath);
    }

    final record = ExplorationRecord(
      id: recording.id,
      createdAt: DateTime.now().toUtc(),
      location: location,
      audioPath: audioPath,
      duration: recording.duration,
      audioQuality: quality,
      detections: List.unmodifiable(detections),
    );
    await _writeRecord(recordDirectory, record);
    return record;
  }

  @override
  Future<List<ExplorationRecord>> list() async {
    final root = await _rootProvider();
    final directory = Directory('${root.path}${Platform.pathSeparator}records');
    if (!await directory.exists()) return const [];
    final records = <ExplorationRecord>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final value = jsonDecode(await entity.readAsString());
        if (value is Map<String, Object?>) {
          records.add(ExplorationRecord.fromJson(value));
        }
      } on FormatException {
        // Ignore one damaged record so the rest of the sound book remains usable.
      }
    }
    records.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return records;
  }

  @override
  Future<void> setConfirmed(String id, bool confirmed) async {
    _validateId(id);
    final root = await _rootProvider();
    final directory = Directory('${root.path}${Platform.pathSeparator}records');
    final file = File('${directory.path}${Platform.pathSeparator}$id.json');
    if (!await file.exists()) throw StateError('声音记录不存在。');
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, Object?>) throw const FormatException('声音记录已损坏。');
    await _writeRecord(
      directory,
      ExplorationRecord.fromJson(value).copyWith(confirmedByUser: confirmed),
    );
  }

  @override
  Future<void> delete(String id) async {
    _validateId(id);
    final root = await _rootProvider();
    final record = File(
      '${root.path}${Platform.pathSeparator}records${Platform.pathSeparator}$id.json',
    );
    final audio = File(
      '${root.path}${Platform.pathSeparator}audio${Platform.pathSeparator}$id.wav',
    );
    if (await record.exists()) await record.delete();
    if (await audio.exists()) await audio.delete();
  }

  Future<void> _writeRecord(
    Directory directory,
    ExplorationRecord record,
  ) async {
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${record.id}.json',
    );
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(record.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  void _validateId(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('声音记录编号无效。');
    }
  }
}
