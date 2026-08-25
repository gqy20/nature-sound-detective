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
    this.parkId,
    this.zoneId,
    this.siteId,
    this.samplingMode = 'opportunistic',
    this.ecologyEligible = false,
    this.isDemo = false,
    this.mediaAssets = const [],
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
    parkId: json['park_id'] as String?,
    zoneId: json['zone_id'] as String?,
    siteId: json['site_id'] as String?,
    samplingMode: json['sampling_mode'] as String? ?? 'opportunistic',
    ecologyEligible: json['ecology_eligible'] as bool? ?? false,
    isDemo: json['is_demo'] as bool? ?? false,
    mediaAssets: switch (json['media_assets']) {
      final List<Object?> values => values
          .whereType<Map<Object?, Object?>>()
          .map((value) => CommunityMediaAsset.fromJson(value.cast<String, Object?>()))
          .toList(growable: false),
      _ => const [],
    },
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
  final String? parkId;
  final String? zoneId;
  final String? siteId;
  final String samplingMode;
  final bool ecologyEligible;
  final bool isDemo;
  final List<CommunityMediaAsset> mediaAssets;
}

class CommunityMediaAsset {
  const CommunityMediaAsset({
    required this.id,
    required this.mediaType,
    required this.sourceType,
    required this.url,
    this.thumbnailUrl,
    this.provider,
    this.model,
  });
  factory CommunityMediaAsset.fromJson(Map<String, Object?> json) => CommunityMediaAsset(
    id: json['id'] as String? ?? '',
    mediaType: json['media_type'] as String? ?? 'image',
    sourceType: json['source_type'] as String? ?? 'ai_generated',
    url: json['url'] as String? ?? '',
    thumbnailUrl: json['thumbnail_url'] as String?,
    provider: json['provider'] as String?,
    model: json['model'] as String?,
  );
  final String id;
  final String mediaType;
  final String sourceType;
  final String url;
  final String? thumbnailUrl;
  final String? provider;
  final String? model;
}

class CommunityPark {
  const CommunityPark({
    required this.id,
    required this.name,
    required this.areaId,
    required this.areaName,
    required this.habitatTags,
    required this.zoneCount,
  });
  factory CommunityPark.fromJson(Map<String, Object?> json) => CommunityPark(
    id: json['park_id'] as String? ?? '',
    name: json['park_name'] as String? ?? '',
    areaId: json['area_id'] as String? ?? '',
    areaName: json['area_name'] as String? ?? '',
    habitatTags: (json['habitat_tags'] as List<Object?>? ?? const []).whereType<String>().toList(),
    zoneCount: json['zone_count'] as int? ?? 0,
  );
  final String id;
  final String name;
  final String areaId;
  final String areaName;
  final List<String> habitatTags;
  final int zoneCount;
}

class CommunitySite {
  const CommunitySite({
    required this.id,
    required this.parkId,
    required this.parkName,
    required this.zoneId,
    required this.zoneName,
    required this.habitatTags,
  });
  factory CommunitySite.fromJson(Map<String, Object?> json) => CommunitySite(
    id: json['id'] as String? ?? '',
    parkId: json['park_id'] as String? ?? '',
    parkName: json['park_name'] as String? ?? '',
    zoneId: json['zone_id'] as String? ?? '',
    zoneName: json['zone_name'] as String? ?? '',
    habitatTags: (json['habitat_tags'] as List<Object?>? ?? const []).whereType<String>().toList(),
  );
  final String id;
  final String parkId;
  final String parkName;
  final String zoneId;
  final String zoneName;
  final List<String> habitatTags;
}

class EcologySnapshot {
  const EcologySnapshot({
    required this.parkId,
    required this.validPostCount,
    required this.independentObserverCount,
    required this.soundTypeCounts,
    required this.dataSufficiency,
    required this.disclaimer,
    this.observationDayCount = 0,
    this.samplingModeCounts = const {},
    this.previousValidPostCount = 0,
    this.activityTrend = 'insufficient',
    this.zoneSummaries = const [],
  });
  factory EcologySnapshot.fromJson(Map<String, Object?> json) => EcologySnapshot(
    parkId: json['park_id'] as String? ?? '',
    validPostCount: json['valid_post_count'] as int? ?? 0,
    independentObserverCount: json['independent_observer_count'] as int? ?? 0,
    soundTypeCounts: (json['sound_type_counts'] as Map<Object?, Object?>? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), (value as num).toInt()),
    ),
    dataSufficiency: json['data_sufficiency'] as String? ?? 'low',
    disclaimer: json['disclaimer'] as String? ?? '',
    observationDayCount: json['observation_day_count'] as int? ?? 0,
    samplingModeCounts:
        (json['sampling_mode_counts'] as Map<Object?, Object?>? ?? const {}).map(
          (key, value) => MapEntry(key.toString(), (value as num).toInt()),
        ),
    previousValidPostCount: json['previous_valid_post_count'] as int? ?? 0,
    activityTrend: json['activity_trend'] as String? ?? 'insufficient',
    zoneSummaries: (json['zone_summaries'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(
          (value) => ZoneSoundscapeSummary.fromJson(
            value.cast<String, Object?>(),
          ),
        )
        .toList(growable: false),
  );
  final String parkId;
  final int validPostCount;
  final int independentObserverCount;
  final Map<String, int> soundTypeCounts;
  final String dataSufficiency;
  final String disclaimer;
  final int observationDayCount;
  final Map<String, int> samplingModeCounts;
  final int previousValidPostCount;
  final String activityTrend;
  final List<ZoneSoundscapeSummary> zoneSummaries;
}

