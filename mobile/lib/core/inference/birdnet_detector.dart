import 'dart:math' as math;
import 'dart:typed_data';

import 'package:nature_sound_detective/core/audio/pcm_resampler.dart';
import 'package:nature_sound_detective/core/inference/audio_inference.dart';
import 'package:nature_sound_detective/core/inference/birdnet_species.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class BirdnetDetector implements AudioDetector {
  BirdnetDetector._(this._interpreter, this._isolate);

  static Future<BirdnetDetector> load() async {
    final options = InterpreterOptions()..threads = 2;
    final interpreter = await Interpreter.fromAsset(
      'assets/models/birdnet.tflite',
      options: options,
    );
    return BirdnetDetector._(
      interpreter,
      await IsolateInterpreter.create(
        address: interpreter.address,
        debugName: 'BirdnetInference',
      ),
    );
  }

  static const _windowSamples = 144000;
  static const _threshold = 0.05;
  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;

  @override
  String get modelId => 'birdnet-acoustic';

  @override
  String get modelVersion => '2.4-fp16';

  @override
  int get requiredSampleRate => 48000;

  @override
  Future<List<SoundDetection>> detect(AudioInferenceInput input) async {
    final waveform = PcmResampler.toMonoFloat32(
      input,
      outputSampleRate: requiredSampleRate,
    );
    if (waveform.isEmpty) return const [];

    final bestBySpecies = <BirdnetSpecies, _BirdScore>{};
    for (var offset = 0; offset < waveform.length; offset += _windowSamples) {
      final window = Float32List(_windowSamples);
      final available = math.min(_windowSamples, waveform.length - offset);
      window.setRange(0, available, waveform, offset);
      final scores = await _runWindow(window);
      for (final species in hangzhouBirdnetSpecies) {
        if (species.outputIndex >= scores.length) continue;
        final score = scores[species.outputIndex];
        if (score < _threshold) continue;
        final interval = DetectionInterval(
          startSeconds: offset / requiredSampleRate,
          endSeconds: math.min(
            (offset + available) / requiredSampleRate,
            waveform.length / requiredSampleRate,
          ),
        );
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
    return detections.take(3).toList(growable: false);
  }

  Future<List<double>> _runWindow(Float32List window) async {
    final outputShape = _interpreter.getOutputTensor(0).shape;
    final outputSize = outputShape.reduce((left, right) => left * right);
    final output = Float32List(outputSize);
    await _isolate.run([window], [output]);
    return output.toList(growable: false);
  }

  Future<void> close() async {
    await _isolate.close();
    _interpreter.close();
  }
}

class _BirdScore {
  _BirdScore(this.confidence, this.intervals);

  double confidence;
  final List<DetectionInterval> intervals;
}
