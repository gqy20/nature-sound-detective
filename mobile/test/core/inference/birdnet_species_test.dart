import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/inference/birdnet_species.dart';

void main() {
  test('keeps the Hangzhou MVP species indices stable', () {
    expect(hangzhouBirdnetSpecies, hasLength(6));
    expect(
      hangzhouBirdnetSpecies.map((species) => species.outputIndex).toSet(),
      {1550, 2420, 5149, 5746, 6250, 6329},
    );
  });
}
