import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/community/route_progress_store.dart';
import 'package:nature_sound_detective/features/park_guide/park_guide_page.dart';

void main() {
  testWidgets('filters parks and opens a parent-guided route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ParkGuidePage(
          service: _FakeCommunityService(),
          routeProgressStore: _MemoryRouteProgressStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今天去哪听？'), findsOneWidget);
    expect(find.text('太子湾公园'), findsOneWidget);
    expect(find.textContaining('不代表动物数量'), findsOneWidget);

    await tester.tap(find.text('20分钟'));
    await tester.pumpAndSettle();
    final recommendation = find.byKey(
      const Key('park-recommendation-taiziwan-park'),
    );
    await tester.ensureVisible(recommendation);
    await tester.pumpAndSettle();
    await tester.tap(recommendation);
    await tester.pumpAndSettle();

    expect(find.text('适合停下来听的区域'), findsOneWidget);
    expect(find.text('中心草地区'), findsOneWidget);
    await tester.tap(find.byKey(const Key('park-route-family-short')));
    await tester.pumpAndSettle();

    expect(find.textContaining('儿童任务：'), findsOneWidget);
    expect(find.textContaining('家长引导：'), findsOneWidget);
    expect(
      find.byKey(const Key('route-listen-taiziwan-park:main-lawn')),
      findsOneWidget,
    );
  });
}

class _FakeCommunityService implements CommunityService {
  static const park = CommunityPark(
    id: 'taiziwan-park',
    name: '太子湾公园',
    areaId: 'xihu',
    areaName: '西湖区',
    habitatTags: ['城市公园', '草地', '水岸'],
    zoneCount: 1,
  );

  @override
  Future<List<CommunityPark>> listParks() async => const [park];

  @override
  Future<List<CommunitySite>> listSites({String? parkId}) async => const [
    CommunitySite(
      id: 'taiziwan-park:main-lawn',
      parkId: 'taiziwan-park',
      parkName: '太子湾公园',
      zoneId: 'main-lawn',
      zoneName: '中心草地区',
      habitatTags: ['草地', '开阔地'],
    ),
  ];

  @override
  Future<List<ExplorationRoute>> listRoutes(String parkId) async => const [
    ExplorationRoute(
      id: 'family-short',
      parkId: 'taiziwan-park',
      name: '城市公园亲子短路线',
      durationMinutes: 25,
      distanceKm: 1.1,
      ageMin: 6,
      tags: ['短路线', '草地', '鸣虫'],
      stops: [
        ExplorationRouteStop(
          siteId: 'taiziwan-park:main-lawn',
          minutes: 5,
          mission: '听听开阔草地里有几种不同节奏。',
        ),
      ],
      disclaimer: '不保证一定遇见动物',
    ),
  ];

  @override
  Future<EcologySnapshot> ecologySnapshot(String parkId) async =>
      const EcologySnapshot(
        parkId: 'taiziwan-park',
        validPostCount: 2,
        independentObserverCount: 2,
        soundTypeCounts: {'鸣虫': 2},
        dataSufficiency: 'medium',
        disclaimer: '不代表动物数量',
      );

  @override
  Future<DailyNatureBrief> dailyBrief(String parkId) async =>
      const DailyNatureBrief(
        parkId: 'taiziwan-park',
        parkName: '太子湾公园',
        headline: '近期鸣虫值得继续倾听',
        summary: '社区记录',
        facts: [],
        possibleExplanations: [],
        mission: '倾听草地',
        dataSufficiency: 'medium',
        disclaimer: '近期记录不代表动物数量。',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryRouteProgressStore implements RouteProgressStore {
  ExplorationRouteProgress? value;

  @override
  Future<ExplorationRouteProgress> load(String routeId) async =>
      value ?? ExplorationRouteProgress(routeId: routeId);

  @override
  Future<void> save(ExplorationRouteProgress progress) async =>
      value = progress;
}
