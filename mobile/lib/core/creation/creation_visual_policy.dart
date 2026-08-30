import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

CreationVisualMode selectCreationVisualMode(SoundDetection? detection) {
  if (detection == null ||
      detection.tentative ||
      detection.specificSpecies == null) {
    return CreationVisualMode.environment;
  }
  return switch (detection.categoryId) {
    'bird' => CreationVisualMode.bird,
    'frog' => CreationVisualMode.frog,
    _ => CreationVisualMode.environment,
  };
}
