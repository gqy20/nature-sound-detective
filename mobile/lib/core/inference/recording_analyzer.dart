import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/wav_pcm_reader.dart';
import 'package:nature_sound_detective/core/fusion/nature_detection_fusion.dart';
import 'package:nature_sound_detective/core/inference/birdnet_detector.dart';
import 'package:nature_sound_detective/core/inference/nonbird_detector.dart';
import 'package:nature_sound_detective/core/inference/yamnet_detector.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

abstract interface class RecordingAnalyzer {
  Future<List<SoundDetection>> analyze(
    RecordedAudio recording, {
    void Function(List<SoundDetection> detections, int processed, int total)?
    onProgress,
  });

  Future<void> dispose();
}

class LocalRecordingAnalyzer implements RecordingAnalyzer {
  LocalRecordingAnalyzer({
    this.reader = const WavPcmReader(),
    this.fusion = const NatureDetectionFusion(),
  });

  final WavPcmReader reader;
  final NatureDetectionFusion fusion;
  late final CachedModel<YamnetDetector> _detector = CachedModel(
    YamnetDetector.load,
  );
  late final CachedModel<BirdnetDetector> _birdDetector = CachedModel(
    BirdnetDetector.load,
  );
  late final CachedModel<NonBirdDetector?> _nonBirdDetector = CachedModel(
    NonBirdDetector.tryLoad,
  );

  Future<bool> preload() async {
    final timer = Stopwatch()..start();
    AppLog.info('inference', 'model_preload_started');
    try {
      await Future.wait([
        _detector.load(),
        _birdDetector.load(),
        _nonBirdDetector.load(),
      ]);
      timer.stop();
      AppLog.info(
        'inference',
        'model_preload_completed',
        fields: {'duration_ms': timer.elapsedMilliseconds},
      );
      return true;
    } catch (error, stackTrace) {
      timer.stop();
      AppLog.warning(
        'inference',
        'model_preload_failed',
        fields: {'duration_ms': timer.elapsedMilliseconds},
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<List<SoundDetection>> analyze(
    RecordedAudio recording, {
    void Function(List<SoundDetection> detections, int processed, int total)?
    onProgress,
  }) async {
    final total = Stopwatch()..start();
    AppLog.info('inference', 'analysis_started', traceId: recording.id);
    final input = await reader.read(
      recordingId: recording.id,
      path: recording.path,
    );
    final yamnetLoader = _detector.load();
    final birdnetLoader = _birdDetector.load();
    final nonBirdLoader = _nonBirdDetector.load();
    final yamnet = await yamnetLoader;
    final birdnet = await birdnetLoader;
    final nonBird = await nonBirdLoader;
    final yamnetFuture = yamnet.detect(input);
    var latestNonBirdDetections = const <SoundDetection>[];
    final birdnetResult = await birdnet.detectWithEmbeddings(
      input,
      onProgress: onProgress == null
          ? null
          : (partial, processed, total) async {
              latestNonBirdDetections = nonBird == null
                  ? const <SoundDetection>[]
                  : await nonBird.detectEmbeddings(partial.embeddings);
              onProgress(
                fusion.fuse([partial.detections, latestNonBirdDetections]),
                processed,
                total,
              );
            },
    );
    final yamnetDetections = await yamnetFuture;
    final nonBirdDetections = onProgress != null
        ? latestNonBirdDetections
        : nonBird == null
        ? const <SoundDetection>[]
        : await nonBird.detectEmbeddings(birdnetResult.embeddings);
    final fused = fusion.fuse([
      yamnetDetections,
      birdnetResult.detections,
      nonBirdDetections,
    ]);
    total.stop();
    AppLog.info(
      'inference',
      'analysis_completed',
      traceId: recording.id,
      fields: {
        'duration_ms': total.elapsedMilliseconds,
        'yamnet_candidates': yamnetDetections.length,
        'birdnet_candidates': birdnetResult.detections.length,
        'nonbird_candidates': nonBirdDetections.length,
        'fused_candidates': fused.length,
        'yamnet_summary': _candidateSummary(yamnetDetections),
        'birdnet_summary': _candidateSummary(birdnetResult.detections),
        'nonbird_summary': _candidateSummary(nonBirdDetections),
        'fused_summary': _candidateSummary(fused),
      },
    );
    return fused;
  }

  List<Map<String, Object?>> _candidateSummary(
    List<SoundDetection> detections,
  ) => detections
      .take(8)
      .map((item) {
        final species = item.specificSpecies;
        return <String, Object?>{
          'category': item.categoryId,
          if (species != null)
            'species_id':
                species.taxonomyId ?? species.scientificName ?? species.nameZh,
          'score': (item.confidence * 100).round() / 100,
          if (item.tentative) 'tentative': true,
          'models': item.evidenceModels.map(_modelFamily).toSet().toList(),
          'windows': item.intervals
              .take(4)
              .map(
                (interval) => <String, Object?>{
                  'start': (interval.startSeconds * 10).round() / 10,
                  'end': (interval.endSeconds * 10).round() / 10,
                },
              )
              .toList(),
        };
      })
      .toList(growable: false);

  String _modelFamily(String model) {
    final normalized = model.toLowerCase();
    if (normalized.contains('birdnet')) return 'birdnet';
    if (normalized.contains('nonbird')) return 'nonbird';
    if (normalized.contains('yamnet')) return 'yamnet';
    return 'other';
  }

  @override
  Future<void> dispose() async {
    final detector = await _detector.loadedValue();
    if (detector != null) await detector.close();
    final birdDetector = await _birdDetector.loadedValue();
    if (birdDetector != null) await birdDetector.close();
    final nonBirdDetector = await _nonBirdDetector.loadedValue();
    if (nonBirdDetector != null) await nonBirdDetector.close();
  }
}

class CachedModel<T> {
  CachedModel(this._loader);

  final Future<T> Function() _loader;
  Future<T>? _future;

  Future<T> load() {
    final current = _future;
    if (current != null) return current;
    final created = _loadAndResetOnFailure();
    _future = created;
    return created;
  }

  Future<T> _loadAndResetOnFailure() async {
    try {
      return await _loader();
    } catch (_) {
      _future = null;
      rethrow;
    }
  }

  Future<T?> loadedValue() async {
    final current = _future;
    if (current == null) return null;
    try {
      return await current;
    } catch (_) {
      return null;
    }
  }
}
