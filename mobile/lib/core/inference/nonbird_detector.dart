import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/inference/nonbird_species.dart';
import 'package:nature_sound_detective/core/inference/tensor_output_buffer.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class BirdnetEmbeddingWindow {
  const BirdnetEmbeddingWindow({
    required this.embedding,
    required this.interval,
  });

  final Float32List embedding;
  final DetectionInterval interval;
}

class NonBirdDetector {
  NonBirdDetector._(this._interpreter, this._isolate, this.catalog);

  static Future<NonBirdDetector?> tryLoad() async {
    final source = await rootBundle.loadString('assets/models/nonbird.json');
    final catalog = NonBirdModelCatalog.fromJson(source);
    if (!catalog.available) {
      AppLog.info('nonbird', 'model_not_installed');
      return null;
    }
    final interpreter = await Interpreter.fromAsset(
      'assets/models/nonbird.tflite',
      options: InterpreterOptions()..threads = 2,
    );
    return NonBirdDetector._(
      interpreter,
      await IsolateInterpreter.create(
        address: interpreter.address,
        debugName: 'NonBirdInference',
      ),
      catalog,
    );
  }

  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;
  final NonBirdModelCatalog catalog;

  Future<List<SoundDetection>> detectEmbeddings(
    List<BirdnetEmbeddingWindow> windows,
  ) async {
    if (windows.isEmpty) return const [];
    final best = <NonBirdSpecies, _NonBirdScore>{};
    for (final window in windows) {
      final outputShape = _interpreter.getOutputTensor(0).shape;
      final output = createTensorOutputBuffer(outputShape);
      await _isolate.run([window.embedding], output);
      final logits = flattenTensorOutput(output);
      for (final species in catalog.species) {
        if (species.outputIndex >= logits.length ||
            species.taxonId == 'background') {
          continue;
        }
        final probability = 1 / (1 + math.exp(-logits[species.outputIndex]));
        if (probability < species.threshold) continue;
        final current = best[species];
        if (current == null) {
          best[species] = _NonBirdScore(probability, [window.interval]);
        } else {
          current.confidence = math.max(current.confidence, probability);
          current.intervals.add(window.interval);
        }
      }
    }
    final detections =
        best.entries
            .map((entry) {
              final species = entry.key;
              return SoundDetection(
                categoryId: species.categoryId,
                nameZh: species.categoryId == 'frog' ? '蛙类鸣叫' : '昆虫鸣叫',
                confidence: entry.value.confidence.clamp(0, 1),
                model: '${catalog.modelId}-${catalog.version}',
                intervals: entry.value.intervals,
                specificSpecies: species.scientificName == null
                    ? null
                    : SpeciesCandidate(
                        nameZh: species.nameZh,
                        scientificName: species.scientificName,
                        taxonomyId: species.taxonId,
                      ),
              );
            })
            .toList(growable: false)
          ..sort((left, right) => right.confidence.compareTo(left.confidence));
    return detections;
  }

  Future<void> close() async {
    await _isolate.close();
    _interpreter.close();
  }
}

class _NonBirdScore {
  _NonBirdScore(this.confidence, this.intervals);

  double confidence;
  final List<DetectionInterval> intervals;
}
