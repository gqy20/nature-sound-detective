import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nature_sound_detective/core/inference/audio_inference.dart';
import 'package:nature_sound_detective/core/inference/birdnet_detector.dart';
import 'package:nature_sound_detective/core/inference/yamnet_detector.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real local models complete inference on Android', (
    tester,
  ) async {
    final samples = Int16List(48000 * 3);
    for (var index = 0; index < samples.length; index++) {
      final seconds = index / 48000;
      samples[index] = (math.sin(2 * math.pi * 220 * seconds) * 4096).round();
    }
    final input = AudioInferenceInput(
      recordingId: 'integration_tensor_output',
      pcm16le: Uint8List.view(samples.buffer),
      sampleRate: 48000,
      channelCount: 1,
    );

    final yamnet = await YamnetDetector.load();
    final birdnet = await BirdnetDetector.load();
    try {
      final yamnetResult = await yamnet.detect(input);
      final birdnetResult = await birdnet.detect(input);

      expect(yamnetResult, isA<List>());
      expect(birdnetResult, isA<List>());
    } finally {
      await yamnet.close();
      await birdnet.close();
    }
  });
}
