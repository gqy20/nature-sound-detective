import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/inference/birdnet_detector.dart';

void main() {
  test('converts BirdNET logits to probabilities', () {
    expect(birdnetLogitToProbability(0), closeTo(0.5, 1e-9));
    expect(birdnetLogitToProbability(-4), closeTo(0.017986, 1e-6));
    expect(birdnetLogitToProbability(4), closeTo(0.982014, 1e-6));
  });
}
