import 'dart:math' as math;

import 'package:nature_sound_detective/core/inference/audio_inference.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

class NatureDetectionFusion implements DetectionFusion {
  const NatureDetectionFusion({
    this.birdCandidateThreshold = 0.10,
    this.birdStandaloneSpeciesThreshold = 0.20,
    this.birdSupportedTentativeThreshold = 0.05,
    this.birdStandaloneTentativeThreshold = 0.08,
    this.nonBirdStandaloneSpeciesThreshold = 0.65,
    this.nonBirdSupportedSpeciesThreshold = 0.35,
    this.maxBirdCandidates = 3,
    this.maxGeneralCategories = 4,
  });

  final double birdCandidateThreshold;
  final double birdStandaloneSpeciesThreshold;
  final double birdSupportedTentativeThreshold;
  final double birdStandaloneTentativeThreshold;
  final double nonBirdStandaloneSpeciesThreshold;
  final double nonBirdSupportedSpeciesThreshold;
  final int maxBirdCandidates;
  final int maxGeneralCategories;

  @override
  List<SoundDetection> fuse(Iterable<List<SoundDetection>> modelOutputs) {
    final valid = modelOutputs
        .expand((items) => items)
        .where(
          (item) =>
              item.confidence.isFinite &&
              item.confidence > 0 &&
              item.categoryId.isNotEmpty,
        )
        .toList(growable: false);
    if (valid.isEmpty) return const [];

    final genericGroups = <String, List<SoundDetection>>{};
    final speciesGroups = <String, List<SoundDetection>>{};
    for (final detection in valid) {
      final species = detection.specificSpecies;
      if (species == null) {
        genericGroups
            .putIfAbsent(detection.categoryId, () => [])
            .add(detection);
      } else {
        speciesGroups
            .putIfAbsent(_speciesKey(detection), () => [])
            .add(detection);
      }
    }

    final originalGeneric = {
      for (final entry in genericGroups.entries)
        entry.key: _mergeGroup(entry.value),
    };
    final reliableSpecies = <SoundDetection>[];
    final tentativeBirdSpecies = <SoundDetection>[];
    for (final group in speciesGroups.values) {
      final candidate = _mergeGroup(group);
      final genericSupport = originalGeneric[candidate.categoryId];
      if (candidate.categoryId == 'bird') {
        final supported = _hasIndependentTemporalSupport(
          candidate,
          genericSupport,
        );
        if (candidate.confidence >= birdCandidateThreshold &&
            (supported ||
                candidate.confidence >= birdStandaloneSpeciesThreshold)) {
          reliableSpecies.add(
            supported
                ? _withGenericSupport(candidate, genericSupport!)
                : candidate,
          );
        } else if ((supported &&
                candidate.confidence >= birdSupportedTentativeThreshold) ||
            (!supported &&
                candidate.confidence >= birdStandaloneTentativeThreshold)) {
          tentativeBirdSpecies.add(
            _asTentative(
              supported
                  ? _withGenericSupport(candidate, genericSupport!)
                  : candidate,
            ),
          );
        }
        continue;
      }

      if (_modelFamilies(candidate).contains('nonbird')) {
        final supported = _hasIndependentTemporalSupport(
          candidate,
          genericSupport,
        );
        if (candidate.confidence >= nonBirdStandaloneSpeciesThreshold ||
            (supported &&
                candidate.confidence >= nonBirdSupportedSpeciesThreshold)) {
          reliableSpecies.add(
            supported
                ? _withGenericSupport(candidate, genericSupport!)
                : candidate,
          );
        } else {
          final downgraded = _downgradeToCategory(candidate);
          if (downgraded.confidence >= 0.25) {
            genericGroups
                .putIfAbsent(candidate.categoryId, () => [])
                .add(downgraded);
          }
        }
        continue;
      }
      reliableSpecies.add(candidate);
    }

    final generic = {
      for (final entry in genericGroups.entries)
        entry.key: _mergeGroup(entry.value),
    };
    final birdSpecies =
        reliableSpecies
            .where((item) => item.categoryId == 'bird')
            .toList(growable: false)
          ..sort((left, right) => right.confidence.compareTo(left.confidence));
    final generalSpecies =
        reliableSpecies
            .where((item) => item.categoryId != 'bird')
            .toList(growable: false)
          ..sort((left, right) => right.confidence.compareTo(left.confidence));
    tentativeBirdSpecies.sort(
      (left, right) => right.confidence.compareTo(left.confidence),
    );
    final birdCandidates = <SoundDetection>[
      ...birdSpecies,
      ...tentativeBirdSpecies,
    ]..sort((left, right) => right.confidence.compareTo(left.confidence));

    final general = <SoundDetection>[...generalSpecies];
    for (final item in generic.values) {
      if (item.categoryId == 'bird') continue;
      final coveredBySpecies = generalSpecies.any(
        (species) =>
            species.categoryId == item.categoryId &&
            _intervalsOverlap(species.intervals, item.intervals),
      );
      if (!coveredBySpecies) general.add(item);
    }
    general.sort((left, right) => _rank(right).compareTo(_rank(left)));

    final result = <SoundDetection>[
      if (birdCandidates.isNotEmpty)
        ...birdCandidates.take(maxBirdCandidates)
      else
        ?generic['bird'],
      ...general.take(maxGeneralCategories),
    ];
    final adjusted = _applyConflictPenalty(result);
    adjusted.sort((left, right) => _rank(right).compareTo(_rank(left)));
    return adjusted;
  }

