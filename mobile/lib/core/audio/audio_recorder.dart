enum AudioRecorderState { idle, recording }

class RecordingSession {
  const RecordingSession({required this.id, required this.startedAt});

  final String id;
  final DateTime startedAt;
}

class RecordedAudio {
  const RecordedAudio({
    required this.id,
    required this.path,
    required this.duration,
    required this.sampleRate,
    required this.channelCount,
    required this.byteLength,
  });

  factory RecordedAudio.fromMap(Map<Object?, Object?> value) {
    return RecordedAudio(
      id: value['id'] as String,
      path: value['path'] as String,
      duration: Duration(milliseconds: (value['duration_ms'] as num).round()),
      sampleRate: value['sample_rate'] as int,
      channelCount: value['channel_count'] as int,
      byteLength: value['byte_length'] as int,
    );
  }

  final String id;
  final String path;
  final Duration duration;
  final int sampleRate;
  final int channelCount;
  final int byteLength;
}

class RecordingLevel {
  const RecordingLevel({required this.rms, required this.peak, this.source});

  factory RecordingLevel.fromMap(Map<Object?, Object?> value) => RecordingLevel(
    rms: (value['rms'] as num?)?.toDouble() ?? 0,
    peak: (value['peak'] as num?)?.toDouble() ?? 0,
    source: value['source'] as String?,
  );

  final double rms;
  final double peak;
  final String? source;
}

abstract interface class AudioImporter {
  Future<RecordedAudio?> pickAudio();
}

abstract interface class RecordingLevelProvider {
  Future<RecordingLevel> getRecordingLevel();
}

abstract interface class AudioRecorder {
  Future<bool> hasPermission();

  Future<bool> requestPermission();

  Future<RecordingSession> start({Duration maxDuration});

  Future<RecordedAudio> stop();

  Future<void> cancel();
}
