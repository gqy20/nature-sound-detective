import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/audio/pcm_resampler.dart';
import 'package:nature_sound_detective/core/inference/audio_inference.dart';
import 'package:nature_sound_detective/core/inference/tensor_output_buffer.dart';
import 'package:nature_sound_detective/core/inference/yamnet_category_map.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class YamnetDetector implements AudioDetector {
  YamnetDetector._({
    required this._interpreter,
    required this._isolate,
    required YamnetLabelMap labels,
  }) : _indicesByCategory = labels.indicesByCategory();

  static Future<YamnetDetector> load() async {
    final timer = Stopwatch()..start();
    AppLog.info(
      'yamnet',
      'model_load_started',
      fields: {'model_version': 'tflite-1'},
    );
    try {
      final results = await Future.wait<Object>([
        Interpreter.fromAsset('assets/models/yamnet.tflite'),
        rootBundle.loadString('assets/labels/yamnet.csv'),
      ]);
      final interpreter = results[0] as Interpreter;
      final detector = YamnetDetector._(
        interpreter: interpreter,
        isolate: await IsolateInterpreter.create(
          address: interpreter.address,
          debugName: 'YamnetInference',
        ),
        labels: YamnetLabelMap.fromCsv(results[1] as String),
      );
      timer.stop();
      AppLog.info(
        'yamnet',
        'model_load_completed',
        fields: {
          'duration_ms': timer.elapsedMilliseconds,
          'model_version': detector.modelVersion,
        },
      );
      return detector;
    } catch (error, stackTrace) {
      timer.stop();
      AppLog.error(
        'yamnet',
        'model_load_failed',
        fields: {'duration_ms': timer.elapsedMilliseconds},
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static const _windowSamples = 15600;
  static const _hopSamples = 7800;
  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;
  final Map<String, List<int>> _indicesByCategory;

  @override
  String get modelId => 'yamnet';

  @override
  String get modelVersion => 'tflite-1';

  @override
  int get requiredSampleRate => 16000;

  @override
  Future<List<SoundDetection>> detect(AudioInferenceInput input) async {
    final timer = Stopwatch()..start();
    final waveform = PcmResampler.toMonoFloat32(
      input,
      outputSampleRate: requiredSampleRate,
    );
    if (waveform.isEmpty) {
      AppLog.warning('yamnet', 'empty_input', traceId: input.recordingId);
      return const [];
    }

    final frameScores = <List<double>>[];
    for (var offset = 0; offset < waveform.length; offset += _hopSamples) {
      final window = Float32List(_windowSamples);
      final available = math.min(_windowSamples, waveform.length - offset);
      window.setRange(0, available, waveform, offset);
      frameScores.add(await _runWindow(window));
      if (offset + _windowSamples >= waveform.length) break;
    }
    final detections = _aggregate(frameScores);
    timer.stop();
    AppLog.info(
      'yamnet',
      'inference_completed',
      traceId: input.recordingId,
      fields: {
        'duration_ms': timer.elapsedMilliseconds,
        'window_count': frameScores.length,
        'detection_count': detections.length,
      },
    );
    return detections;
  }

  Future<List<double>> _runWindow(Float32List window) async {
    final inputShape = _interpreter.getInputTensor(0).shape;
    final outputShape = _interpreter.getOutputTensor(0).shape;
    final input = inputShape.length == 2 ? [window] : window;
    final output = createTensorOutputBuffer(outputShape);
    await _isolate.run(input, output);
    return flattenTensorOutput(output);
  }

  List<SoundDetection> _aggregate(List<List<double>> frames) {
    final detections = <SoundDetection>[];
    for (final category in yamnetNatureCategories) {
      final indices = _indicesByCategory[category.id] ?? const [];
      if (indices.isEmpty) continue;
      final scores = frames
          .map(
            (frame) => indices
                .where((index) => index < frame.length)
                .map((index) => frame[index])
                .fold<double>(0, math.max),
          )
          .toList(growable: false);
      final confidence = scores.fold<double>(0, math.max);
      if (confidence < category.threshold) continue;
      detections.add(
        SoundDetection(
          categoryId: category.id,
          nameZh: category.nameZh,
          confidence: confidence.clamp(0, 1),
          model: '$modelId-$modelVersion',
          intervals: _intervals(scores, category.threshold),
        ),
      );
    }
    detections.sort(
      (left, right) => right.confidence.compareTo(left.confidence),
    );
    return detections;
  }

  List<DetectionInterval> _intervals(List<double> scores, double threshold) {
    final intervals = <DetectionInterval>[];
    int? startFrame;
    for (var index = 0; index <= scores.length; index++) {
      final active = index < scores.length && scores[index] >= threshold;
      if (active && startFrame == null) startFrame = index;
      if (!active && startFrame != null) {
        intervals.add(
          DetectionInterval(
            startSeconds: startFrame * _hopSamples / requiredSampleRate,
            endSeconds:
                ((index - 1) * _hopSamples + _windowSamples) /
                requiredSampleRate,
          ),
        );
        startFrame = null;
      }
    }
    return intervals;
  }

  Future<void> close() async {
    await _isolate.close();
    _interpreter.close();
    AppLog.debug('yamnet', 'model_closed');
  }
}
