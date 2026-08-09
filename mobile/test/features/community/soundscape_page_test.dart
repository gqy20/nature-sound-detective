import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
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
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('共听杭州'), findsOneWidget);
    expect(find.byKey(const Key('soundscape-area-xihu')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('community-post-post-1')),
      350,
    );
    expect(find.byKey(const Key('community-post-post-1')), findsOneWidget);
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
  Future<void> withdraw(String postId) async {}
}
