import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/app.dart';
import 'package:nature_sound_detective/core/audio/audio_playback.dart';
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/wav_quality_analyzer.dart';
import 'package:nature_sound_detective/core/diagnostics/diagnostics_config.dart';
import 'package:nature_sound_detective/core/inference/recording_analyzer.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/features/capture/capture_page.dart';
import 'package:nature_sound_detective/features/species/species_detail_page.dart';

void main() {
  testWidgets('shows the Android-first capture shell', (tester) async {
    await tester.pumpWidget(const NatureSoundApp(preloadSoundscape: false));

    expect(find.text('自然声探员'), findsOneWidget);
    expect(find.text('听听，谁在附近？'), findsOneWidget);
    expect(find.byKey(const Key('record-button')), findsOneWidget);
    expect(find.byKey(const Key('import-audio-button')), findsOneWidget);
    expect(find.byKey(const Key('family-link-button')), findsOneWidget);
    expect(find.byKey(const Key('soundscape-button')), findsOneWidget);
    expect(find.byKey(const Key('works-button')), findsOneWidget);
    expect(find.byKey(const Key('creation-settings-button')), findsOneWidget);
    expect(find.byKey(const Key('park-guide-button')), findsNothing);
    expect(
      find.byKey(const Key('debug-export-button')),
      diagnosticsEnabled ? findsOneWidget : findsNothing,
    );
    expect(find.byKey(const Key('primary-feature-page-view')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('把手机靠近想听的方向')).dy -
          tester.getBottomLeft(find.text('听听，谁在附近？')).dy,
      greaterThanOrEqualTo(12),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('record-limit-label'))).dy -
          tester.getBottomLeft(find.byKey(const Key('record-button'))).dy,
      greaterThanOrEqualTo(12),
    );
  });

  testWidgets('swipes between primary features and shows its destination', (
    tester,
  ) async {
    final logger = AppLogger(sinks: const []);
    AppLog.useLogger(logger);
    addTearDown(
      () => AppLog.useLogger(AppLogger(sinks: const [ConsoleLogSink()])),
    );
    await tester.pumpWidget(const NatureSoundApp(preloadSoundscape: false));
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('primary-feature-page-view'))),
    );
    await gesture.moveBy(const Offset(-520, 0));
    await tester.pump();
    expect(find.byKey(const Key('primary-swipe-indicator')), findsNothing);
    await gesture.up();
    await _pumpFrames(tester);
    expect(
      find.byKey(const Key('current-primary-feature-soundscape')),
      findsOneWidget,
    );
    await tester.fling(
      find.byKey(const Key('primary-feature-page-view')),
      const Offset(-650, 0),
      1200,
    );
    await _pumpFrames(tester);
    expect(
      find.byKey(const Key('current-primary-feature-natureBook')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('open-park-guide-from-soundscape')),
      findsNothing,
    );
    expect(
      logger.recent.where(
        (entry) =>
            entry.event == 'primary_navigation_requested' &&
            entry.fields['trigger'] == 'swipe',
      ),
      hasLength(2),
    );
    expect(
      logger.recent.where(
        (entry) => entry.event == 'primary_navigation_completed',
      ),
      hasLength(2),
    );
    await tester.pump(const Duration(seconds: 13));
  });

  testWidgets('existing header button uses the same primary pager', (
    tester,
  ) async {
    await tester.pumpWidget(const NatureSoundApp(preloadSoundscape: false));
    await tester.pump();

    await tester.tap(find.byKey(const Key('soundscape-button')));
    await _pumpFrames(tester);

    expect(
      find.byKey(const Key('current-primary-feature-soundscape')),
      findsOneWidget,
    );
  });

  testWidgets('primary page follows the finger and cancels a short swipe', (
    tester,
  ) async {
    final logger = AppLogger(sinks: const []);
    AppLog.useLogger(logger);
    addTearDown(
      () => AppLog.useLogger(AppLogger(sinks: const [ConsoleLogSink()])),
    );
    await tester.pumpWidget(const NatureSoundApp(preloadSoundscape: false));
    await tester.pump();

    final capture = find.byKey(const ValueKey('primary-capture-content'));
    final startX = tester.getTopLeft(capture).dx;
    final gesture = await tester.startGesture(tester.getCenter(capture));
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();

    expect(tester.getTopLeft(capture).dx, lessThan(startX - 40));

    await gesture.up();
    await _pumpFrames(tester);

    expect(
      find.byKey(const Key('current-primary-feature-capture')),
      findsOneWidget,
    );
    expect(tester.getTopLeft(capture).dx, closeTo(startX, 1));
    expect(
      logger.recent.any((entry) => entry.event == 'primary_swipe_cancelled'),
      isTrue,
    );
  });

  testWidgets('system back returns directly without crossing sibling pages', (
    tester,
  ) async {
    final logger = AppLogger(sinks: const []);
    AppLog.useLogger(logger);
    addTearDown(
      () => AppLog.useLogger(AppLogger(sinks: const [ConsoleLogSink()])),
    );
    await tester.pumpWidget(const NatureSoundApp(preloadSoundscape: false));
    await tester.pump();

    await tester.tap(find.byKey(const Key('works-button')));
    await _pumpFrames(tester);
    expect(
      find.byKey(const Key('current-primary-feature-natureBook')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await _pumpFrames(tester);

    expect(
      find.byKey(const Key('current-primary-feature-capture')),
      findsOneWidget,
    );
    final returnEvents = logger.recent.where(
      (entry) =>
          entry.event == 'primary_navigation_completed' &&
          entry.fields['trigger'] == 'system_back',
    );
    expect(returnEvents, hasLength(1));
    expect(returnEvents.single.fields['from'], 'natureBook');
    expect(returnEvents.single.fields['to'], 'capture');
    expect(returnEvents.single.fields['transition'], 'fade_through');
  });

  testWidgets('keeps the timer inside the record control', (tester) async {
    final recorder = _FakeRecorder();
    final swipeLocks = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CapturePage(
          recorder: recorder,
          qualityAnalyzer: const _FakeQualityAnalyzer(usable: true),
          playback: const _FakePlayback(),
          analyzer: const _FakeAnalyzer(),
          onPrimarySwipeLockChanged: swipeLocks.add,
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
    expect(find.byKey(const Key('live-audio-wave-ring')), findsOneWidget);
    expect(find.byKey(const Key('live-wave-hint')), findsOneWidget);
    expect(swipeLocks, contains(true));
  });

  testWidgets('does not dispose an analyzer owned by the app shell', (
    tester,
  ) async {
    final analyzer = _CountingAnalyzer();
    await tester.pumpWidget(MaterialApp(home: CapturePage(analyzer: analyzer)));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(analyzer.disposeCalls, 0);
  });

  testWidgets('requests system microphone permission without an extra dialog', (
    tester,
  ) async {
    final logger = AppLogger(sinks: const []);
    AppLog.useLogger(logger);
    addTearDown(
      () => AppLog.useLogger(AppLogger(sinks: const [ConsoleLogSink()])),
    );
    final recorder = _PermissionRecorder();
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
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('允许记录自然声音？'), findsNothing);
    expect(recorder.permissionRequests, 1);
    expect(find.text('结束'), findsOneWidget);
    expect(
      logger.recent.any(
        (entry) => entry.event == 'microphone_permission_requested',
      ),
      isTrue,
    );
    expect(
      logger.recent.any(
        (entry) =>
            entry.event == 'microphone_permission_result' &&
            entry.fields['granted'] == true,
      ),
      isTrue,
    );
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
    expect(find.byKey(const Key('audio-waveform-card')), findsOneWidget);
    expect(find.byKey(const Key('recording-waveform')), findsOneWidget);
    expect(find.text('没有录到有效声音'), findsOneWidget);
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
    await tester.pump();

    expect(find.byKey(const Key('analyze-button')), findsNothing);
    expect(find.byKey(const Key('analysis-progress')), findsOneWidget);
    expect(find.byKey(const Key('analysis-window-progress')), findsOneWidget);
    expect(find.textContaining('1 / 2'), findsOneWidget);

    analyzer.finish.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('unknown result prioritizes saving evidence and retrying', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();

    expect(find.text('回放原声 · 5s'), findsOneWidget);
    expect(find.byKey(const Key('quality-status')), findsOneWidget);
    expect(find.text('录音质量可用于识别'), findsNothing);
    expect(find.byKey(const Key('analyze-button')), findsNothing);
    await tester.drag(
      find.byKey(const Key('result-sheet-scroll')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('save-unknown-sound-button')), findsOneWidget);
    expect(find.text('保存为未知声音'), findsOneWidget);
    expect(find.byKey(const Key('unknown-retry-button')), findsOneWidget);
    expect(find.text('再录一段试试'), findsOneWidget);
    expect(find.byKey(const Key('science-card-button')), findsNothing);
    expect(find.byKey(const Key('open-creation-button')), findsNothing);
  });

  testWidgets('offers retry only when automatic analysis fails', (
    tester,
  ) async {
    final analyzer = _FailingThenSuccessfulAnalyzer();
    await tester.pumpWidget(
      MaterialApp(
        home: CapturePage(
          recorder: _FakeRecorder(),
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

    expect(analyzer.calls, 1);
    expect(find.byKey(const Key('analyze-button')), findsNothing);
    expect(find.byKey(const Key('retry-analysis-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry-analysis-button')));
    await tester.pumpAndSettle();

    expect(analyzer.calls, 2);
    expect(find.byKey(const Key('retry-analysis-button')), findsNothing);
    expect(find.byKey(const Key('unknown-result')), findsOneWidget);
  });

  testWidgets('opens the local science card without a cloud request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: CapturePage(
          recorder: _FakeRecorder(),
          qualityAnalyzer: const _FakeQualityAnalyzer(usable: true),
          playback: const _FakePlayback(),
          analyzer: const _ImmediateAnalyzer(),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('result-sheet-scroll')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('science-card-button')));
    await tester.pumpAndSettle();

    expect(find.byType(SpeciesDetailPage), findsOneWidget);
    expect(find.text('科普卡'), findsOneWidget);
    expect(find.text('生成儿童科普卡？'), findsNothing);

    expect(find.text('听更多'), findsNothing);
    expect(find.textContaining('基础科普和现场核对都在本机完成'), findsNothing);
  });

  testWidgets('separates strong model clues from weak recording evidence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CapturePage(
          recorder: _FakeRecorder(),
          qualityAnalyzer: const _FakeQualityAnalyzer(
            usable: true,
            weakSignal: true,
          ),
          playback: const _FakePlayback(),
          analyzer: const _ImmediateAnalyzer(),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('weak-evidence-notice')), findsOneWidget);
    expect(find.textContaining('录音证据较弱'), findsOneWidget);
  });
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 40}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
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