  String _speciesKey(SoundDetection detection) {
    final species = detection.specificSpecies!;
    final identity =
        species.taxonomyId ??
        species.scientificName?.toLowerCase() ??
        species.nameZh;
    return '${detection.categoryId}|$identity';
  }

  SoundDetection _mergeGroup(List<SoundDetection> group) {
    final sorted = [...group]
      ..sort((left, right) => right.confidence.compareTo(left.confidence));
    final primary = sorted.first;
    final models = <String>{
      for (final item in sorted) ...item.evidenceModels,
    }.toList(growable: false);
    final familyCount = models.map(_modelFamily).toSet().length;
    final agreementBonus = math.min(0.08, math.max(0, familyCount - 1) * 0.04);
    return SoundDetection(
      categoryId: primary.categoryId,
      nameZh: primary.nameZh,
      confidence: math.min(1, primary.confidence + agreementBonus),
      model: primary.model,
      supportingModels: models,
      intervals: _mergeIntervals(sorted.expand((item) => item.intervals)),
      specificSpecies: primary.specificSpecies,
      tentative: sorted.every((item) => item.tentative),
    );
  }

  SoundDetection _downgradeToCategory(SoundDetection candidate) {
    final name = switch (candidate.categoryId) {
      'frog' => '蛙类鸣叫',
      'insect' => '昆虫鸣叫',
      'bird' => '鸟类鸣叫',
      _ => candidate.nameZh,
    };
    return SoundDetection(
      categoryId: candidate.categoryId,
      nameZh: name,
      confidence: candidate.confidence * 0.7,
      model: candidate.model,
      supportingModels: candidate.evidenceModels,
      intervals: candidate.intervals,
    );
  }

  SoundDetection _withGenericSupport(
    SoundDetection species,
    SoundDetection generic,
  ) {
    final models = <String>{
      ...species.evidenceModels,
      ...generic.evidenceModels,
    }.toList(growable: false);
    return SoundDetection(
      categoryId: species.categoryId,
      nameZh: species.nameZh,
      confidence: math.min(1, species.confidence + 0.04),
      model: species.model,
      supportingModels: models,
      intervals: _mergeIntervals([...species.intervals, ...generic.intervals]),
      specificSpecies: species.specificSpecies,
      tentative: species.tentative,
    );
  }

