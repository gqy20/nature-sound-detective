import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/park_guide/park_guide_availability.dart';
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
        ageBand: ChildAgeBand.sixToSeven,
        visitDuration: VisitDuration.fortyMinutes,
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

    final result = const ParkRecommendationEngine().rank(
      [park],
      const ParkGuidePreferences(
        ageBand: ChildAgeBand.sixToSeven,
        visitDuration: VisitDuration.fortyMinutes,
      ),
    ).single;

    expect(result.hasReliableCommunityEvidence, isFalse);
    expect(result.displayScore, isNot(contains('分')));
    expect(result.communityEvidenceNote, contains('未使用动物活动趋势'));
    expect(result.reasons, contains('适合综合自然声音探索'));
  });

  test('excludes routes outside the selected age band or time budget', () {
    final park = _data(
      id: 'xixi-wetland',
      name: '西溪湿地',
      tags: const ['湿地'],
      duration: 60,
      age: 8,
    );

    final tooYoung = const ParkRecommendationEngine().rank(
      [park],
      const ParkGuidePreferences(
        ageBand: ChildAgeBand.sixToSeven,
        visitDuration: VisitDuration.overAnHour,
      ),
    );
    final tooShort = const ParkRecommendationEngine().rank(
      [park],
      const ParkGuidePreferences(
        ageBand: ChildAgeBand.eightToNine,
        visitDuration: VisitDuration.fortyMinutes,
      ),
    );

    expect(tooYoung, isEmpty);
    expect(tooShort, isEmpty);
  });

  test('treats accessibility as a required condition', () {
    final inaccessible = _data(
      id: 'xixi-wetland',
      name: '西溪湿地',
      tags: const ['湿地'],
      duration: 45,
      age: 8,
    );
    final accessible = _data(
      id: 'taiziwan-park',
      name: '太子湾公园',
      tags: const ['草地'],
      duration: 25,
      age: 6,
    );

    final result = const ParkRecommendationEngine().rank([
      inaccessible,
      accessible,
    ], const ParkGuidePreferences(requiresAccessibleRoute: true));

    expect(result.single.data.park.id, 'taiziwan-park');
    expect(result.single.reasons, contains('现有试点信息标记为无障碍友好'));
  });

  test('changes ranking for interest and walking preference', () {
    final botanical = _data(
      id: 'hangzhou-botanical-garden',
      name: '杭州植物园',
      tags: const ['鸟类', '树冠'],
      duration: 35,
      distance: 1.6,
      age: 6,
    );
    final xixi = _data(
      id: 'xixi-wetland',
      name: '西溪湿地',
      tags: const ['蛙类', '水鸟'],
      duration: 45,
      distance: 2,
      age: 8,
    );
    final taiziwan = _data(
      id: 'taiziwan-park',
      name: '太子湾公园',
      tags: const ['草地', '鸣虫'],
      duration: 25,
      distance: 1.1,
      age: 6,
    );
    final values = [botanical, xixi, taiziwan];

    final birds = const ParkRecommendationEngine().rank(
      values,
      const ParkGuidePreferences(
        visitDuration: VisitDuration.sixtyMinutes,
        interest: ParkInterest.birds,
        walkPreference: WalkPreference.relaxed,
      ),
    );
    final frogsAndFullRoute = const ParkRecommendationEngine().rank(
      values,
      const ParkGuidePreferences(
        visitDuration: VisitDuration.sixtyMinutes,
        interest: ParkInterest.frogsAndInsects,
        walkPreference: WalkPreference.fullRoute,
      ),
    );
    final relaxed = const ParkRecommendationEngine().rank(
      values,
      const ParkGuidePreferences(
        visitDuration: VisitDuration.sixtyMinutes,
        walkPreference: WalkPreference.relaxed,
      ),
    );

    expect(birds.first.data.park.id, 'hangzhou-botanical-garden');
    expect(birds.first.matchNote, contains('鸟鸣'));
    expect(frogsAndFullRoute.first.data.park.id, 'xixi-wetland');
    expect(frogsAndFullRoute.first.matchNote, contains('蛙虫'));
    expect(relaxed.first.data.park.id, 'taiziwan-park');
  });

  test('keeps every current preference combination usable', () {
    final configured = const ParkGuideAvailability().ensureBaselineRoute(
      _data(
        id: 'taiziwan-park',
        name: '太子湾公园',
        tags: const ['城市公园', '草地', '水岸'],
        duration: 25,
        age: 6,
      ),
    );

    for (final ageBand in ChildAgeBand.values) {
      for (final visitDuration in VisitDuration.values) {
        for (final interest in ParkInterest.values) {
          for (final walkPreference in WalkPreference.values) {
            for (final requiresAccessibleRoute in [false, true]) {
              final preferences = ParkGuidePreferences(
                ageBand: ageBand,
                visitDuration: visitDuration,
                interest: interest,
                walkPreference: walkPreference,
                requiresAccessibleRoute: requiresAccessibleRoute,
              );
              final result = const ParkRecommendationEngine().rank(
                [configured],
                preferences,
                preferredParkId: 'taiziwan-park',
              );
              expect(
                result,
                isNotEmpty,
                reason: '应覆盖 ${preferences.signature}',
              );
            }
          }
        }
      }
    }
    final baseline = configured.routes.singleWhere(
      (route) => route.id.endsWith('family-baseline'),
    );
    expect(baseline.ageMin, 0);
    expect(baseline.durationMinutes, lessThanOrEqualTo(20));
    expect(baseline.disclaimer, contains('家长全程陪同'));
    expect(baseline.stops.single.mission, contains('家长全程陪同'));
  });
}

ParkGuideData _data({
  required String id,
  required String name,
  required List<String> tags,
  required int duration,
  required int age,
  double distance = 1,
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
      distanceKm: distance,
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
