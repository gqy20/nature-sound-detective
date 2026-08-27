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
  bool _closed = false;

  Future<List<SoundDetection>> detectEmbeddings(
    List<BirdnetEmbeddingWindow> windows,
  ) async {
    if (windows.isEmpty) return const [];
    final scores = <_WindowScores>[];
    for (final window in windows) {
      final outputShape = _interpreter.getOutputTensor(0).shape;
      final output = createTensorOutputBuffer(outputShape);
      await _isolate.run([window.embedding], output);
      final logits = flattenTensorOutput(output);
      scores.add(
        _WindowScores(window, [
          for (final value in logits) 1 / (1 + math.exp(-value)),
        ]),
      );
    }
    final best = <NonBirdSpecies, _NonBirdScore>{};
    final background = catalog.species
        .where((item) => item.taxonId == 'background')
        .firstOrNull;
    final candidates = catalog.species
        .where((item) => item.taxonId != 'background')
        .toList(growable: false);
    for (final species in candidates) {
      final active = <int>[];
      for (var index = 0; index < scores.length; index++) {
        final item = scores[index];
        if (species.outputIndex >= item.probabilities.length) continue;
        final probability = item.probabilities[species.outputIndex];
        final backgroundProbability =
            background == null ||
                background.outputIndex >= item.probabilities.length
            ? 0.0
            : item.probabilities[background.outputIndex];
        var runnerUp = 0.0;
        for (final other in candidates) {
          if (other == species ||
              other.outputIndex >= item.probabilities.length) {
            continue;
          }
          runnerUp = math.max(runnerUp, item.probabilities[other.outputIndex]);
        }
        final requiredTopMargin = requiredNonBirdTopMargin(
          species,
          catalog.rejection,
        );
        final classifierAccepted =
            probability >= species.threshold &&
            probability - backgroundProbability >=
                catalog.rejection.backgroundMargin &&
            (requiredTopMargin <= 0 ||
                probability - runnerUp >= requiredTopMargin) &&
            _cosine(item.window.embedding, species.centroid) >=
                species.minCosineSimilarity;
        final referenceSimilarity = _referenceSimilarity(
          item.window.embedding,
          species,
        );
        var referenceRunnerUp = -1.0;
        for (final other in candidates) {
          if (other == species) continue;
          referenceRunnerUp = math.max(
            referenceRunnerUp,
            _referenceSimilarity(item.window.embedding, other),
          );
        }
        final referenceAccepted =
            catalog.officialReference.enabled &&
            probability >=
                math.min(
                  species.threshold,
                  catalog.officialReference.minimumClassifierProbability,
                ) &&
            referenceSimilarity >= species.officialReferenceMinSimilarity &&
            referenceSimilarity - referenceRunnerUp >=
                catalog.officialReference.minimumTopMargin;
        if (!classifierAccepted && !referenceAccepted) {
          continue;
        }
        active.add(index);
        item.referenceMatches[species] = referenceAccepted
            ? referenceSimilarity
            : null;
      }
      final accepted = _temporallySupported(active, scores, species);
      for (final index in accepted) {
        final item = scores[index];
        final probability = item.probabilities[species.outputIndex];
        final current = best[species];
        if (current == null) {
          best[species] = _NonBirdScore(probability, [
            item.window.interval,
          ], referenceSimilarity: item.referenceMatches[species]);
        } else {
          current.confidence = math.max(current.confidence, probability);
          current.intervals.add(item.window.interval);
          final referenceMatch = item.referenceMatches[species];
          if (referenceMatch != null) {
            current.referenceSimilarity = math.max(
              current.referenceSimilarity ?? -1,
              referenceMatch,
            );
          }
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
                supportingModels: entry.value.referenceSimilarity == null
                    ? const []
                    : [
                        '${catalog.modelId}-${catalog.version}',
                        'official-reference-match',
                      ],
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

  Set<int> _temporallySupported(
    List<int> active,
    List<_WindowScores> scores,
    NonBirdSpecies species,
  ) {
    final accepted = <int>{};
    var run = <int>[];
    void finishRun() {
      if (run.length >= catalog.rejection.minSupportingWindows) {
        accepted.addAll(run);
      } else if (run.length == 1 &&
          scores[run.single].probabilities[species.outputIndex] >=
              species.threshold + catalog.rejection.shortClipThresholdExcess) {
        accepted.add(run.single);
      }
      run = <int>[];
    }

    for (final index in active) {
      if (run.isNotEmpty &&
          scores[index].window.interval.startSeconds >
              scores[run.last].window.interval.endSeconds +
                  catalog.rejection.maxWindowGapSeconds) {
        finishRun();
      }
      run.add(index);
    }
    finishRun();
    return accepted;
  }

  double _cosine(Float32List embedding, List<double> centroid) {
    if (centroid.length != embedding.length) return 1;
    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;
    for (var index = 0; index < embedding.length; index++) {
      dot += embedding[index] * centroid[index];
      leftNorm += embedding[index] * embedding[index];
      rightNorm += centroid[index] * centroid[index];
    }
    if (leftNorm <= 0 || rightNorm <= 0) return -1;
    return dot / math.sqrt(leftNorm * rightNorm);
  }

  double _referenceSimilarity(Float32List embedding, NonBirdSpecies species) {
    var best = -1.0;
    for (final prototype in species.officialReferencePrototypes) {
      best = math.max(best, _cosine(embedding, prototype));
    }
    return best;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _isolate.close();
    _interpreter.close();
  }
}

class _NonBirdScore {
  _NonBirdScore(this.confidence, this.intervals, {this.referenceSimilarity});

  double confidence;
  final List<DetectionInterval> intervals;
  double? referenceSimilarity;
}

class _WindowScores {
  _WindowScores(this.window, this.probabilities);

  final BirdnetEmbeddingWindow window;
  final List<double> probabilities;
  final Map<NonBirdSpecies, double?> referenceMatches = {};
}