  SoundDetection _asTentative(SoundDetection candidate) {
    return SoundDetection(
      categoryId: candidate.categoryId,
      nameZh: candidate.nameZh,
      confidence: candidate.confidence,
      model: candidate.model,
      supportingModels: candidate.evidenceModels,
      intervals: candidate.intervals,
      specificSpecies: candidate.specificSpecies,
      tentative: true,
    );
  }

  bool _hasIndependentTemporalSupport(
    SoundDetection candidate,
    SoundDetection? generic,
  ) {
    if (generic == null ||
        !_intervalsOverlap(candidate.intervals, generic.intervals)) {
      return false;
    }
    final candidateFamilies = _modelFamilies(candidate);
    return _modelFamilies(
      generic,
    ).any((family) => !candidateFamilies.contains(family));
  }

  List<DetectionInterval> _mergeIntervals(
    Iterable<DetectionInterval> intervals,
  ) {
    final sorted = intervals.toList(growable: false)
      ..sort((left, right) => left.startSeconds.compareTo(right.startSeconds));
    if (sorted.isEmpty) return const [];
    final merged = <DetectionInterval>[sorted.first];
    for (final interval in sorted.skip(1)) {
      final previous = merged.last;
      if (interval.startSeconds <= previous.endSeconds + 0.05) {
        merged[merged.length - 1] = DetectionInterval(
          startSeconds: previous.startSeconds,
          endSeconds: math.max(previous.endSeconds, interval.endSeconds),
        );
      } else {
        merged.add(interval);
      }
    }
    return merged;
  }

  bool _intervalsOverlap(
    List<DetectionInterval> left,
    List<DetectionInterval> right,
  ) {
    if (left.isEmpty || right.isEmpty) return true;
    return left.any(
      (a) => right.any(
        (b) =>
            math.min(a.endSeconds, b.endSeconds) -
                math.max(a.startSeconds, b.startSeconds) >
            0.1,
      ),
    );
  }

  List<SoundDetection> _applyConflictPenalty(List<SoundDetection> detections) {
    const vocalCategories = {'bird', 'frog', 'insect'};
    return detections
        .map((candidate) {
          if (!vocalCategories.contains(candidate.categoryId)) return candidate;
          final strongerConflict = detections.any((other) {
            if (identical(other, candidate) ||
                other.categoryId == candidate.categoryId ||
                !vocalCategories.contains(other.categoryId) ||
                !_intervalsOverlap(candidate.intervals, other.intervals)) {
              return false;
            }
            final otherHasMoreSupport =
                _modelFamilies(other).length > _modelFamilies(candidate).length;
            return other.confidence >= candidate.confidence + 0.15 ||
                (otherHasMoreSupport &&
                    other.confidence >= candidate.confidence);
          });
          if (!strongerConflict) return candidate;
          return SoundDetection(
            categoryId: candidate.categoryId,
            nameZh: candidate.nameZh,
            confidence: candidate.confidence * 0.82,
            model: candidate.model,
            supportingModels: candidate.evidenceModels,
            intervals: candidate.intervals,
            specificSpecies: candidate.specificSpecies,
            tentative: candidate.tentative,
          );
        })
        .toList(growable: false);
  }

  Set<String> _modelFamilies(SoundDetection detection) =>
      detection.evidenceModels.map(_modelFamily).toSet();

  String _modelFamily(String model) {
    final normalized = model.toLowerCase();
    if (normalized.contains('birdnet')) return 'birdnet';
    if (normalized.contains('nonbird')) return 'nonbird';
    if (normalized.contains('yamnet')) return 'yamnet';
    return normalized;
  }

  double _rank(SoundDetection detection) {
    final speciesBonus = detection.specificSpecies == null ? 0.0 : 0.03;
    final supportBonus = math.min(
      0.04,
      (_modelFamilies(detection).length - 1) * 0.02,
    );
    final tentativePenalty = detection.tentative ? 0.05 : 0.0;
    return math.min(1, detection.confidence) +
        speciesBonus +
        supportBonus -
        tentativePenalty;
  }
}
