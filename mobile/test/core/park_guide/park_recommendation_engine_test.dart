import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/park_guide/park_recommendation.dart';
import 'package:nature_sound_detective/core/park_guide/park_recommendation_engine.dart';

void main() {
  test('ranks a short matching route above a long route', () {
    final short = _data(
      id: 'taiziwan-park',
      name: '太子湾公园',
      tags: const ['草地', '鸣虫'],
      duration: 25,
      age: 6,
    );
    final long = _data(
      id: 'xixi-wetland',
      name: '西溪湿地',
      tags: const ['湿地', '蛙类'],
      duration: 60,
      age: 8,
    );

    final result = const ParkRecommendationEngine().rank(
      [long, short],
      const ParkGuidePreferences(
        childAge: 6,
        durationMinutes: 20,
        interest: ParkInterest.frogsAndInsects,
      ),
    );

    expect(result.first.data.park.id, 'taiziwan-park');
    expect(result.first.reasons, isNotEmpty);
    expect(result.first.hasReliableCommunityEvidence, isTrue);
    expect(result.first.displayScore, endsWith('分'));
  });

  test('uses an honest fit label when community data is insufficient', () {
    final park = _data(
      id: 'taiziwan-park',
      name: '太子湾公园',
      tags: const ['草地', '鸣虫'],
      duration: 25,
      age: 6,
      dataSufficiency: 'low',
      validPostCount: 0,
    );

    final result = const ParkRecommendationEngine().rank([
      park,
    ], const ParkGuidePreferences(childAge: 6, durationMinutes: 20)).single;

    expect(result.hasReliableCommunityEvidence, isFalse);
    expect(result.displayScore, isNot(contains('分')));
    expect(result.communityEvidenceNote, contains('未使用动物活动趋势'));
  });
}

ParkGuideData _data({
  required String id,
  required String name,
  required List<String> tags,
  required int duration,
  required int age,
  String dataSufficiency = 'medium',
  int validPostCount = 2,
}) => ParkGuideData(
  park: CommunityPark(
    id: id,
    name: name,
    areaId: 'xihu',
    areaName: '西湖区',
    habitatTags: tags,
    zoneCount: 1,
  ),
  sites: [
    CommunitySite(
      id: '$id:zone',
      parkId: id,
      parkName: name,
      zoneId: 'zone',
      zoneName: '测试区域',
      habitatTags: tags,
    ),
  ],
  routes: [
    ExplorationRoute(
      id: '$id-route',
      parkId: id,
      name: '测试路线',
      durationMinutes: duration,
      distanceKm: 1,
      ageMin: age,
      tags: tags,
      stops: [
        ExplorationRouteStop(siteId: '$id:zone', minutes: 5, mission: '安静倾听'),
      ],
      disclaimer: '不保证一定遇见动物',
    ),
  ],
  snapshot: EcologySnapshot(
    parkId: id,
    validPostCount: validPostCount,
    independentObserverCount: 2,
    soundTypeCounts: const {'鸣虫': 2},
    dataSufficiency: dataSufficiency,
    disclaimer: '不代表动物数量',
  ),
  brief: DailyNatureBrief(
    parkId: id,
    parkName: name,
    headline: '测试简报',
    summary: '测试',
    facts: const [],
    possibleExplanations: const [],
    mission: '倾听',
    dataSufficiency: 'medium',
    disclaimer: '不代表动物数量',
  ),
);
