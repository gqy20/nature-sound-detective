import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/models/exploration_feedback.dart';

class ExplorationRecord {
  const ExplorationRecord({
    required this.id,
    required this.createdAt,
    required this.location,
    required this.audioPath,
    required this.duration,
    required this.audioQuality,
    required this.detections,
    this.confirmedByUser = false,
    this.feedback,
  });

  factory ExplorationRecord.fromJson(Map<String, Object?> json) {
    final quality = json['audio_quality'];
    final detectionValues = json['detections'];
    return ExplorationRecord(
      id: json['id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      location: json['location'] as String? ?? '杭州',
      audioPath: json['audio_path'] as String? ?? '',
      duration: Duration(milliseconds: json['duration_ms'] as int? ?? 0),
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
      confirmedByUser: json['confirmed_by_user'] as bool? ?? false,
      feedback: switch (json['feedback']) {
        Map<Object?, Object?> value => ExplorationFeedback.fromJson(
          value.cast<String, Object?>(),
        ),
        _ => null,
      },
    );
  }

  final String id;
  final DateTime createdAt;
  final String location;
  final String audioPath;
  final Duration duration;
  final AudioQuality audioQuality;
  final List<SoundDetection> detections;
  final bool confirmedByUser;
  final ExplorationFeedback? feedback;

  ExplorationRecord copyWith({
    bool? confirmedByUser,
    ExplorationFeedback? feedback,
  }) {
    return ExplorationRecord(
      id: id,
      createdAt: createdAt,
      location: location,
      audioPath: audioPath,
      duration: duration,
      audioQuality: audioQuality,
      detections: detections,
      confirmedByUser: confirmedByUser ?? this.confirmedByUser,
      feedback: feedback ?? this.feedback,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'created_at': createdAt.toUtc().toIso8601String(),
    'location': location,
    'audio_path': audioPath,
    'duration_ms': duration.inMilliseconds,
    'audio_quality': audioQuality.toJson(),
    'detections': detections.map((item) => item.toJson()).toList(),
    'confirmed_by_user': confirmedByUser,
    if (feedback != null) 'feedback': feedback!.toJson(),
  };
}
