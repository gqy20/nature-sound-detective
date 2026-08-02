import 'dart:typed_data';

import 'package:nature_sound_detective/core/inference/audio_inference.dart';

class PcmResampler {
  const PcmResampler._();

  static Float32List toMonoFloat32(
    AudioInferenceInput input, {
    required int outputSampleRate,
  }) {
    if (input.pcm16le.lengthInBytes.isOdd) {
      throw const FormatException('PCM 16-bit 数据长度必须是偶数。');
    }
    final allSamples = input.pcm16le.lengthInBytes ~/ 2;
    final frameCount = allSamples ~/ input.channelCount;
    if (frameCount == 0) return Float32List(0);
    final bytes = ByteData.sublistView(input.pcm16le);
    final mono = Float32List(frameCount);
    for (var frame = 0; frame < frameCount; frame++) {
      var sum = 0.0;
      for (var channel = 0; channel < input.channelCount; channel++) {
        final index = frame * input.channelCount + channel;
        sum += bytes.getInt16(index * 2, Endian.little) / 32768.0;
      }
      mono[frame] = sum / input.channelCount;
    }
    if (input.sampleRate == outputSampleRate) return mono;

    final outputLength = (frameCount * outputSampleRate / input.sampleRate)
        .round();
    final output = Float32List(outputLength);
    final sourceStep = input.sampleRate / outputSampleRate;
    for (var index = 0; index < outputLength; index++) {
      final sourcePosition = index * sourceStep;
      final left = sourcePosition.floor().clamp(0, frameCount - 1);
      final right = (left + 1).clamp(0, frameCount - 1);
      final fraction = sourcePosition - left;
      output[index] = mono[left] * (1 - fraction) + mono[right] * fraction;
    }
    return output;
  }
}
