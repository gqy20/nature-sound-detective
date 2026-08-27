import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/community/soundscape_preloader.dart';
import 'package:nature_sound_detective/features/community/soundscape_page.dart';

import '../../support/tolerant_golden_comparator.dart';
import 'package:nature_sound_detective/features/community/native_amap_view.dart';

void main() {
  useCrossPlatformGoldenComparator();
  testWidgets('reuses startup soundscape preload without duplicate requests', (
    tester,
  ) async {
    final service = _FakeCommunityService();
    final preloader = SoundscapePreloader(service: service);
    await preloader.load();

    await tester.pumpWidget(
      MaterialApp(
        home: SoundscapePage(
          service: service,
          preloader: preloader,
          recordsLoader: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.areaRequests, 1);
    expect(service.postRequests, 1);
    expect(service.parkRequests, 1);
    expect(find.byKey(const Key('soundscape-map-section')), findsOneWidget);
  });

  testWidgets('offers a lightweight handoff to the park guide', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SoundscapePage(
          service: _FakeCommunityService(),
          recordsLoader: () async => const [],
          onOpenParkGuide: () => opened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('open-park-guide-from-soundscape')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('open-park-guide-from-soundscape')));

    expect(opened, isTrue);
  });

  testWidgets('returns to the city map when the primary page is re-entered', (
    tester,
  ) async {
    final position = ValueNotifier<double>(0);
    addTearDown(position.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SoundscapePage(
          service: _FakeCommunityService(),
          recordsLoader: () async => const [],
          primaryPagePosition: position,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = find.byType(ListView).first;
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, greaterThan(0));

    position.value = 1;
    await tester.pump();

    expect(scrollable.position.pixels, 0);
    expect(find.byKey(const Key('soundscape-map-section')), findsOneWidget);
  });

  testWidgets('shows regional soundscape and structured listening card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeCommunityService();
    await tester.pumpWidget(
      MaterialApp(
        home: SoundscapePage(
          service: service,
          recordsLoader: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile(
        '../../goldens/community/soundscape-community-map-first.png',
      ),
    );

    expect(find.text('共听杭州'), findsOneWidget);
    expect(find.byKey(const Key('soundscape-map-section')), findsOneWidget);
    expect(find.text('最新声音'), findsOneWidget);
    expect(find.text('等你辨认'), findsOneWidget);
    expect(find.text('本周任务'), findsNothing);
    expect(find.byKey(const Key('soundscape-today-focus')), findsNothing);
    expect(find.byKey(const Key('park-zone-sound-map')), findsNothing);
    expect(find.text('发布'), findsOneWidget);
    await tester.tap(find.byKey(const Key('soundscape-info-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 条真实观察 · 1 条体验示例'), findsOneWidget);
    expect(find.textContaining('记录数量不代表动物数量'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('离线底图'), findsOneWidget);
    expect(find.byKey(const Key('hangzhou-offline-map')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('open-fullscreen-soundscape-map')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-fullscreen-soundscape-map')));
    await tester.pumpAndSettle();
    expect(find.text('杭州声音地图'), findsOneWidget);
    expect(find.byKey(const Key('soundscape-map-zoom-in')), findsOneWidget);
    expect(find.byKey(const Key('soundscape-map-zoom-out')), findsOneWidget);
    expect(find.byKey(const Key('soundscape-map-reset')), findsOneWidget);
    await tester.tap(find.byKey(const Key('soundscape-map-zoom-in')));
    await tester.tap(find.byKey(const Key('soundscape-map-zoom-out')));
    await tester.tap(find.byKey(const Key('soundscape-map-reset')));
    await tester.tap(find.byKey(const Key('soundscape-area-xihu')));
    await tester.pumpAndSettle();
    final selectedPanel = find.byKey(const Key('fullscreen-area-panel'));
    expect(selectedPanel, findsOneWidget);
    expect(
      find.descendant(
        of: selectedPanel,
        matching: find.textContaining('不展示精确录音位置'),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('open-selected-soundscape-area')));
    await tester.pumpAndSettle();
    expect(find.text('共听杭州'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('soundscape-area-xihu')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('soundscape-area-xihu')), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(find.text('西湖区 · 1 条线索 · 1 条等待协助'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('community-post-post-1')),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('community-post-post-1')), findsOneWidget);
    expect(find.text('乌鸫候选'), findsOneWidget);
    expect(find.text('先听，再判断这条线索更像谁？'), findsOneWidget);
    expect(find.textContaining('公众协助中，尚未专业确认'), findsOneWidget);
  });

  testWidgets('empty local book keeps publication private', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SoundscapePage(
          service: _FakeCommunityService(),
          recordsLoader: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('publish-community-sound')));
    await tester.pumpAndSettle();

    expect(find.textContaining('自然册里还没有声音'), findsOneWidget);
    expect(find.textContaining('先完成一次录音和调查'), findsOneWidget);
  });

  testWidgets('offers native dynamic map on first fullscreen entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugNativeAmapSupported = true;
    var accepted = false;
    const privacyChannel = MethodChannel('com.xykw.nature_sound/amap_privacy');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(privacyChannel, (call) async {
          if (call.method == 'isAvailable') return true;
          if (call.method == 'hasConsent') return false;
          if (call.method == 'accept') accepted = true;
          return null;
        });
    addTearDown(() {
      debugNativeAmapSupported = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(privacyChannel, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SoundscapePage(
          service: _FakeCommunityService(),
          recordsLoader: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('open-fullscreen-soundscape-map')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('open-fullscreen-soundscape-map')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('enable-native-amap-first-use')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('native-map-choice-sheet'))).height,
      lessThanOrEqualTo(300),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../goldens/community/map-source-sheet.png'),
    );
    await tester.tap(find.byKey(const Key('enable-native-amap-first-use')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(accepted, isTrue);
    expect(find.byKey(const Key('native-amap-view')), findsOneWidget);
    expect(find.text('高德动态地图'), findsOneWidget);
  });

  testWidgets('uses native AMap immediately after consent was saved', (
    tester,
  ) async {
    debugNativeAmapSupported = true;
    const privacyChannel = MethodChannel('com.xykw.nature_sound/amap_privacy');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(privacyChannel, (call) async {
          if (call.method == 'isAvailable') return true;
          if (call.method == 'hasConsent') return true;
          return null;
        });
    addTearDown(() {
      debugNativeAmapSupported = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(privacyChannel, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SoundscapePage(
          service: _FakeCommunityService(),
          recordsLoader: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('open-fullscreen-soundscape-map')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('open-fullscreen-soundscape-map')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('native-amap-view')), findsOneWidget);
    expect(find.text('高德动态地图'), findsOneWidget);
  });
}

class _FakeCommunityService implements CommunityService {
  int areaRequests = 0;
  int postRequests = 0;
  int parkRequests = 0;
  final post = CommunityPost(
    id: 'post-1',
    alias: '雾林探员 027',
    areaId: 'xihu',
    areaName: '西湖区',
    subject: '乌鸫候选',
    soundType: '鸟鸣',
    observedAt: DateTime.utc(2026, 8, 9, 6),
    createdAt: DateTime.utc(2026, 8, 9, 6),
    audioUrl: '',
    duration: const Duration(seconds: 8),
    candidateNames: const ['乌鸫', '鹊鸲'],
    fieldObservations: const ['声音来自树冠'],
    status: 'published_unverified',
    reviewStatus: 'not_requested',
    responseCount: 0,
    responseSummary: const {},
    ownedByRequester: false,
    parkId: 'hangzhou-botanical-garden',
    zoneId: 'understory-trail',
    ecologyEligible: true,
    mediaAssets: const [
      CommunityMediaAsset(
        id: 'asset-1',
        mediaType: 'video',
        sourceType: 'ai_generated',
        url: 'https://example.test/story.mp4',
      ),
    ],
  );

  final demoPost = CommunityPost(
    id: 'demo-1',
    alias: '林下体验员',
    areaId: 'xihu',
    areaName: '西湖区',
    subject: '公园体验线索 · 林下鸟鸣',
    soundType: '鸟鸣',
    observedAt: DateTime.utc(2026, 8, 9, 7),
    createdAt: DateTime.utc(2026, 8, 9, 7),
    audioUrl: '',
    duration: const Duration(seconds: 9),
    candidateNames: const ['鸟类'],
    fieldObservations: const ['体验数据，不代表杭州实地记录'],
    status: 'published_unverified',
    reviewStatus: 'not_requested',
    responseCount: 1,
    responseSummary: const {'鸟类': 1},
    ownedByRequester: false,
    parkId: 'hangzhou-botanical-garden',
    zoneId: 'understory-trail',
    ecologyEligible: false,
    isDemo: true,
  );

  @override
  Future<List<SoundscapeArea>> listAreas() async {
    areaRequests++;
    return const [
      SoundscapeArea(
        id: 'xihu',
        name: '西湖区',
        postCount: 1,
        waitingCount: 1,
        soundTypes: ['鸟鸣'],
      ),
    ];
  }

  @override
  Future<List<CommunityPark>> listParks() async {
    parkRequests++;
    return const [
      CommunityPark(
        id: 'hangzhou-botanical-garden',
        name: '杭州植物园',
        areaId: 'xihu',
        areaName: '西湖区',
        habitatTags: ['林地'],
        zoneCount: 3,
      ),
    ];
  }

  @override
  Future<List<CommunitySite>> listSites({String? parkId}) async => const [
    CommunitySite(
      id: 'hangzhou-botanical-garden:understory-trail',
      parkId: 'hangzhou-botanical-garden',
      parkName: '杭州植物园',
      zoneId: 'understory-trail',
      zoneName: '林下步道',
      habitatTags: ['林下'],
    ),
  ];

  @override
  Future<EcologySnapshot> ecologySnapshot(String parkId) async =>
      const EcologySnapshot(
        parkId: 'hangzhou-botanical-garden',
        validPostCount: 1,
        independentObserverCount: 1,
        soundTypeCounts: {'鸟鸣': 1},
        dataSufficiency: 'low',
        disclaimer: '不替代专业生态监测',
      );

  @override
  Future<DailyNatureBrief> dailyBrief(String parkId) async =>
      const DailyNatureBrief(
        parkId: 'hangzhou-botanical-garden',
        parkName: '杭州植物园',
        headline: '杭州植物园正在等待更多声音',
        summary: '数据不足',
        facts: ['1条观察'],
        possibleExplanations: ['上传少不代表动物少'],
        mission: '完成一次倾听',
        dataSufficiency: 'low',
        disclaimer: '社区趋势',
      );

  @override
  Future<List<ExplorationRoute>> listRoutes(String parkId) async => const [
    ExplorationRoute(
      id: 'botanical-morning-canopy',
      parkId: 'hangzhou-botanical-garden',
      name: '清晨树冠声音路线',
      durationMinutes: 35,
      distanceKm: 1.6,
      ageMin: 6,
      tags: ['鸟类', '树冠'],
      stops: [
        ExplorationRouteStop(
          siteId: 'hangzhou-botanical-garden:lingfeng-entrance',
          minutes: 5,
          mission: '安静听三分钟',
        ),
      ],
      disclaimer: '近期社区记录不保证一定遇见动物',
    ),
  ];

  @override
  Future<List<CommunityPost>> listPosts({String? areaId}) async {
    postRequests++;
    return [post, demoPost];
  }

  @override
  Future<CommunityPost> assist(
    String postId, {
    required String choice,
    bool alsoHeard = false,
    int? keySecond,
  }) async => post;

  @override
  Future<CommunityPost> publish(PublicationRequest request) async => post;

  @override
  Future<CommunityMediaAsset> addMedia(
    String postId, {
    required String filePath,
    required String mediaType,
    required String sourceType,
    String? provider,
    String? model,
  }) async => const CommunityMediaAsset(
    id: 'uploaded-asset',
    mediaType: 'video',
    sourceType: 'composed',
    url: 'https://example.test/uploaded.mp4',
  );

  @override
  Future<void> withdraw(String postId) async {}
}
