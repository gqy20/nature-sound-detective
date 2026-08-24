import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/audio/audio_playback.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/features/species/species_detail_page.dart';

void main() {
  testWidgets('field checks, source and audio segment are interactive', (
    tester,
  ) async {
    final playback = _FakePlayback();
    var changedObservations = <String, List<String>>{};
    await tester.pumpWidget(
      MaterialApp(
        home: SpeciesDetailPage(
          audioPath: '/recordings/bird.wav',
          playback: playback,
          onObservationsChanged: (values) => changedObservations = values,
          detection: const SoundDetection(
            categoryId: 'bird',
            nameZh: '鸟类',
            confidence: 0.72,
            model: 'test',
            intervals: [DetectionInterval(startSeconds: 3, endSeconds: 12)],
            specificSpecies: SpeciesCandidate(
              nameZh: '白头鹎',
              scientificName: 'Pycnonotus sinensis',
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('白头鹎的参考照片'), findsOneWidget);
    expect(find.text('声音像 72%'), findsOneWidget);
    expect(find.text('科普卡'), findsOneWidget);

    await tester.tap(find.text('© CharlesLam · CC BY-SA 2.0'));
    await tester.pumpAndSettle();
    expect(find.text('照片来源'), findsOneWidget);
    expect(find.text('Wikimedia Commons'), findsOneWidget);
    await tester.tap(find.text('复制来源链接'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('3.0–12.0s'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_circle_outline_rounded));
    await tester.pump();
    expect(playback.segmentStart, const Duration(seconds: 3));
    expect(playback.segmentEnd, const Duration(seconds: 12));

    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('什么时候发现的？'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清晨'));
    await tester.tap(find.text('高处树冠'));
    await tester.tap(find.text('重复鸣叫'));
    await tester.pumpAndSettle();
    expect(find.text('✓ 已满足故事生成条件'), findsOneWidget);
    await tester.tap(find.text('完成现场观察'));
    expect(changedObservations, {
      'time': ['early_morning'],
      'habitat': ['tree_canopy'],
      'sound_pattern': ['repeated'],
    });

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('认识它'), findsOneWidget);
    expect(find.textContaining('城市公园'), findsOneWidget);
    expect(find.text('听更多'), findsNothing);
    expect(find.textContaining('需联网'), findsNothing);
  });

  testWidgets('multiple intervals show a clear position', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SpeciesDetailPage(
          detection: SoundDetection(
            categoryId: 'bird',
            nameZh: '鸟类',
            confidence: 0.4,
            model: 'test',
            intervals: [
              DetectionInterval(startSeconds: 1, endSeconds: 2),
              DetectionInterval(startSeconds: 5, endSeconds: 7),
            ],
          ),
        ),
      ),
    );

    expect(find.text('1/2 · 1–2s'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline_rounded), findsNothing);
  });

  testWidgets('species without curated media keeps a visual fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SpeciesDetailPage(
          detection: SoundDetection(
            categoryId: 'bird',
            nameZh: '鸟类',
            confidence: 0.08,
            model: 'test',
            tentative: true,
            specificSpecies: SpeciesCandidate(
              nameZh: '暂未收录的鸟',
              scientificName: 'Unknown species',
            ),
          ),
        ),
      ),
    );

    expect(find.text('暂未收录的鸟'), findsOneWidget);
    expect(find.text('声音像 8% · 再听听'), findsOneWidget);
    expect(find.byIcon(Icons.flight_rounded), findsWidgets);
    expect(find.textContaining('Wikimedia'), findsNothing);
  });
}

class _FakePlayback implements AudioPlayback {
  final _controller = StreamController<bool>.broadcast();
  Duration? segmentStart;
  Duration? segmentEnd;

  @override
  Stream<bool> get playing => _controller.stream;

  @override
  Future<void> play(String path) async {
    _controller.add(true);
  }

  @override
  Future<void> playSegment(
    String path, {
    required Duration start,
    required Duration end,
  }) async {
    segmentStart = start;
    segmentEnd = end;
    _controller.add(true);
  }

  @override
  Future<void> stop() async {
    if (!_controller.isClosed) _controller.add(false);
  }

  @override
  Future<void> dispose() => _controller.close();
}
