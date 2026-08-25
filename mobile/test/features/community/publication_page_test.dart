import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/storage/exploration_record.dart';
import 'package:nature_sound_detective/features/community/publication_page.dart';

void main() {
  testWidgets('publishes the real observation before its selected story video', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = Directory.systemTemp.createTempSync('community-work-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final video = File('${directory.path}/story.mp4');
    video.writeAsBytesSync([0, 1, 2, 3]);
    final service = _PublicationService();
    final record = ExplorationRecord(
      id: 'observation-1',
      createdAt: DateTime.utc(2026, 8, 25),
      location: '杭州植物园',
      audioPath: '${directory.path}/sound.wav',
      duration: const Duration(seconds: 8),
      audioQuality: const AudioQuality(usable: true),
      detections: const [
        SoundDetection(
          categoryId: 'bird',
          nameZh: '鸟鸣',
          confidence: .8,
          model: 'yamnet',
          specificSpecies: SpeciesCandidate(nameZh: '乌鸫'),
        ),
      ],
    );
    final work = CreationRecord(
      id: 'work-1',
      subject: '乌鸫',
      location: '杭州植物园',
      createdAt: DateTime.utc(2026, 8, 25),
      updatedAt: DateTime.utc(2026, 8, 25),
      stage: CreationStage.completed,
      message: '完成',
      directoryPath: directory.path,
      sourceAudioPath: record.audioPath,
      finalVideoPath: video.path,
    );

    CommunityPost? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-publication'),
                onPressed: () async {
                  result = await Navigator.of(context).push<CommunityPost>(
                    MaterialPageRoute(
                      builder: (_) => PublicationPage(
                        record: record,
                        service: service,
                        availableWorks: [work],
                      ),
                    ),
                  );
                },
                child: const Text('发布'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-publication')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('同时发布自然作品'), findsOneWidget);
    await tester.tap(find.byKey(const Key('include-community-work')));
    await tester.tap(find.byKey(const Key('adult-confirmation')));
    await tester.tap(find.byKey(const Key('public-consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-publication')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(service.publishCalls, 1);
    expect(service.mediaCalls, 1);
    expect(service.lastSourceType, 'composed');
    expect(service.lastFilePath, video.path);
    expect(result?.id, 'post-1');
  });
}

class _PublicationService implements CommunityService {
  int publishCalls = 0;
  int mediaCalls = 0;
  String? lastSourceType;
  String? lastFilePath;

  final post = CommunityPost(
    id: 'post-1',
    alias: '晨风探员 123',
    areaId: 'xihu',
    areaName: '西湖区',
    subject: '乌鸫',
    soundType: '鸟鸣',
    observedAt: DateTime.utc(2026, 8, 25),
    createdAt: DateTime.utc(2026, 8, 25),
    audioUrl: '/audio.wav',
    duration: const Duration(seconds: 8),
    candidateNames: const ['乌鸫'],
    fieldObservations: const [],
    status: 'published_unverified',
    reviewStatus: 'not_requested',
    responseCount: 0,
    responseSummary: const {},
    ownedByRequester: true,
  );

  @override
  Future<CommunityPost> publish(PublicationRequest request) async {
    publishCalls += 1;
    return post;
  }

  @override
  Future<CommunityMediaAsset> addMedia(
    String postId, {
    required String filePath,
    required String mediaType,
    required String sourceType,
    String? provider,
    String? model,
  }) async {
    mediaCalls += 1;
    lastSourceType = sourceType;
    lastFilePath = filePath;
    return const CommunityMediaAsset(
      id: 'asset-1',
      mediaType: 'video',
      sourceType: 'composed',
      url: '/video.mp4',
    );
  }

  @override
  Future<List<CommunityPark>> listParks() async => const [
    CommunityPark(
      id: 'hangzhou-botanical-garden',
      name: '杭州植物园',
      areaId: 'xihu',
      areaName: '西湖区',
      habitatTags: ['林地'],
      zoneCount: 1,
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
  Future<List<SoundscapeArea>> listAreas() async => const [];
  @override
  Future<List<CommunityPost>> listPosts({String? areaId}) async => const [];
  @override
  Future<EcologySnapshot> ecologySnapshot(String parkId) =>
      throw UnimplementedError();
  @override
  Future<DailyNatureBrief> dailyBrief(String parkId) =>
      throw UnimplementedError();
  @override
  Future<List<ExplorationRoute>> listRoutes(String parkId) async => const [];
  @override
  Future<CommunityPost> assist(
    String postId, {
    required String choice,
    bool alsoHeard = false,
    int? keySecond,
  }) => throw UnimplementedError();
  @override
  Future<void> withdraw(String postId) async {}
}
