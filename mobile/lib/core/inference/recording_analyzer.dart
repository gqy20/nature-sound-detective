import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/wav_pcm_reader.dart';
import 'package:nature_sound_detective/core/inference/birdnet_detector.dart';
import 'package:nature_sound_detective/core/inference/yamnet_detector.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

abstract interface class RecordingAnalyzer {
  Future<List<SoundDetection>> analyze(RecordedAudio recording);

  Future<void> dispose();
}

class LocalRecordingAnalyzer implements RecordingAnalyzer {
  LocalRecordingAnalyzer({this.reader = const WavPcmReader()});

  final WavPcmReader reader;
  Future<YamnetDetector>? _detector;
  Future<BirdnetDetector>? _birdDetector;

  @override
  Future<List<SoundDetection>> analyze(RecordedAudio recording) async {
    final input = await reader.read(
      recordingId: recording.id,
      path: recording.path,
    );
    final yamnet = await (_detector ??= YamnetDetector.load());
    final birdnet = await (_birdDetector ??= BirdnetDetector.load());
    final yamnetDetections = await yamnet.detect(input);
    final birdnetDetections = await birdnet.detect(input);
    return [...yamnetDetections, ...birdnetDetections];
  }

  @override
  Future<void> dispose() async {
    final detector = _detector;
    if (detector != null) (await detector).close();
    final birdDetector = _birdDetector;
    if (birdDetector != null) (await birdDetector).close();
  }
}
