import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/wav_pcm_reader.dart';
import 'package:nature_sound_detective/core/inference/yamnet_detector.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

abstract interface class RecordingAnalyzer {
  Future<List<SoundDetection>> analyze(RecordedAudio recording);

  Future<void> dispose();
}

class YamnetRecordingAnalyzer implements RecordingAnalyzer {
  YamnetRecordingAnalyzer({this.reader = const WavPcmReader()});

  final WavPcmReader reader;
  Future<YamnetDetector>? _detector;

  @override
  Future<List<SoundDetection>> analyze(RecordedAudio recording) async {
    final detector = await (_detector ??= YamnetDetector.load());
    final input = await reader.read(
      recordingId: recording.id,
      path: recording.path,
    );
    return detector.detect(input);
  }

  @override
  Future<void> dispose() async {
    final detector = _detector;
    if (detector != null) (await detector).close();
  }
}
