import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/community/community_activity_guide.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';

void main() {
  test('groups real species records into community activity points', () async {
    final guide = CommunityActivityGuide(
      postsLoader: () async => [
        _post(
          id: 'real-1',
          subject: '乌鸫',
          parkId: 'botanical',
          siteId: 'botanical:forest',
          observedAt: DateTime.utc(2026, 8, 30),
        ),
        _post(
          id: 'real-2',
          subject: '林间鸟鸣',
          candidateNames: const ['乌鸫'],
          parkId: 'botanical',
          siteId: 'botanical:forest',
          observedAt: DateTime.utc(2026, 8, 28),
        ),
        _post(
          id: 'demo',
          subject: '乌鸫',
          isDemo: true,
          observedAt: DateTime.utc(2026, 8, 31),
        ),
      ],
      parksLoader: () async => const [
        CommunityPark(
          id: 'botanical',
          name: '杭州植物园',
          areaId: 'xihu',
          areaName: '西湖区',
          habitatTags: ['林地'],
          zoneCount: 1,
        ),
      ],
      sitesLoader: () async => const [
        CommunitySite(
          id: 'botanical:forest',
          parkId: 'botanical',
          parkName: '杭州植物园',
          zoneId: 'forest',
          zoneName: '林下步道',
          habitatTags: ['林地'],
        ),
      ],
    );

    final hint = await guide.load('乌鸫', preferredParkId: 'botanical');

    expect(hint?.matchingRecordCount, 2);
    expect(hint?.points, hasLength(1));
    expect(hint?.points.single.label, '杭州植物园 · 林下步道');
    expect(hint?.points.single.recordCount, 2);
  });

  test('returns no hint when the community has no matching species', () async {
    final guide = CommunityActivityGuide(
      postsLoader: () async => [
        _post(
          id: 'other',
          subject: '蛙鸣',
          observedAt: DateTime.utc(2026, 8, 30),
        ),
      ],
      parksLoader: () async => const [],
      sitesLoader: () async => const [],
    );

    expect(await guide.load('乌鸫'), isNull);
  });
}

CommunityPost _post({
  required String id,
  required String subject,
  required DateTime observedAt,
  List<String> candidateNames = const [],
  String? parkId,
  String? siteId,
  bool isDemo = false,
}) => CommunityPost(
  id: id,
  alias: '社区探员',
  areaId: 'xihu',
  areaName: '西湖区',
  subject: subject,
  soundType: '鸟鸣',
  observedAt: observedAt,
  createdAt: observedAt,
  audioUrl: 'https://example.test/$id.mp3',
  duration: const Duration(seconds: 8),
  candidateNames: candidateNames,
  fieldObservations: const [],
  status: 'published_unverified',
  reviewStatus: 'not_requested',
  responseCount: 0,
  responseSummary: const {},
  ownedByRequester: false,
  parkId: parkId,
  siteId: siteId,
  isDemo: isDemo,
);
