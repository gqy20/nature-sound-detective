import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/audio/audio_playback.dart';
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/models/exploration_feedback.dart';
import 'package:nature_sound_detective/core/storage/exploration_record.dart';
import 'package:nature_sound_detective/core/storage/exploration_store.dart';
import 'package:nature_sound_detective/features/library/nature_book_page.dart';

void main() {
  testWidgets('lists and plays a saved sound independently from works', (
    tester,
  ) async {
    final store = _MemoryStore();
    final playback = _FakePlayback();
    await tester.pumpWidget(
      MaterialApp(
        home: NatureBookPage(store: store, playback: playback),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('自然册'), findsOneWidget);
    expect(find.text('声音记录'), findsOneWidget);
    expect(find.text('作品'), findsOneWidget);
    expect(find.text('乌鸫'), findsOneWidget);

    await tester.tap(find.byKey(const Key('play-sound-1')));
    await tester.pump();
    expect(playback.lastPath, '/tmp/sound-1.wav');
  });
}

class _MemoryStore implements ExplorationStore {
  final records = <ExplorationRecord>[
    ExplorationRecord(
      id: 'sound-1',
      createdAt: DateTime(2026, 8, 5, 9, 30),
      location: '杭州',
      audioPath: '/tmp/sound-1.wav',
      duration: const Duration(seconds: 13),
      audioQuality: const AudioQuality(usable: true),
      detections: const [
        SoundDetection(
          categoryId: 'bird',
          nameZh: '鸟类鸣叫',
          confidence: 0.66,
          model: 'birdnet',
          specificSpecies: SpeciesCandidate(nameZh: '乌鸫'),
        ),
      ],
    ),
  ];

  @override
  Future<List<ExplorationRecord>> list() async => List.of(records);

  @override
  Future<void> delete(String id) async =>
      records.removeWhere((item) => item.id == id);

  @override
  Future<ExplorationRecord> save({
    required RecordedAudio recording,
    required AudioQuality quality,
    required List<SoundDetection> detections,
    required String location,
    Map<String, List<String>> fieldChecks = const {},
  }) => throw UnimplementedError();
  @override
  Future<void> setConfirmed(String id, bool confirmed) async {}
  @override
  Future<void> setFeedback(String id, ExplorationFeedback feedback) async {}
  @override
  Future<void> setFieldChecks(
    String id,
    String speciesKey,
    List<String> checks,
  ) async {}
  @override
  Future<Directory> exportReviewPackage(Directory destination) async =>
      destination;
}

class _FakePlayback implements AudioPlayback {
  final controller = StreamController<bool>.broadcast();
  String? lastPath;
  @override
  Stream<bool> get playing => controller.stream;
  @override
  Future<void> play(String path) async {
    lastPath = path;
    controller.add(true);
  }

  @override
  Future<void> playSegment(
    String path, {
    required Duration start,
    required Duration end,
  }) async {
    lastPath = path;
    controller.add(true);
  }

  @override
  Future<void> stop() async => controller.add(false);
  @override
  Future<void> dispose() => controller.close();
}
