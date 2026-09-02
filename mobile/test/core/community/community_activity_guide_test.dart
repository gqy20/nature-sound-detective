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
          id: 'related-insect',
          subject: '林间虫鸣',
          soundType: '虫鸣',
          parkId: 'botanical',
          siteId: 'botanical:forest',
          observedAt: DateTime.utc(2026, 8, 29),
        ),
        _post(
          id: 'unrelated-frog',
          subject: '池塘蛙鸣',
          soundType: '蛙鸣',
          areaId: 'yuhang',
          areaName: '余杭区',
          parkId: 'wetland',
          siteId: 'wetland:pond',
          observedAt: DateTime.utc(2026, 8, 29),
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
        CommunityPark(
          id: 'wetland',
          name: '湿地公园',
          areaId: 'yuhang',
          areaName: '余杭区',
          habitatTags: ['水域'],
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
        CommunitySite(
          id: 'wetland:pond',
          parkId: 'wetland',
          parkName: '湿地公园',
          zoneId: 'pond',
          zoneName: '池塘',
          habitatTags: ['水域'],
        ),
      ],
    );

    final hint = await guide.load('乌鸫', preferredParkId: 'botanical');

    expect(hint?.matchingRecordCount, 2);
    expect(hint?.relatedRecordCount, 3);
    expect(hint?.soundTypes, containsAll(['鸟鸣', '虫鸣']));
    expect(hint?.soundTypes, isNot(contains('蛙鸣')));
    expect(hint?.points, hasLength(1));
    expect(hint?.points.single.label, '杭州植物园 · 林下步道');
    expect(hint?.points.single.recordCount, 3);
    expect(hint?.points.single.sourceSpeciesRecordCount, 2);
    expect(hint?.focus.parkId, 'botanical');
    expect(hint?.focus.habitatTags, contains('林地'));
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
  String soundType = '鸟鸣',
  String areaId = 'xihu',
  String areaName = '西湖区',
  String? parkId,
  String? siteId,
  bool isDemo = false,
}) => CommunityPost(
  id: id,
  alias: '社区探员',
  areaId: areaId,
  areaName: areaName,
  subject: subject,
  soundType: soundType,
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
