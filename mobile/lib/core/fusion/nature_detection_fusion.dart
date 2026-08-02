import 'dart:math' as math;

import 'package:nature_sound_detective/core/inference/audio_inference.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

class NatureDetectionFusion implements DetectionFusion {
  const NatureDetectionFusion({
    this.birdCandidateThreshold = 0.25,
    this.maxBirdCandidates = 3,
    this.maxGeneralCategories = 4,
  });

  final double birdCandidateThreshold;
  final int maxBirdCandidates;
  final int maxGeneralCategories;

  @override
  List<SoundDetection> fuse(Iterable<List<SoundDetection>> modelOutputs) {
    final all = modelOutputs.expand((items) => items);
    final bestByKey = <String, SoundDetection>{};
    for (final detection in all) {
      if (!detection.confidence.isFinite || detection.confidence <= 0) continue;
      final species = detection.specificSpecies?.scientificName ?? '';
      final key = '${detection.categoryId}|$species|${detection.model}';
      final current = bestByKey[key];
      if (current == null || detection.confidence > current.confidence) {
        bestByKey[key] = detection;
      }
    }

    final birdCandidates =
        bestByKey.values
            .where(
              (item) =>
                  item.categoryId == 'bird' &&
                  item.specificSpecies != null &&
                  item.confidence >= birdCandidateThreshold,
            )
            .toList(growable: false)
          ..sort((left, right) => right.confidence.compareTo(left.confidence));
    final genericBird = bestByKey.values
        .where(
          (item) => item.categoryId == 'bird' && item.specificSpecies == null,
        )
        .fold<SoundDetection?>(
          null,
          (best, item) =>
              best == null || item.confidence > best.confidence ? item : best,
        );
    final general =
        bestByKey.values
            .where((item) => item.categoryId != 'bird')
            .toList(growable: false)
          ..sort((left, right) => right.confidence.compareTo(left.confidence));

    final result = <SoundDetection>[
      if (birdCandidates.isNotEmpty)
        ...birdCandidates.take(maxBirdCandidates)
      else
        ?genericBird,
      ...general.take(maxGeneralCategories),
    ];
    result.sort((left, right) => _rank(right).compareTo(_rank(left)));
    return result;
  }

  double _rank(SoundDetection detection) {
    final speciesBonus = detection.specificSpecies == null ? 0.0 : 0.03;
    return math.min(1, detection.confidence) + speciesBonus;
  }
}
