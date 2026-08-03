enum FeedbackDecision { correct, wrong, uncertain }

class ExplorationFeedback {
  const ExplorationFeedback({
    required this.decision,
    this.correctedTaxonId,
    this.consentToRetainAudio = false,
    this.reviewStatus = 'user_reported',
  });

  factory ExplorationFeedback.fromJson(Map<String, Object?> json) {
    final decision = FeedbackDecision.values.where(
      (item) => item.name == json['decision'],
    );
    return ExplorationFeedback(
      decision: decision.firstOrNull ?? FeedbackDecision.uncertain,
      correctedTaxonId: json['corrected_taxon_id'] as String?,
      consentToRetainAudio: json['consent_to_retain_audio'] as bool? ?? false,
      reviewStatus: json['review_status'] as String? ?? 'user_reported',
    );
  }

  final FeedbackDecision decision;
  final String? correctedTaxonId;
  final bool consentToRetainAudio;
  final String reviewStatus;

  Map<String, Object?> toJson() => {
    'decision': decision.name,
    if (correctedTaxonId != null) 'corrected_taxon_id': correctedTaxonId,
    'consent_to_retain_audio': consentToRetainAudio,
    'review_status': reviewStatus,
  };
}
