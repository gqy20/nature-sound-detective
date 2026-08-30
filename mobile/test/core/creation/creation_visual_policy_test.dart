import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/creation/creation_visual_policy.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

void main() {
  test('shows supported animals only for non-tentative specific species', () {
    expect(selectCreationVisualMode(null), CreationVisualMode.environment);
    expect(
      selectCreationVisualMode(_detection(categoryId: 'bird')),
      CreationVisualMode.bird,
    );
    expect(
      selectCreationVisualMode(_detection(categoryId: 'frog')),
      CreationVisualMode.frog,
    );
    expect(
      selectCreationVisualMode(_detection(categoryId: 'insect')),
      CreationVisualMode.environment,
    );
    expect(
      selectCreationVisualMode(_detection(categoryId: 'bird', tentative: true)),
      CreationVisualMode.environment,
    );
    expect(
      selectCreationVisualMode(
        _detection(categoryId: 'bird', hasSpecificSpecies: false),
      ),
      CreationVisualMode.environment,
    );
  });
}

SoundDetection _detection({
  required String categoryId,
  bool tentative = false,
  bool hasSpecificSpecies = true,
}) => SoundDetection(
  categoryId: categoryId,
  nameZh: '候选声音',
  confidence: 0.9,
  model: 'test',
  tentative: tentative,
  specificSpecies: hasSpecificSpecies
      ? const SpeciesCandidate(nameZh: '候选物种')
      : null,
);