class ZoneSoundscapeSummary {
  const ZoneSoundscapeSummary({
    required this.zoneId,
    required this.zoneName,
    required this.validPostCount,
    required this.independentObserverCount,
    required this.soundTypeCounts,
    required this.dataSufficiency,
  });

  factory ZoneSoundscapeSummary.fromJson(Map<String, Object?> json) =>
      ZoneSoundscapeSummary(
        zoneId: json['zone_id'] as String? ?? '',
        zoneName: json['zone_name'] as String? ?? '',
        validPostCount: json['valid_post_count'] as int? ?? 0,
        independentObserverCount:
            json['independent_observer_count'] as int? ?? 0,
        soundTypeCounts:
            (json['sound_type_counts'] as Map<Object?, Object?>? ?? const {}).map(
              (key, value) => MapEntry(key.toString(), (value as num).toInt()),
            ),
        dataSufficiency: json['data_sufficiency'] as String? ?? 'low',
      );

  final String zoneId;
  final String zoneName;
  final int validPostCount;
  final int independentObserverCount;
  final Map<String, int> soundTypeCounts;
  final String dataSufficiency;
}

class DailyNatureBrief {
  const DailyNatureBrief({
    required this.parkId,
    required this.parkName,
    required this.headline,
    required this.summary,
    required this.facts,
    required this.possibleExplanations,
    required this.mission,
    required this.dataSufficiency,
    required this.disclaimer,
  });
  factory DailyNatureBrief.fromJson(Map<String, Object?> json) => DailyNatureBrief(
    parkId: json['park_id'] as String? ?? '',
    parkName: json['park_name'] as String? ?? '',
    headline: json['headline'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    facts: (json['facts'] as List<Object?>? ?? const []).whereType<String>().toList(),
    possibleExplanations: (json['possible_explanations'] as List<Object?>? ?? const []).whereType<String>().toList(),
    mission: json['mission'] as String? ?? '',
    dataSufficiency: json['data_sufficiency'] as String? ?? 'low',
    disclaimer: json['disclaimer'] as String? ?? '',
  );
  final String parkId;
  final String parkName;
  final String headline;
  final String summary;
  final List<String> facts;
  final List<String> possibleExplanations;
  final String mission;
  final String dataSufficiency;
  final String disclaimer;
}

class ExplorationRouteStop {
  const ExplorationRouteStop({
    required this.siteId,
    required this.minutes,
    required this.mission,
  });

  factory ExplorationRouteStop.fromJson(Map<String, Object?> json) =>
      ExplorationRouteStop(
        siteId: json['site_id'] as String? ?? '',
        minutes: (json['minutes'] as num?)?.toInt() ?? 0,
        mission: json['mission'] as String? ?? '',
      );

  final String siteId;
  final int minutes;
  final String mission;
}

class ExplorationRoute {
  const ExplorationRoute({
    required this.id,
    required this.parkId,
    required this.name,
    required this.durationMinutes,
    required this.distanceKm,
    required this.ageMin,
    required this.tags,
    required this.stops,
    required this.disclaimer,
  });

  factory ExplorationRoute.fromJson(Map<String, Object?> json) =>
      ExplorationRoute(
        id: json['id'] as String? ?? '',
        parkId: json['park_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
        distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
        ageMin: (json['age_min'] as num?)?.toInt() ?? 0,
        tags: (json['tags'] as List<Object?>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        stops: (json['stops'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map(
              (value) => ExplorationRouteStop.fromJson(
                value.cast<String, Object?>(),
              ),
            )
            .toList(growable: false),
        disclaimer: json['disclaimer'] as String? ?? '',
      );

  final String id;
  final String parkId;
  final String name;
  final int durationMinutes;
  final double distanceKm;
  final int ageMin;
  final List<String> tags;
  final List<ExplorationRouteStop> stops;
  final String disclaimer;
}

class PublicationConsent {
  const PublicationConsent({
    required this.areaId,
    required this.areaName,
    required this.adultConfirmed,
    required this.publicConsent,
    required this.reviewConsent,
    this.parkId,
    this.zoneId,
    this.siteId,
  });

  final String areaId;
  final String areaName;
  final bool adultConfirmed;
  final bool publicConsent;
  final bool reviewConsent;
  final String? parkId;
  final String? zoneId;
  final String? siteId;
}

class PublicationRequest {
  const PublicationRequest({required this.record, required this.consent});

  final ExplorationRecord record;
  final PublicationConsent consent;
}
