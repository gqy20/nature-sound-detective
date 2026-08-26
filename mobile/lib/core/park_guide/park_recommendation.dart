import 'package:nature_sound_detective/core/community/community_models.dart';

enum ParkInterest {
  all('都可以'),
  birds('鸟鸣'),
  frogsAndInsects('蛙虫'),
  naturalSoundscape('流水风雨');

  const ParkInterest(this.label);
  final String label;
}

enum ChildAgeBand {
  fiveAndUnder('5岁及以下', 0, 5),
  sixToSeven('6–7岁', 6, 7),
  eightToNine('8–9岁', 8, 9),
  tenToEleven('10–11岁', 10, 11),
  twelveAndUp('12岁及以上', 12, null);

  const ChildAgeBand(this.label, this.minAge, this.maxAge);
  final String label;
  final int minAge;
  final int? maxAge;
}

enum VisitDuration {
  twentyMinutes('20分钟内', 20),
  fortyMinutes('20–40分钟', 40),
  sixtyMinutes('40–60分钟', 60),
  overAnHour('1小时以上', 120);

  const VisitDuration(this.label, this.maxMinutes);
  final String label;
  final int maxMinutes;
}

enum WalkPreference {
  relaxed('轻松步行'),
  fullRoute('完整路线');

  const WalkPreference(this.label);
  final String label;
}

class ParkGuidePreferences {
  const ParkGuidePreferences({
    this.ageBand = ChildAgeBand.eightToNine,
    this.visitDuration = VisitDuration.fortyMinutes,
    this.interest = ParkInterest.all,
    this.walkPreference = WalkPreference.relaxed,
    this.requiresAccessibleRoute = false,
  });

  final ChildAgeBand ageBand;
  final VisitDuration visitDuration;
  final ParkInterest interest;
  final WalkPreference walkPreference;
  final bool requiresAccessibleRoute;

  int get childAge => ageBand.minAge;
  int get durationMinutes => visitDuration.maxMinutes;

  ParkGuidePreferences copyWith({
    ChildAgeBand? ageBand,
    VisitDuration? visitDuration,
    ParkInterest? interest,
    WalkPreference? walkPreference,
    bool? requiresAccessibleRoute,
  }) => ParkGuidePreferences(
    ageBand: ageBand ?? this.ageBand,
    visitDuration: visitDuration ?? this.visitDuration,
    interest: interest ?? this.interest,
    walkPreference: walkPreference ?? this.walkPreference,
    requiresAccessibleRoute:
        requiresAccessibleRoute ?? this.requiresAccessibleRoute,
  );
}

class ParkGuideData {
  const ParkGuideData({
    required this.park,
    required this.sites,
    required this.routes,
    required this.snapshot,
    required this.brief,
    this.loadWarnings = const [],
  });

  final CommunityPark park;
  final List<CommunitySite> sites;
  final List<ExplorationRoute> routes;
  final EcologySnapshot snapshot;
  final DailyNatureBrief brief;
  final List<String> loadWarnings;
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
