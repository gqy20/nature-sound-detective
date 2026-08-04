import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/fusion/nature_detection_fusion.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

void main() {
  const fusion = NatureDetectionFusion();

  test(
    'replaces generic bird class with strong BirdNET species candidates',
    () {
      final result = fusion.fuse([
        [_detection('bird', 0.8, model: 'yamnet')],
        [
          _detection('bird', 0.72, model: 'birdnet', species: '乌鸫'),
          _detection('bird', 0.04, model: 'birdnet', species: '白头鹎'),
        ],
      ]);

      expect(result.where((item) => item.categoryId == 'bird'), hasLength(1));
      expect(result.first.specificSpecies?.nameZh, '乌鸫');
      expect(result.first.tentative, isFalse);
    },
  );

  test('keeps one supported weak bird species as a tentative guess', () {
    final result = fusion.fuse([
      [
        _detection(
          'bird',
          0.62,
          model: 'yamnet',
          interval: const DetectionInterval(startSeconds: 3, endSeconds: 5),
        ),
      ],
      [
        _detection(
          'bird',
          0.07,
          model: 'birdnet',
          species: '乌鸫',
          interval: const DetectionInterval(startSeconds: 3, endSeconds: 6),
        ),
        _detection(
          'bird',
          0.04,
          model: 'birdnet',
          species: '白头鹎',
          interval: const DetectionInterval(startSeconds: 3, endSeconds: 6),
        ),
      ],
    ]);

    expect(result.where((item) => item.categoryId == 'bird'), hasLength(1));
    expect(result.single.specificSpecies?.nameZh, '乌鸫');
    expect(result.single.tentative, isTrue);
    expect(result.single.evidenceModels, containsAll(['birdnet', 'yamnet']));
  });

  test('does not expose a very weak unsupported bird species', () {
    final result = fusion.fuse([
      [_detection('bird', 0.06, model: 'birdnet', species: '乌鸫')],
    ]);

    expect(result, isEmpty);
  });

  test('promotes a supported low-score bird to an exact clue', () {
    final result = fusion.fuse([
      [
        _detection(
          'bird',
          0.60,
          model: 'yamnet',
          interval: const DetectionInterval(startSeconds: 1, endSeconds: 3),
        ),
      ],
      [
        _detection(
          'bird',
          0.12,
          model: 'birdnet',
          species: '白头鹎',
          interval: const DetectionInterval(startSeconds: 1, endSeconds: 4),
        ),
      ],
    ]);

    expect(result.single.specificSpecies?.nameZh, '白头鹎');
    expect(result.single.tentative, isFalse);
  });

  test('keeps the top three bird species candidates by confidence', () {
    final result = fusion.fuse([
      [_detection('bird', 0.70, model: 'yamnet')],
      [
        _detection('bird', 0.42, model: 'birdnet', species: '乌鸫'),
        _detection('bird', 0.31, model: 'birdnet', species: '白头鹎'),
        _detection('bird', 0.18, model: 'birdnet', species: '喜鹊'),
        _detection('bird', 0.12, model: 'birdnet', species: '麻雀'),
      ],
    ]);

    expect(result.map((item) => item.specificSpecies?.nameZh), [
      '乌鸫',
      '白头鹎',
      '喜鹊',
    ]);
  });

  test('keeps mixed non-bird soundscape categories', () {
    final result = fusion.fuse([
      [
        _detection('frog', 0.82, model: 'yamnet'),
        _detection('running_water', 0.67, model: 'yamnet'),
      ],
      const [],
    ]);

    expect(result.map((item) => item.categoryId), ['frog', 'running_water']);
  });

  test('keeps exact non-bird species beside a bird candidate', () {
    final result = fusion.fuse([
      [
        _detection('insect', 0.78, model: 'nonbird', species: '黑蚱蝉'),
        _detection('bird', 0.72, model: 'birdnet', species: '乌鸫'),
      ],
    ]);

    expect(
      result.map((item) => item.specificSpecies?.nameZh),
      containsAll(['黑蚱蝉', '乌鸫']),
    );
  });

  test('merges the same generic category across model families', () {
    final result = fusion.fuse([
      [
        _detection(
          'insect',
          0.58,
          model: 'yamnet',
          interval: const DetectionInterval(startSeconds: 2.9, endSeconds: 4.4),
        ),
      ],
      [
        _detection(
          'insect',
          0.70,
          model: 'challenge-nonbird',
          interval: const DetectionInterval(startSeconds: 3, endSeconds: 6),
        ),
      ],
    ]);

    expect(result.where((item) => item.categoryId == 'insect'), hasLength(1));
    final insect = result.single;
    expect(insect.evidenceModels, containsAll(['yamnet', 'challenge-nonbird']));
    expect(insect.intervals.single.startSeconds, 2.9);
    expect(insect.intervals.single.endSeconds, 6);
  });

  test('downgrades an unsupported medium non-bird species to a category', () {
    final result = fusion.fuse([
      [_detection('frog', 0.50, model: 'challenge-nonbird', species: '孟闻琴蛙')],
    ]);

    expect(result.single.categoryId, 'frog');
    expect(result.single.specificSpecies, isNull);
    expect(result.single.nameZh, '蛙类鸣叫');
    expect(result.single.confidence, closeTo(0.35, 0.0001));
  });

  test('keeps a medium species when another model supports its category', () {
    final result = fusion.fuse([
      [
        _detection(
          'frog',
          0.45,
          model: 'yamnet',
          interval: const DetectionInterval(startSeconds: 6, endSeconds: 8),
        ),
      ],
      [
        _detection(
          'frog',
          0.50,
          model: 'challenge-nonbird',
          species: '孟闻琴蛙',
          interval: const DetectionInterval(startSeconds: 6, endSeconds: 9),
        ),
      ],
    ]);

    expect(result.single.specificSpecies?.nameZh, '孟闻琴蛙');
    expect(
      result.single.evidenceModels,
      containsAll(['yamnet', 'challenge-nonbird']),
    );
  });

  test(
    'penalizes an overlapping single-model category with weaker evidence',
    () {
      final result = fusion.fuse([
        [
          _detection(
            'bird',
            0.72,
            model: 'yamnet',
            interval: const DetectionInterval(startSeconds: 3, endSeconds: 5),
          ),
          _detection(
            'insect',
            0.68,
            model: 'yamnet',
            interval: const DetectionInterval(startSeconds: 3, endSeconds: 5),
          ),
        ],
        [
          _detection(
            'insect',
            0.70,
            model: 'challenge-nonbird',
            interval: const DetectionInterval(startSeconds: 3, endSeconds: 6),
          ),
        ],
      ]);

      final bird = result.singleWhere((item) => item.categoryId == 'bird');
      expect(bird.confidence, lessThan(0.65));
    },
  );

  test('cleans up the mixed result observed during device validation', () {
    final result = fusion.fuse([
      [
        _detection(
          'bird',
          0.72,
          model: 'yamnet',
          interval: const DetectionInterval(startSeconds: 3.4, endSeconds: 4.9),
        ),
        _detection(
          'insect',
          0.50,
          model: 'yamnet',
          interval: const DetectionInterval(startSeconds: 2.9, endSeconds: 4.4),
        ),
      ],
      [
        _detection(
          'insect',
          0.70,
          model: 'challenge-nonbird',
          interval: const DetectionInterval(startSeconds: 3, endSeconds: 6),
        ),
        _detection(
          'frog',
          0.50,
          model: 'challenge-nonbird',
          species: '孟闻琴蛙',
          interval: const DetectionInterval(startSeconds: 6, endSeconds: 9),
        ),
      ],
    ]);

    expect(result, hasLength(3));
    expect(result.where((item) => item.categoryId == 'insect'), hasLength(1));
    expect(
      result.singleWhere((item) => item.categoryId == 'frog').specificSpecies,
      isNull,
    );
  });

  test('returns no detection for empty or invalid outputs', () {
    final result = fusion.fuse([
      [_detection('frog', double.nan, model: 'yamnet')],
      const [],
    ]);

    expect(result, isEmpty);
  });
}

SoundDetection _detection(
  String category,
  double confidence, {
  required String model,
  String? species,
  DetectionInterval? interval,
}) {
  return SoundDetection(
    categoryId: category,
    nameZh: category,
    confidence: confidence.isFinite ? confidence.clamp(0, 1) : 0,
    model: model,
    intervals: interval == null ? const [] : [interval],
    specificSpecies: species == null ? null : SpeciesCandidate(nameZh: species),
  );
}
