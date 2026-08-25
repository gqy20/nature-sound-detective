import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';
import 'package:nature_sound_detective/core/guidance/parent_guidance_engine.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

void main() {
  const detection = SoundDetection(
    categoryId: 'bird',
    nameZh: '鸟鸣',
    confidence: .7,
    model: 'BirdNET',
    specificSpecies: SpeciesCandidate(nameZh: '乌鸫'),
  );

  test('provides two to three parent directions', () {
    final bundle = const ParentGuidanceEngine().build(
      detection: detection,
      observations: const {},
      behaviors: const {},
    );

    expect(bundle.guides.length, inInclusiveRange(2, 3));
    expect(bundle.guides.first.say, contains('先不看候选'));
    expect(bundle.guides.every((item) => item.avoid.isNotEmpty), isTrue);
  });

  test('praise is tied to observed behavior', () {
    final bundle = const ParentGuidanceEngine().build(
      detection: detection,
      observations: const {
        'habitat': ['tree_canopy'],
        'sound_pattern': ['repeated'],
      },
      behaviors: const {
        ExplorationBehavior.replayedAudio,
        ExplorationBehavior.comparedEvidence,
        ExplorationBehavior.acceptedUncertainty,
      },
    );

    expect(bundle.praiseSuggestions, hasLength(3));
    expect(bundle.praiseSuggestions.first.text, contains('重新听'));
    expect(bundle.praiseSuggestions.last.text, contains('暂时不知道'));
  });
}
