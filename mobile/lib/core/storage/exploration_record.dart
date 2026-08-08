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
    this.fieldChecks = const {},
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
      fieldChecks: switch (json['field_checks']) {
        Map<Object?, Object?> values => values.map(
          (key, value) => MapEntry(
            key.toString(),
            value is List<Object?>
                ? value.whereType<String>().toList(growable: false)
                : const <String>[],
          ),
        ),
        _ => const {},
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
  final Map<String, List<String>> fieldChecks;

  ExplorationRecord copyWith({
    bool? confirmedByUser,
    ExplorationFeedback? feedback,
    Map<String, List<String>>? fieldChecks,
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
      fieldChecks: fieldChecks ?? this.fieldChecks,
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
    if (fieldChecks.isNotEmpty) 'field_checks': fieldChecks,
  };
}
