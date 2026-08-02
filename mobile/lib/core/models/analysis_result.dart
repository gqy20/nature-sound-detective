import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

enum RecordingSource {
  mobile,
  web;

  static RecordingSource parse(Object? value) => switch (value) {
    'web' => web,
    _ => mobile,
  };
}

enum ClientPlatform {
  android,
  ios,
  web;

  static ClientPlatform parse(Object? value) => switch (value) {
    'ios' => ios,
    'web' => web,
    _ => android,
  };
}

class AnalysisResult {
  const AnalysisResult({
    required this.recordingId,
    required this.source,
    required this.platform,
    required this.audioQuality,
    required this.detections,
    this.contractVersion = currentContractVersion,
    this.unknown = false,
    this.requiresConfirmation = true,
    this.confirmedByUser = false,
  });

  factory AnalysisResult.fromJson(Map<String, Object?> json) {
    final quality = json['audio_quality'];
    final detectionValues = json['detections'];
    return AnalysisResult(
      recordingId: json['recording_id'] as String? ?? '',
      source: RecordingSource.parse(json['source']),
      platform: ClientPlatform.parse(json['platform']),
      contractVersion:
          json['contract_version'] as String? ?? currentContractVersion,
      audioQuality: quality is Map<Object?, Object?>
          ? AudioQuality.fromJson(quality.cast<String, Object?>())
          : const AudioQuality(usable: false),
      detections: detectionValues is List<Object?>
          ? detectionValues
                .whereType<Map<Object?, Object?>>()
                .map(
                  (value) =>
                      SoundDetection.fromJson(value.cast<String, Object?>()),
                )
                .toList(growable: false)
          : const [],
      unknown: json['unknown'] as bool? ?? false,
      requiresConfirmation: json['requires_confirmation'] as bool? ?? true,
      confirmedByUser: json['confirmed_by_user'] as bool? ?? false,
    );
  }

  static const currentContractVersion = '1.0';

  final String recordingId;
  final RecordingSource source;
  final ClientPlatform platform;
  final String contractVersion;
  final AudioQuality audioQuality;
  final List<SoundDetection> detections;
  final bool unknown;
  final bool requiresConfirmation;
  final bool confirmedByUser;

  Map<String, Object?> toJson() => {
    'recording_id': recordingId,
    'source': source.name,
    'platform': platform.name,
    'contract_version': contractVersion,
    'audio_quality': audioQuality.toJson(),
    'detections': detections.map((item) => item.toJson()).toList(),
    'unknown': unknown,
    'requires_confirmation': requiresConfirmation,
    'confirmed_by_user': confirmedByUser,
  };
}
