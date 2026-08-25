import 'package:nature_sound_detective/core/community/community_models.dart';

enum ParkInterest {
  all('都可以'),
  birds('鸟鸣'),
  frogsAndInsects('蛙虫'),
  naturalSoundscape('流水风雨');

  const ParkInterest(this.label);
  final String label;
}

enum WalkPreference {
  relaxed('轻松步行'),
  fullRoute('完整路线'),
  accessible('无障碍优先');

  const WalkPreference(this.label);
  final String label;
}

class ParkGuidePreferences {
  const ParkGuidePreferences({
    this.childAge = 8,
    this.durationMinutes = 40,
    this.interest = ParkInterest.all,
    this.walkPreference = WalkPreference.relaxed,
  });

  final int childAge;
  final int durationMinutes;
  final ParkInterest interest;
  final WalkPreference walkPreference;

  ParkGuidePreferences copyWith({
    int? childAge,
    int? durationMinutes,
    ParkInterest? interest,
    WalkPreference? walkPreference,
  }) => ParkGuidePreferences(
    childAge: childAge ?? this.childAge,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    interest: interest ?? this.interest,
    walkPreference: walkPreference ?? this.walkPreference,
  );
}

class ParkGuideData {
  const ParkGuideData({
    required this.park,
    required this.sites,
    required this.routes,
    required this.snapshot,
    required this.brief,
  });

  final CommunityPark park;
  final List<CommunitySite> sites;
  final List<ExplorationRoute> routes;
  final EcologySnapshot snapshot;
  final DailyNatureBrief brief;
}

class ParkRecommendation {
  const ParkRecommendation({
    required this.data,
    required this.score,
    required this.reasons,
    required this.bestTime,
    required this.familyNote,
    required this.safetyNote,
    required this.communityEvidenceNote,
    required this.hasReliableCommunityEvidence,
  });

  final ParkGuideData data;
  final int score;
  final List<String> reasons;
  final String bestTime;
  final String familyNote;
  final String safetyNote;
  final String communityEvidenceNote;
  final bool hasReliableCommunityEvidence;

  String get displayScore {
    if (hasReliableCommunityEvidence) return '$score分';
    if (score >= 85) return '很适合';
    if (score >= 70) return '比较适合';
    return '可以尝试';
  }
}
