import 'dart:math';

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
      score += 20;
      reasons.add('适合${preferences.ageBand.label}儿童');
      final difference = (route.durationMinutes - preferences.durationMinutes)
          .abs();
      final durationScore = max(0, 20 - (difference / 3).round());
      score += durationScore;
      reasons.add('路线约${route.durationMinutes}分钟，符合本次时间');
    }
    if (preferences.requiresAccessibleRoute && accessible) {
      score += 5;
      reasons.add('现有试点信息标记为无障碍友好');
    }
    final allTags = {
      ...data.park.habitatTags,
      ...data.sites.expand((site) => site.habitatTags),
      ...data.routes.expand((route) => route.tags),
    };
    final interestMatches = switch (preferences.interest) {
      ParkInterest.all => true,
      ParkInterest.birds => allTags.any(
        (tag) => tag.contains('鸟') || tag.contains('树冠') || tag.contains('林'),
      ),
      ParkInterest.frogsAndInsects => allTags.any(
        (tag) =>
            tag.contains('蛙') ||
            tag.contains('虫') ||
            tag.contains('湿地') ||
            tag.contains('草'),
      ),
      ParkInterest.naturalSoundscape => allTags.any(
        (tag) => tag.contains('水') || tag.contains('溪') || tag.contains('湿地'),
      ),
    };
    if (interestMatches) {
      score += 18;
      reasons.add('生境与“${preferences.interest.label}”探索方向匹配');
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
    if (preferences.walkPreference == WalkPreference.fullRoute &&
        route != null) {
      score += 5;
    }
    if (preferences.walkPreference == WalkPreference.relaxed &&
        (route?.distanceKm ?? 9) <= 1.6) {
      score += 5;
    }
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
    );
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
