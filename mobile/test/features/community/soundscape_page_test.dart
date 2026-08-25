import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/community/route_progress_store.dart';
import 'package:nature_sound_detective/features/community/soundscape_page.dart';

void main() {
  testWidgets('shows regional soundscape and structured listening card', (
    tester,
  ) async {
    final service = _FakeCommunityService();
    await tester.pumpWidget(
      MaterialApp(
        home: SoundscapePage(
          service: service,
          recordsLoader: () async => const [],
          routeProgressStore: _MemoryRouteProgressStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('共听杭州'), findsOneWidget);
    expect(find.text('杭州植物园'), findsOneWidget);
    expect(find.text('今日自然声讯'), findsOneWidget);
    expect(find.textContaining('等待更多声音'), findsOneWidget);
    expect(find.text('为什么可能这样'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('park-zone-sound-map')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('林下步道'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(
        const Key('open-exploration-route-botanical-morning-canopy'),
      ),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('亲子自然探索'), findsOneWidget);
    expect(find.text('清晨树冠声音路线'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const Key('open-exploration-route-botanical-morning-canopy'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('自然探索路线'), findsOneWidget);
    expect(find.text('已完成 0 / 1 个倾听任务'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const Key(
          'route-stop-hangzhou-botanical-garden:lingfeng-entrance',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('路线探索完成'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('杭州实景'), findsOneWidget);
    expect(find.byKey(const Key('hangzhou-offline-map')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('soundscape-area-xihu')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('soundscape-area-xihu')), findsOneWidget);
    await tester.tap(find.byKey(const Key('soundscape-area-xihu')));
    await tester.pumpAndSettle();
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

    expect(find.text('自然册里还没有声音'), findsOneWidget);
    expect(find.textContaining('先完成一次录音和调查'), findsOneWidget);
  });
}

class _MemoryRouteProgressStore implements RouteProgressStore {
  final _values = <String, ExplorationRouteProgress>{};

  @override
  Future<ExplorationRouteProgress> load(String routeId) async =>
      _values[routeId] ?? ExplorationRouteProgress(routeId: routeId);

  @override
  Future<void> save(ExplorationRouteProgress progress) async {
    _values[progress.routeId] = progress;
  }
}

class _FakeCommunityService implements CommunityService {
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

  @override
  Future<List<SoundscapeArea>> listAreas() async => const [
    SoundscapeArea(
      id: 'xihu',
      name: '西湖区',
      postCount: 1,
      waitingCount: 1,
      soundTypes: ['鸟鸣'],
    ),
  ];

  @override
  Future<List<CommunityPark>> listParks() async => const [
    CommunityPark(
      id: 'hangzhou-botanical-garden',
      name: '杭州植物园',
      areaId: 'xihu',
      areaName: '西湖区',
      habitatTags: ['林地'],
      zoneCount: 3,
    ),
  ];

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
  Future<EcologySnapshot> ecologySnapshot(String parkId) async => const EcologySnapshot(
    parkId: 'hangzhou-botanical-garden',
    validPostCount: 1,
    independentObserverCount: 1,
    soundTypeCounts: {'鸟鸣': 1},
    dataSufficiency: 'low',
    disclaimer: '不替代专业生态监测',
  );

  @override
  Future<DailyNatureBrief> dailyBrief(String parkId) async => const DailyNatureBrief(
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
  Future<List<CommunityPost>> listPosts({String? areaId}) async => [post];

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