class _PermissionRecorder extends _FakeRecorder {
  int permissionRequests = 0;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }
}

class _FakeQualityAnalyzer implements AudioQualityAnalyzer {
  const _FakeQualityAnalyzer({required this.usable, this.weakSignal = false});

  final bool usable;
  final bool weakSignal;

  @override
  Future<AudioQuality> analyze(String path) async => AudioQuality(
    usable: usable,
    weakSignal: weakSignal,
    warnings: usable ? const [] : const ['声音偏小，请靠近目标声音再录一次。'],
  );
}

class _FakePlayback implements AudioPlayback {
  const _FakePlayback();

  @override
  Stream<bool> get playing => const Stream.empty();

  @override
  Stream<Duration> get position => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> play(String path) async {}

  @override
  Future<void> playSegment(
    String path, {
    required Duration start,
    required Duration end,
  }) async {}

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

class _CountingAnalyzer implements RecordingAnalyzer {
  int disposeCalls = 0;

  @override
  Future<List<SoundDetection>> analyze(
    RecordedAudio recording, {
    void Function(List<SoundDetection> detections, int processed, int total)?
    onProgress,
  }) async => const [];

  @override
  Future<void> dispose() async => disposeCalls++;
}

class _ImmediateAnalyzer implements RecordingAnalyzer {
  const _ImmediateAnalyzer();

  @override
  Future<List<SoundDetection>> analyze(
    RecordedAudio recording, {
    void Function(List<SoundDetection> detections, int processed, int total)?
    onProgress,
  }) async => const [
    SoundDetection(
      categoryId: 'bird',
      nameZh: '鸟类',
      confidence: 0.82,
      model: 'fake',
      specificSpecies: SpeciesCandidate(
        nameZh: '白头鹎',
        scientificName: 'Pycnonotus sinensis',
      ),
    ),
  ];

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

class _FailingThenSuccessfulAnalyzer implements RecordingAnalyzer {
  int calls = 0;

  @override
  Future<List<SoundDetection>> analyze(
    RecordedAudio recording, {
    void Function(List<SoundDetection> detections, int processed, int total)?
    onProgress,
  }) async {
    calls += 1;
    if (calls == 1) throw StateError('model unavailable');
    return const [];
  }

  @override
  Future<void> dispose() async {}
}
