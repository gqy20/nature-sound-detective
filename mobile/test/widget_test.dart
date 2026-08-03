import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/app.dart';
import 'package:nature_sound_detective/core/audio/audio_playback.dart';
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/wav_quality_analyzer.dart';
import 'package:nature_sound_detective/core/inference/recording_analyzer.dart';
import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/features/capture/capture_page.dart';

void main() {
  testWidgets('shows the Android-first capture shell', (tester) async {
    await tester.pumpWidget(const NatureSoundApp());

    expect(find.text('自然声探员'), findsOneWidget);
    expect(find.text('听听，谁在附近？'), findsOneWidget);
    expect(find.byKey(const Key('record-button')), findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);
  });

  testWidgets('keeps the timer inside the record control', (tester) async {
    final recorder = _FakeRecorder();
    await tester.pumpWidget(
      MaterialApp(
        home: CapturePage(
          recorder: recorder,
          qualityAnalyzer: const _FakeQualityAnalyzer(usable: true),
          playback: const _FakePlayback(),
          analyzer: const _FakeAnalyzer(),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pump();

    final timer = find.byKey(const Key('recording-duration'));
    expect(timer, findsOneWidget);
    expect(
      find.ancestor(
        of: timer,
        matching: find.byKey(const Key('record-button')),
      ),
      findsOneWidget,
    );
    expect(find.text('结束'), findsOneWidget);
  });

  testWidgets('shows an unusable recording in a fixed result sheet', (
    tester,
  ) async {
    final recorder = _FakeRecorder();
    await tester.pumpWidget(
      MaterialApp(
        home: CapturePage(
          recorder: recorder,
          qualityAnalyzer: const _FakeQualityAnalyzer(usable: false),
          playback: const _FakePlayback(),
          analyzer: const _FakeAnalyzer(),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recording-result-sheet')), findsOneWidget);
    expect(find.text('声音有点远'), findsOneWidget);
    expect(find.byKey(const Key('retry-recording-button')), findsOneWidget);
  });

  testWidgets('shows progressive window clues while local analysis continues', (
    tester,
  ) async {
    final recorder = _FakeRecorder();
    final analyzer = _ProgressiveAnalyzer();
    await tester.pumpWidget(
      MaterialApp(
        home: CapturePage(
          recorder: recorder,
          qualityAnalyzer: const _FakeQualityAnalyzer(usable: true),
          playback: const _FakePlayback(),
          analyzer: analyzer,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('analyze-button')));
    await tester.pump();

    expect(find.byKey(const Key('analysis-window-progress')), findsOneWidget);
    expect(find.textContaining('1 / 2'), findsOneWidget);

    analyzer.finish.complete();
    await tester.pumpAndSettle();
  });
}

class _FakeRecorder implements AudioRecorder {
  @override
  Future<void> cancel() async {}

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<RecordingSession> start({Duration maxDuration = Duration.zero}) async {
    return RecordingSession(id: 'test', startedAt: DateTime.now());
  }

  @override
  Future<RecordedAudio> stop() async {
    return const RecordedAudio(
      id: 'test',
      path: 'test.wav',
      duration: Duration(seconds: 5),
      sampleRate: 16000,
      channelCount: 1,
      byteLength: 160000,
    );
  }
}

class _FakeQualityAnalyzer implements AudioQualityAnalyzer {
  const _FakeQualityAnalyzer({required this.usable});

  final bool usable;

  @override
  Future<AudioQuality> analyze(String path) async => AudioQuality(
    usable: usable,
    warnings: usable ? const [] : const ['声音偏小，请靠近目标声音再录一次。'],
  );
}

class _FakePlayback implements AudioPlayback {
  const _FakePlayback();

  @override
  Stream<bool> get playing => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> play(String path) async {}

  @override
  Future<void> stop() async {}
}

class _FakeAnalyzer implements RecordingAnalyzer {
  const _FakeAnalyzer();

  @override
  Future<List<SoundDetection>> analyze(
    RecordedAudio recording, {
    void Function(List<SoundDetection> detections, int processed, int total)?
    onProgress,
  }) async => const [];

  @override
  Future<void> dispose() async {}
}

class _ProgressiveAnalyzer implements RecordingAnalyzer {
  final finish = Completer<void>();

  static const detection = SoundDetection(
    categoryId: 'bird',
    nameZh: '鸟类鸣叫',
    confidence: 0.8,
    model: 'fake',
    specificSpecies: SpeciesCandidate(nameZh: '珠颈斑鸠'),
  );

  @override
  Future<List<SoundDetection>> analyze(
    RecordedAudio recording, {
    void Function(List<SoundDetection> detections, int processed, int total)?
    onProgress,
  }) async {
    onProgress?.call(const [detection], 1, 2);
    await finish.future;
    return const [detection];
  }

  @override
  Future<void> dispose() async {}
}
