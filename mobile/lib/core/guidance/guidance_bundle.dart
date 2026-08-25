enum ExplorationBehavior {
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
}

class GuidanceBundle {
  const GuidanceBundle({required this.guides, required this.praiseSuggestions});

  final List<ParentGuide> guides;
  final List<PraiseSuggestion> praiseSuggestions;
}
