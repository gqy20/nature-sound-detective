import 'package:nature_sound_detective/core/storage/exploration_record.dart';

class SoundscapeArea {
  const SoundscapeArea({
    required this.id,
    required this.name,
    required this.postCount,
    required this.waitingCount,
    required this.soundTypes,
  });

  factory SoundscapeArea.fromJson(Map<String, Object?> json) => SoundscapeArea(
    id: json['area_id'] as String? ?? '',
    name: json['area_name'] as String? ?? '',
    postCount: json['post_count'] as int? ?? 0,
    waitingCount: json['waiting_count'] as int? ?? 0,
    soundTypes: switch (json['sound_types']) {
      final List<Object?> values => values.whereType<String>().toList(),
      _ => const [],
    },
  );

  final String id;
  final String name;
  final int postCount;
  final int waitingCount;
  final List<String> soundTypes;
}

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.alias,
    required this.areaId,
    required this.areaName,
    required this.subject,
    required this.soundType,
    required this.observedAt,
    required this.createdAt,
    required this.audioUrl,
    required this.duration,
    required this.candidateNames,
    required this.fieldObservations,
    required this.status,
    required this.reviewStatus,
    required this.responseCount,
    required this.responseSummary,
    required this.ownedByRequester,
  });

  factory CommunityPost.fromJson(Map<String, Object?> json) => CommunityPost(
    id: json['id'] as String? ?? '',
    alias: json['alias'] as String? ?? '匿名探员',
    areaId: json['area_id'] as String? ?? '',
    areaName: json['area_name'] as String? ?? '杭州',
    subject: json['subject'] as String? ?? '自然声音线索',
    soundType: json['sound_type'] as String? ?? '自然声音',
    observedAt:
        DateTime.tryParse(json['observed_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    audioUrl: json['audio_url'] as String? ?? '',
    duration: Duration(milliseconds: json['duration_ms'] as int? ?? 0),
    candidateNames: switch (json['candidate_names']) {
      final List<Object?> values => values.whereType<String>().toList(),
      _ => const [],
    },
    fieldObservations: switch (json['field_observations']) {
      final List<Object?> values => values.whereType<String>().toList(),
      _ => const [],
    },
    status: json['status'] as String? ?? 'published_unverified',
    reviewStatus: json['review_status'] as String? ?? 'not_requested',
    responseCount: json['response_count'] as int? ?? 0,
    responseSummary: switch (json['response_summary']) {
      final Map<Object?, Object?> values => values.map(
        (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
      ),
      _ => const {},
    },
    ownedByRequester: json['owned_by_requester'] as bool? ?? false,
  );

  final String id;
  final String alias;
  final String areaId;
  final String areaName;
  final String subject;
  final String soundType;
  final DateTime observedAt;
  final DateTime createdAt;
  final String audioUrl;
  final Duration duration;
  final List<String> candidateNames;
  final List<String> fieldObservations;
  final String status;
  final String reviewStatus;
  final int responseCount;
  final Map<String, int> responseSummary;
  final bool ownedByRequester;
}

class PublicationConsent {
  const PublicationConsent({
    required this.areaId,
    required this.areaName,
    required this.adultConfirmed,
    required this.publicConsent,
    required this.reviewConsent,
  });

  final String areaId;
  final String areaName;
  final bool adultConfirmed;
  final bool publicConsent;
  final bool reviewConsent;
}

class PublicationRequest {
  const PublicationRequest({required this.record, required this.consent});

  final ExplorationRecord record;
  final PublicationConsent consent;
}
