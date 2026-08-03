import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/audio/pcm_resampler.dart';
import 'package:nature_sound_detective/core/inference/audio_inference.dart';
import 'package:nature_sound_detective/core/inference/birdnet_species.dart';
import 'package:nature_sound_detective/core/inference/nonbird_detector.dart';
import 'package:nature_sound_detective/core/inference/tensor_output_buffer.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class BirdnetDetector implements AudioDetector {
  BirdnetDetector._(this._interpreter, this._isolate, this._species);

  static Future<BirdnetDetector> load() async {
    final timer = Stopwatch()..start();
    AppLog.info(
      'birdnet',
      'model_load_started',
      fields: {'model_version': '2.4-fp16'},
    );
    try {
      final options = InterpreterOptions()..threads = 2;
      final results = await Future.wait<Object>([
        Interpreter.fromAsset('assets/models/birdnet.tflite', options: options),
        rootBundle.loadString('assets/labels/birdnet_hz.json'),
      ]);
      final interpreter = results[0] as Interpreter;
      final catalog = BirdnetSpeciesCatalog.fromJson(results[1] as String);
      final detector = BirdnetDetector._(
        interpreter,
        await IsolateInterpreter.create(
          address: interpreter.address,
          debugName: 'BirdnetInference',
        ),
        catalog.species,
      );
      timer.stop();
      AppLog.info(
        'birdnet',
        'model_load_completed',
        fields: {
          'duration_ms': timer.elapsedMilliseconds,
          'model_version': detector.modelVersion,
          'species_count': detector._species.length,
        },
      );
      return detector;
    } catch (error, stackTrace) {
      timer.stop();
      AppLog.error(
        'birdnet',
        'model_load_failed',
        fields: {'duration_ms': timer.elapsedMilliseconds},
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static const _windowSamples = 144000;
  static const _threshold = 0.05;
  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;
  final List<BirdnetSpecies> _species;

  @override
  String get modelId => 'birdnet-acoustic';

  @override
  String get modelVersion => '2.4-fp16';

  @override
  int get requiredSampleRate => 48000;

  @override
  Future<List<SoundDetection>> detect(AudioInferenceInput input) async {
    return (await detectWithEmbeddings(input)).detections;
  }

  Future<BirdnetDetectionResult> detectWithEmbeddings(
    AudioInferenceInput input,
  ) async {
    final timer = Stopwatch()..start();
    final waveform = PcmResampler.toMonoFloat32(
      input,
      outputSampleRate: requiredSampleRate,
    );
    if (waveform.isEmpty) {
      AppLog.warning('birdnet', 'empty_input', traceId: input.recordingId);
      return const BirdnetDetectionResult([], []);
    }

    final bestBySpecies = <BirdnetSpecies, _BirdScore>{};
    final embeddings = <BirdnetEmbeddingWindow>[];
    for (var offset = 0; offset < waveform.length; offset += _windowSamples) {
      final window = Float32List(_windowSamples);
      final available = math.min(_windowSamples, waveform.length - offset);
      window.setRange(0, available, waveform, offset);
      final result = await _runWindow(window);
      final scores = result.scores;
      final interval = DetectionInterval(
        startSeconds: offset / requiredSampleRate,
        endSeconds: math.min(
          (offset + available) / requiredSampleRate,
          waveform.length / requiredSampleRate,
        ),
      );
      embeddings.add(
        BirdnetEmbeddingWindow(embedding: result.embedding, interval: interval),
      );
      for (final species in _species) {
        if (species.outputIndex >= scores.length) continue;
        final score = scores[species.outputIndex];
        if (score < _threshold) continue;
        final current = bestBySpecies[species];
        if (current == null) {
          bestBySpecies[species] = _BirdScore(score, [interval]);
        } else {
          current.confidence = math.max(current.confidence, score);
          current.intervals.add(interval);
        }
      }
    }

    final detections =
        bestBySpecies.entries
            .map(
              (entry) => SoundDetection(
                categoryId: 'bird',
                nameZh: '鸟类鸣叫',
                confidence: entry.value.confidence.clamp(0, 1),
                model: '$modelId-$modelVersion',
                intervals: entry.value.intervals,
                specificSpecies: SpeciesCandidate(
                  nameZh: entry.key.nameZh,
                  scientificName: entry.key.scientificName,
                ),
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => right.confidence.compareTo(left.confidence));
    final result = detections.take(3).toList(growable: false);
    timer.stop();
    AppLog.info(
      'birdnet',
      'inference_completed',
      traceId: input.recordingId,
      fields: {
        'duration_ms': timer.elapsedMilliseconds,
        'window_count': (waveform.length / _windowSamples).ceil(),
        'detection_count': result.length,
      },
    );
    return BirdnetDetectionResult(result, embeddings);
  }

  Future<_BirdnetWindowResult> _runWindow(Float32List window) async {
    final outputShape = _interpreter.getOutputTensor(0).shape;
    final output = createTensorOutputBuffer(outputShape);
    if (_interpreter.getOutputTensors().length != 2) {
      throw StateError(
        'BirdNET model is missing its explicit embedding output',
      );
    }
    final embeddingShape = _interpreter.getOutputTensor(1).shape;
    final embeddingOutput = createTensorOutputBuffer(embeddingShape);
    await _isolate.runForMultipleInputs(
      [
        [window],
      ],
      {0: output, 1: embeddingOutput},
    );
    final embedding = flattenTensorOutput(embeddingOutput);
    if (embedding.length != 1024) {
      throw StateError('BirdNET embedding output changed: ${embedding.length}');
    }
    return _BirdnetWindowResult(
      flattenTensorOutput(
        output,
      ).map(birdnetLogitToProbability).toList(growable: false),
      Float32List.fromList(embedding),
    );
  }

  Future<void> close() async {
    await _isolate.close();
    _interpreter.close();
    AppLog.debug('birdnet', 'model_closed');
  }
}

double birdnetLogitToProbability(double logit) {
  return 1 / (1 + math.exp(-logit));
}

class BirdnetDetectionResult {
  const BirdnetDetectionResult(this.detections, this.embeddings);

  final List<SoundDetection> detections;
  final List<BirdnetEmbeddingWindow> embeddings;
}

class _BirdnetWindowResult {
  const _BirdnetWindowResult(this.scores, this.embedding);

  final List<double> scores;
  final Float32List embedding;
}

class _BirdScore {
  _BirdScore(this.confidence, this.intervals);

  double confidence;
  final List<DetectionInterval> intervals;
}
