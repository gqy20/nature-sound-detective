import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/wav_pcm_reader.dart';
import 'package:nature_sound_detective/core/fusion/nature_detection_fusion.dart';
import 'package:nature_sound_detective/core/inference/birdnet_detector.dart';
import 'package:nature_sound_detective/core/inference/yamnet_detector.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

abstract interface class RecordingAnalyzer {
  Future<List<SoundDetection>> analyze(RecordedAudio recording);

  Future<void> dispose();
}

class LocalRecordingAnalyzer implements RecordingAnalyzer {
  LocalRecordingAnalyzer({
    this.reader = const WavPcmReader(),
    this.fusion = const NatureDetectionFusion(),
  });

  final WavPcmReader reader;
  final NatureDetectionFusion fusion;
  Future<YamnetDetector>? _detector;
  Future<BirdnetDetector>? _birdDetector;

  @override
  Future<List<SoundDetection>> analyze(RecordedAudio recording) async {
    final total = Stopwatch()..start();
    AppLog.info('inference', 'analysis_started', traceId: recording.id);
    final input = await reader.read(
      recordingId: recording.id,
      path: recording.path,
    );
    final yamnet = await (_detector ??= YamnetDetector.load());
    final birdnet = await (_birdDetector ??= BirdnetDetector.load());
    final yamnetDetections = await yamnet.detect(input);
    final birdnetDetections = await birdnet.detect(input);
    final fused = fusion.fuse([yamnetDetections, birdnetDetections]);
    total.stop();
    AppLog.info(
      'inference',
      'analysis_completed',
      traceId: recording.id,
      fields: {
        'duration_ms': total.elapsedMilliseconds,
        'yamnet_candidates': yamnetDetections.length,
        'birdnet_candidates': birdnetDetections.length,
        'fused_candidates': fused.length,
      },
    );
    return fused;
  }

  @override
  Future<void> dispose() async {
    final detector = _detector;
    if (detector != null) await (await detector).close();
    final birdDetector = _birdDetector;
    if (birdDetector != null) await (await birdDetector).close();
  }
}
