import 'dart:typed_data';

import 'package:nature_sound_detective/core/models/detection.dart';

class AudioInferenceInput {
  const AudioInferenceInput({
    required this.recordingId,
    required this.pcm16le,
    required this.sampleRate,
    required this.channelCount,
  }) : assert(sampleRate > 0),
       assert(channelCount > 0);

  final String recordingId;
  final Uint8List pcm16le;
  final int sampleRate;
  final int channelCount;
}

abstract interface class AudioDetector {
  String get modelId;

  String get modelVersion;

  int get requiredSampleRate;

  Future<List<SoundDetection>> detect(AudioInferenceInput input);
}

abstract interface class DetectionFusion {
  List<SoundDetection> fuse(Iterable<List<SoundDetection>> modelOutputs);
}
