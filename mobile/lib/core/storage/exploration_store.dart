import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/inference/birdnet_species.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/models/exploration_feedback.dart';
import 'package:nature_sound_detective/core/storage/exploration_record.dart';
import 'package:path_provider/path_provider.dart';

abstract interface class ExplorationStore {
  Future<ExplorationRecord> save({
    required RecordedAudio recording,
    required AudioQuality quality,
    required List<SoundDetection> detections,
    required String location,
    Map<String, List<String>> fieldChecks = const {},
  });

  Future<List<ExplorationRecord>> list();

  Future<void> setConfirmed(String id, bool confirmed);

  Future<void> setFeedback(String id, ExplorationFeedback feedback);

  Future<void> setFieldChecks(
    String id,
    String speciesKey,
    List<String> checks,
  );

  Future<Directory> exportReviewPackage(Directory destination);

  Future<void> delete(String id);
}

typedef DirectoryProvider = Future<Directory> Function();
typedef SpeciesCatalogProvider = Future<BirdnetSpeciesCatalog> Function();

class FileExplorationStore implements ExplorationStore {
  FileExplorationStore({
    DirectoryProvider? rootProvider,
    SpeciesCatalogProvider? speciesCatalogProvider,
  }) : _rootProvider = rootProvider ?? _defaultRoot,
       _speciesCatalogProvider =
           speciesCatalogProvider ?? _defaultSpeciesCatalog;

  final DirectoryProvider _rootProvider;
  final SpeciesCatalogProvider _speciesCatalogProvider;
  Future<BirdnetSpeciesCatalog>? _speciesCatalogFuture;

  static Future<Directory> _defaultRoot() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(
      '${documents.path}${Platform.pathSeparator}nature_sound_detective',
    );
  }

  static Future<BirdnetSpeciesCatalog> _defaultSpeciesCatalog() async {
    return BirdnetSpeciesCatalog.fromJson(
      await rootBundle.loadString('assets/labels/birdnet_hz.json'),
    );
  }

  @override
  Future<ExplorationRecord> save({
    required RecordedAudio recording,
    required AudioQuality quality,
    required List<SoundDetection> detections,
    required String location,
    Map<String, List<String>> fieldChecks = const {},
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
      fieldChecks: fieldChecks,
    );
    await _writeRecord(recordDirectory, record);
    AppLog.debug(
      'storage',
      'record_written',
      traceId: recording.id,
      fields: {'byte_length': recording.byteLength},
    );
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
      } on FormatException catch (error, stackTrace) {
        AppLog.warning(
          'storage',
          'damaged_record_skipped',
          error: error,
          stackTrace: stackTrace,
        );
        // Ignore one damaged record so the rest of the sound book remains usable.
      }
    }
    if (_containsVersionedSpecies(records)) {
      try {
        final catalog = await (_speciesCatalogFuture ??=
            _speciesCatalogProvider());
        for (var index = 0; index < records.length; index += 1) {
          final record = records[index];
          records[index] = record.copyWith(
            detections: record.detections
                .map(catalog.normalizeDetection)
                .toList(growable: false),
          );
        }
      } catch (error, stackTrace) {
        AppLog.warning(
          'storage',
          'species_names_not_normalized',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    records.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return records;
  }

  bool _containsVersionedSpecies(List<ExplorationRecord> records) {
    return records.any(
      (record) => record.detections.any((detection) {
        final scientificName = detection.specificSpecies?.scientificName;
        return scientificName != null && scientificName.trim().isNotEmpty;
      }),
    );
  }

  @override
  Future<void> setConfirmed(String id, bool confirmed) async {
    await setFeedback(
      id,
      ExplorationFeedback(
        decision: confirmed ? FeedbackDecision.correct : FeedbackDecision.wrong,
      ),
    );
  }

  @override
  Future<void> setFeedback(String id, ExplorationFeedback feedback) async {
    _validateId(id);
    final root = await _rootProvider();
    final directory = Directory('${root.path}${Platform.pathSeparator}records');
    final file = File('${directory.path}${Platform.pathSeparator}$id.json');
    if (!await file.exists()) throw StateError('声音记录不存在。');
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, Object?>) throw const FormatException('声音记录已损坏。');
    await _writeRecord(
      directory,
      ExplorationRecord.fromJson(value).copyWith(
        confirmedByUser: feedback.decision == FeedbackDecision.correct,
        feedback: feedback,
      ),
    );
  }

  @override
  Future<void> setFieldChecks(
    String id,
    String speciesKey,
    List<String> checks,
  ) async {
    _validateId(id);
    final root = await _rootProvider();
    final directory = Directory('${root.path}${Platform.pathSeparator}records');
    final file = File('${directory.path}${Platform.pathSeparator}$id.json');
    if (!await file.exists()) throw StateError('声音记录不存在。');
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, Object?>) throw const FormatException('声音记录已损坏。');
    final record = ExplorationRecord.fromJson(value);
    final updated = <String, List<String>>{
      ...record.fieldChecks,
      if (checks.isNotEmpty) speciesKey: List.unmodifiable(checks),
    };
    if (checks.isEmpty) updated.remove(speciesKey);
    await _writeRecord(directory, record.copyWith(fieldChecks: updated));
  }

  @override
  Future<Directory> exportReviewPackage(Directory destination) async {
    final package = Directory(
      '${destination.path}${Platform.pathSeparator}nature_sound_review',
    );
    final audioDirectory = Directory(
      '${package.path}${Platform.pathSeparator}audio',
    );
    await audioDirectory.create(recursive: true);
    final rows = <String>[];
    for (final record in await list()) {
      final feedback = record.feedback;
      if (feedback == null || !feedback.consentToRetainAudio) continue;
      final source = File(record.audioPath);
      if (!await source.exists()) continue;
      final audioName = '${record.id}.wav';
      await source.copy(
        '${audioDirectory.path}${Platform.pathSeparator}$audioName',
      );
      final payload = record.toJson()
        ..['audio_path'] = 'audio/$audioName'
        ..['review_status'] = 'user_reported';
      rows.add(jsonEncode(payload));
    }
    await File(
      '${package.path}${Platform.pathSeparator}feedback.jsonl',
    ).writeAsString(rows.isEmpty ? '' : '${rows.join('\n')}\n', flush: true);
    return package;
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
    AppLog.info('storage', 'record_deleted', traceId: id);
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
