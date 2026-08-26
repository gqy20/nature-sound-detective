import 'dart:math';

import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/park_guide/park_recommendation.dart';

class ParkRecommendationEngine {
  const ParkRecommendationEngine();

  List<ParkRecommendation> rank(
    List<ParkGuideData> values,
    ParkGuidePreferences preferences,
  ) {
    final results = values
        .map((value) => _score(value, preferences))
        .whereType<ParkRecommendation>()
        .toList(growable: false);
    return [...results]
      ..sort((left, right) => right.score.compareTo(left.score));
  }

  ParkRecommendation? _score(
    ParkGuideData data,
    ParkGuidePreferences preferences,
  ) {
    final accessible = _accessibleParkIds.contains(data.park.id);
    if (preferences.requiresAccessibleRoute && !accessible) return null;
    final eligibleRoutes = data.routes
        .where(
          (route) =>
              preferences.childAge >= route.ageMin &&
              route.durationMinutes <= preferences.durationMinutes,
        )
        .toList(growable: false);
    if (data.routes.isNotEmpty && eligibleRoutes.isEmpty) return null;
    final route = eligibleRoutes.isEmpty
        ? null
        : (eligibleRoutes.toList()..sort(
                (left, right) =>
                    (preferences.durationMinutes - left.durationMinutes).abs() -
                    (preferences.durationMinutes - right.durationMinutes).abs(),
              ))
              .first;
    var score = 30;
    final reasons = <String>[];
    if (route != null) {
      final ageGap = preferences.childAge - route.ageMin;
      score += max(8, 20 - ageGap * 2);
      reasons.add('适合${preferences.ageBand.label}儿童');
      final difference = (route.durationMinutes - preferences.durationMinutes)
          .abs();
      final durationScore = max(0, 20 - (difference / 2.5).round());
      score += durationScore;
      reasons.add('路线约${route.durationMinutes}分钟，符合本次时间');
    }
    if (preferences.requiresAccessibleRoute && accessible) {
      score += 5;
      reasons.add('现有试点信息标记为无障碍友好');
    }
    final interestScore = _interestScore(data, route, preferences.interest);
    score += interestScore;
    if (interestScore > 0) {
      reasons.add(
        preferences.interest == ParkInterest.all
            ? '适合综合自然声音探索'
            : '生境与“${preferences.interest.label}”探索方向匹配',
      );
    }
    final hasReliableCommunityEvidence =
        data.snapshot.dataSufficiency == 'medium' ||
        data.snapshot.dataSufficiency == 'high';
    if (hasReliableCommunityEvidence) {
      score += data.snapshot.dataSufficiency == 'high' ? 12 : 8;
    }
    final communityEvidenceNote = hasReliableCommunityEvidence
        ? '近期${data.snapshot.validPostCount}条有效社区声音记录已纳入排序。'
        : '近期数据不足，本次排序未使用动物活动趋势。';
    if (route != null) {
      score += switch (preferences.walkPreference) {
        WalkPreference.relaxed =>
          route.distanceKm <= 1.2
              ? 20
              : route.distanceKm <= 1.6
              ? 10
              : 0,
        WalkPreference.fullRoute =>
          route.distanceKm >= 1.8
              ? 20
              : route.distanceKm >= 1.5
              ? 10
              : 2,
      };
    }
    final matchNote = preferences.interest != ParkInterest.all
        ? interestScore >= 16
              ? '${preferences.interest.label}路线匹配'
              : '${preferences.interest.label}生境较匹配'
        : preferences.walkPreference == WalkPreference.relaxed
        ? '短程路线更适合轻松步行'
        : '路线长度更适合完整探索';
    final profile = _profiles[data.park.id] ?? _fallbackProfile;
    return ParkRecommendation(
      data: data,
      score: score.clamp(0, 100),
      reasons: reasons.take(3).toList(growable: false),
      bestTime: profile.bestTime,
      familyNote: profile.familyNote,
      safetyNote: profile.safetyNote,
      communityEvidenceNote: communityEvidenceNote,
      hasReliableCommunityEvidence: hasReliableCommunityEvidence,
      matchNote: matchNote,
    );
  }

  static int _interestScore(
    ParkGuideData data,
    ExplorationRoute? route,
    ParkInterest interest,
  ) {
    if (interest == ParkInterest.all) return 10;
    bool matches(String tag) => switch (interest) {
      ParkInterest.all => true,
      ParkInterest.birds =>
        tag.contains('鸟') || tag.contains('树冠') || tag.contains('林'),
      ParkInterest.frogsAndInsects =>
        tag.contains('蛙') || tag.contains('虫') || tag.contains('湿地'),
      ParkInterest.naturalSoundscape =>
        tag.contains('水') ||
            tag.contains('溪') ||
            tag.contains('湿地') ||
            tag.contains('雨'),
    };

    final routeMatches = route?.tags.where((tag) => matches(tag)).length ?? 0;
    if (routeMatches > 0) return min(22, 16 + routeMatches * 3);
    if (data.sites.any((site) => site.habitatTags.any(matches))) return 11;
    if (data.park.habitatTags.any(matches)) return 6;
    return 0;
  }

  static const _accessibleParkIds = {'taiziwan-park'};

  static const _fallbackProfile = _ParkProfile(
    bestTime: '建议选择较安静的清晨或傍晚',
    familyNote: '出发前请查看公园官方开放信息和家庭设施。',
    safetyNote: '留在公开步道，远距离倾听，不追逐或投喂动物。',
  );

  static const _profiles = <String, _ParkProfile>{
    'hangzhou-botanical-garden': _ParkProfile(
      bestTime: '清晨更适合比较树冠和灌木鸟鸣',
      familyNote: '林下路线约35分钟，可按孩子体力提前结束。',
      safetyNote: '林下湿滑时放慢速度，水生植物区只在外围步道观察。',
    ),
    'xixi-wetland': _ParkProfile(
      bestTime: '清晨或傍晚更适合倾听湿地边缘声景',
      familyNote: '完整路线约45分钟，建议8岁以上儿童参与。',
      safetyNote: '全程留在栈道，不靠近水边或进入芦苇区域。',
    ),
    'taiziwan-park': _ParkProfile(
      bestTime: '上午较早或傍晚适合比较草地、溪流和林缘声音',
      familyNote: '亲子短路线约25分钟，适合第一次尝试。',
      safetyNote: '溪流附近牵好低龄儿童，拥挤时避开持续人声再录音。',
    ),
  };
}

class _ParkProfile {
  const _ParkProfile({
    required this.bestTime,
    required this.familyNote,
    required this.safetyNote,
  });
  final String bestTime;
  final String familyNote;
  final String safetyNote;
}
