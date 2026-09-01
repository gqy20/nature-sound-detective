import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/community/route_progress_store.dart';
import 'package:nature_sound_detective/core/community/route_listening_context.dart';
import 'package:nature_sound_detective/features/park_guide/park_guide_page.dart';

import '../../support/tolerant_golden_comparator.dart';

void main() {
  useCrossPlatformGoldenComparator(precisionTolerance: 0.03);
  testWidgets('filters parks and opens a parent-guided route', (tester) async {
    tester.view.physicalSize = const Size(430, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final listeningStore = _MemoryListeningContextStore();
    var openedCapture = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ParkGuidePage(
          service: _FakeCommunityService(),
          routeProgressStore: _MemoryRouteProgressStore(),
          listeningContextStore: listeningStore,
          onStartRouteListening: () async => openedCapture = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile(
        '../../goldens/park_guide/park-selection-frameless.png',
      ),
    );

    expect(find.text('1/3 · 选择公园'), findsOneWidget);
    expect(
      find.byKey(const Key('park-guide-park-selection-page')),
      findsOneWidget,
    );
    await _selectTaiziwanPark(tester);
    expect(find.byKey(const Key('park-guide-criteria-page')), findsOneWidget);
    expect(
      find.byKey(const Key('park-guide-recommendations-page')),
      findsNothing,
    );
    expect(find.byKey(const Key('park-first-recommendation')), findsNothing);
    expect(find.text('调整家庭条件'), findsNothing);
    expect(find.textContaining('不代表动物数量'), findsNothing);
    final preferences = find.byKey(const Key('park-preference-journal'));
    expect(
      find.descendant(of: preferences, matching: find.byType(Divider)),
      findsNothing,
    );
    expect(
      tester.getBottomLeft(preferences).dy,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('../../goldens/park_guide/criteria-frameless.png'),
    );

    await tester.tap(find.text('6–7岁'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-park-recommendations')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('park-guide-recommendations-page')),
      findsOneWidget,
    );
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile(
        '../../goldens/park_guide/recommendation-top-aligned.png',
      ),
    );
    final recommendation = find.byKey(
      const Key('park-recommendation-taiziwan-park'),
    );
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
    await tester.tap(
      find.byKey(const Key('route-stop-taiziwan-park:main-lawn')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('route-listen-taiziwan-park:main-lawn')),
    );
    await tester.pumpAndSettle();
    final context = await listeningStore.load();
    expect(context?.parkId, 'taiziwan-park');
    expect(context?.zoneId, 'main-lawn');
    expect(context?.routeId, 'family-short');
    expect(context?.safeObservationConfirmed, isTrue);
    expect(openedCapture, isTrue);
  });

  testWidgets('keeps route action above an enclosing navigation bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBody: true,
          bottomNavigationBar: const SizedBox(
            key: Key('test-primary-navigation'),
            height: 96,
          ),
          body: ParkGuidePage(service: _FakeCommunityService()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectTaiziwanPark(tester);

    final action = find.byKey(const Key('open-park-recommendations'));
    final navigation = find.byKey(const Key('test-primary-navigation'));
    final criteria = find.byKey(const Key('park-guide-criteria-page'));

    expect(find.byKey(const Key('park-guide-criteria-scroll')), findsOneWidget);
    expect(find.byKey(const Key('park-guide-sticky-action')), findsOneWidget);
    expect(tester.getSize(criteria).width, closeTo(430, 0.1));
    expect(
      tester.getBottomLeft(action).dy,
      lessThanOrEqualTo(tester.getTopLeft(navigation).dy - 12),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the community suggested park at the criteria step', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ParkGuidePage(
          service: _FakeCommunityService(),
          initialParkId: 'taiziwan-park',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('park-guide-criteria-page')), findsOneWidget);
    expect(find.text('1/3 · 选择公园'), findsNothing);
    await tester.tap(find.byKey(const Key('open-park-recommendations')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('park-recommendation-taiziwan-park')),
      findsOneWidget,
    );
  });

  testWidgets('keeps available park guidance when one endpoint fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ParkGuidePage(service: _PartialCommunityService())),
    );
    await tester.pumpAndSettle();

    await _selectTaiziwanPark(tester);
    await tester.tap(find.byKey(const Key('open-park-recommendations')));
    await tester.pumpAndSettle();
    expect(find.text('太子湾公园'), findsWidgets);
    expect(find.textContaining('探索路线暂时不可用'), findsOneWidget);
    expect(find.text('游园信息暂时没有连上，请稍后重试。'), findsNothing);
  });

  testWidgets('uses age ranges and treats accessibility as a requirement', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ParkGuidePage(service: _FakeCommunityService())),
    );
    await tester.pumpAndSettle();

    await _selectTaiziwanPark(tester);
    expect(find.text('5岁及以下'), findsOneWidget);
    expect(find.text('孩子年龄'), findsOneWidget);
    expect(find.text('6–7岁'), findsOneWidget);
    expect(find.text('8–9岁'), findsOneWidget);
    expect(find.text('10–11岁'), findsOneWidget);
    expect(find.text('12岁及以上'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('都可以'), findsNothing);
    expect(find.text('需要无障碍路线'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    await tester.tap(find.byKey(const Key('park-age-fiveAndUnder')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('暂无完整匹配'), findsOneWidget);

    await tester.tap(find.byKey(const Key('park-age-sixToSeven')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('open-park-recommendations')));
    await tester.pumpAndSettle();
    expect(find.text('本次首选'), findsOneWidget);
    expect(
      find.byKey(const Key('park-recommendation-change-reason')),
      findsOneWidget,
    );
    expect(find.text('太子湾公园'), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('park-guide-criteria-page')), findsOneWidget);
  });

  testWidgets('stops loading and offers retry when park list hangs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ParkGuidePage(
          service: _HangingParkListService(),
          parkListTimeout: const Duration(milliseconds: 20),
        ),
      ),
    );

    expect(find.byKey(const Key('park-guide-loading')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.byKey(const Key('park-guide-loading')), findsNothing);
    expect(find.textContaining('请检查网络后重试'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
  });

  testWidgets('degrades a hanging park detail without blocking the page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ParkGuidePage(
          service: _HangingRouteService(),
          parkDetailTimeout: const Duration(milliseconds: 20),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('park-guide-loading')), findsNothing);
    await _selectTaiziwanPark(tester);
    await tester.tap(find.byKey(const Key('open-park-recommendations')));
    await tester.pumpAndSettle();
    expect(find.text('太子湾公园'), findsWidgets);
    expect(find.textContaining('探索路线暂时不可用'), findsOneWidget);
  });

  testWidgets('retry recovers after a bounded park list failure', (
    tester,
  ) async {
    final service = _RecoveringParkListService();
    await tester.pumpWidget(MaterialApp(home: ParkGuidePage(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('重新加载'), findsOneWidget);
    await tester.ensureVisible(find.text('重新加载'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();

    expect(find.text('重新加载'), findsNothing);
    await _selectTaiziwanPark(tester);
    await tester.tap(find.byKey(const Key('open-park-recommendations')));
    await tester.pumpAndSettle();
    expect(find.text('太子湾公园'), findsWidgets);
    expect(service.calls, 3);
  });
}

Future<void> _selectTaiziwanPark(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('select-park-taiziwan-park')));
  await tester.pumpAndSettle();
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

class _PartialCommunityService extends _FakeCommunityService {
  @override
  Future<List<ExplorationRoute>> listRoutes(String parkId) async {
    throw const CommunityException('route unavailable');
  }
}

class _HangingParkListService extends _FakeCommunityService {
  @override
  Future<List<CommunityPark>> listParks() =>
      Completer<List<CommunityPark>>().future;
}

class _HangingRouteService extends _FakeCommunityService {
  @override
  Future<List<ExplorationRoute>> listRoutes(String parkId) =>
      Completer<List<ExplorationRoute>>().future;
}

class _RecoveringParkListService extends _FakeCommunityService {
  int calls = 0;

  @override
  Future<List<CommunityPark>> listParks() async {
    calls++;
    if (calls <= 2) throw const CommunityException('temporary failure');
    return super.listParks();
  }
}

class _MemoryListeningContextStore extends RouteListeningContextStore {
  _MemoryListeningContextStore()
    : super(directoryProvider: () => throw UnimplementedError());

  RouteListeningContext? value;

  @override
  Future<RouteListeningContext?> load() async => value;

  @override
  Future<void> save(RouteListeningContext context) async => value = context;

  @override
  Future<void> clear() async => value = null;
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
