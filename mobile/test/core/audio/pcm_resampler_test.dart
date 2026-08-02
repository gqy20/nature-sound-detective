import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/audio/pcm_resampler.dart';
import 'package:nature_sound_detective/core/inference/audio_inference.dart';

void main() {
  test('downmixes stereo PCM and resamples it', () {
    final samples = Int16List.fromList([
      32767,
      32767,
      0,
      0,
      -32768,
      -32768,
      0,
      0,
    ]);
    final input = AudioInferenceInput(
      recordingId: 'rec_1',
      pcm16le: samples.buffer.asUint8List(),
      sampleRate: 4,
      channelCount: 2,
    );

    final output = PcmResampler.toMonoFloat32(input, outputSampleRate: 2);

    expect(output, hasLength(2));
    expect(output.first, closeTo(1, 0.001));
    expect(output.last, closeTo(-1, 0.001));
  });
}
