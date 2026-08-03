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
          _detection('bird', 0.10, model: 'birdnet', species: '白头鹎'),
        ],
      ]);

      expect(result.where((item) => item.categoryId == 'bird'), hasLength(1));
      expect(result.first.specificSpecies?.nameZh, '乌鸫');
    },
  );

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
}) {
  return SoundDetection(
    categoryId: category,
    nameZh: category,
    confidence: confidence.isFinite ? confidence.clamp(0, 1) : 0,
    model: model,
    specificSpecies: species == null ? null : SpeciesCandidate(nameZh: species),
  );
}
