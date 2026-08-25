enum ExplorationBehavior {
  capturedSound,
  importedSound,
  recordedSound,
  replayedAudio,
  completedObservation,
  comparedEvidence,
  acceptedUncertainty,
  retriedRecording,
  observedSafely,
}

class ParentGuide {
  const ParentGuide({
    required this.goal,
    required this.say,
    required this.action,
    required this.avoid,
  });

  final String goal;
  final String say;
  final String action;
  final String avoid;

  factory ParentGuide.fromJson(Map<String, Object?> json) => ParentGuide(
    goal: json['goal'] as String? ?? '',
    say: json['say'] as String? ?? '',
    action: json['action'] as String? ?? '',
    avoid: json['avoid'] as String? ?? '',
  );
}

class PraiseSuggestion {
  const PraiseSuggestion({
    required this.behavior,
    required this.ability,
    required this.text,
  });

  final ExplorationBehavior behavior;
  final String ability;
  final String text;

  factory PraiseSuggestion.fromJson(Map<String, Object?> json) =>
      PraiseSuggestion(
        behavior: ExplorationBehavior.values.firstWhere(
          (value) => value.name == json['evidence_behavior'],
          orElse: () => ExplorationBehavior.recordedSound,
        ),
        ability: json['ability'] as String? ?? '',
        text: json['text'] as String? ?? '',
      );
}

class GuidanceBundle {
  const GuidanceBundle({
    required this.guides,
    required this.praiseSuggestions,
    this.provider = 'reviewed-template',
    this.aiGenerated = false,
    this.warning = '',
    this.quotaLimit,
    this.quotaRemaining,
    this.cached = false,
  });

  final List<ParentGuide> guides;
  final List<PraiseSuggestion> praiseSuggestions;
  final String provider;
  final bool aiGenerated;
  final String warning;
  final int? quotaLimit;
  final int? quotaRemaining;
  final bool cached;

  factory GuidanceBundle.fromJson(Map<String, Object?> json) {
    final quota = switch (json['quota']) {
      Map<Object?, Object?> value => value.cast<String, Object?>(),
      _ => const <String, Object?>{},
    };
    return GuidanceBundle(
      guides: (json['guides'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((value) => ParentGuide.fromJson(value.cast<String, Object?>()))
          .toList(growable: false),
      praiseSuggestions: (json['praises'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(
            (value) => PraiseSuggestion.fromJson(value.cast<String, Object?>()),
          )
          .toList(growable: false),
      provider: json['provider'] as String? ?? 'unknown',
      aiGenerated: json['ai_generated'] as bool? ?? false,
      warning: json['warning'] as String? ?? '',
      quotaLimit: (quota['limit'] as num?)?.toInt(),
      quotaRemaining: (quota['remaining'] as num?)?.toInt(),
      cached: json['cached'] as bool? ?? false,
    );
  }
}
