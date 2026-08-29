import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/app.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode_store.dart';
import 'package:nature_sound_detective/features/capture/capture_page.dart';
import 'package:nature_sound_detective/core/network/parent_guidance_service.dart';
import 'package:nature_sound_detective/core/family/family_session_coordinator.dart';
import 'package:nature_sound_detective/core/family/family_session_models.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';
import 'package:nature_sound_detective/core/diagnostics/diagnostics_config.dart';

void main() {
  testWidgets('parent view exposes the guide without replacing capture', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CapturePage(
          mode: ExplorationMode.parent,
          parentGuidanceService: _FakeParentGuidanceService(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('和孩子一起听听'), findsOneWidget);
    expect(find.byKey(const Key('park-guide-button')), findsOneWidget);
    expect(find.byKey(const Key('works-button')), findsOneWidget);
    expect(find.byKey(const Key('creation-settings-button')), findsOneWidget);
    expect(find.byKey(const Key('soundscape-button')), findsOneWidget);
    expect(find.byKey(const Key('parent-park-guide-cta')), findsOneWidget);
    expect(find.byKey(const Key('record-button')), findsOneWidget);
    expect(find.textContaining('剩余 12 / 20 次'), findsNothing);
  });

  testWidgets('app switch persists the selected mode', (tester) async {
    final store = _MemoryModeStore();
    await tester.pumpWidget(
      NatureSoundApp(modeStore: store, preloadSoundscape: false),
    );
    await tester.pump();

    final modeMenu = find.byKey(const Key('exploration-mode-menu'));
    expect(
      find.descendant(
        of: modeMenu,
        matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
      ),
      findsNothing,
    );
    await tester.tap(modeMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('家长陪伴'));
    await tester.pumpAndSettle();

    expect(store.value, ExplorationMode.parent);
    expect(find.text('陪孩子一起探索'), findsOneWidget);
    expect(
      find.byKey(const Key('parent-connect-family-primary')),
      findsOneWidget,
    );
    expect(find.text('只同步探索步骤，不传原始录音、精确位置或儿童身份。'), findsNothing);
  });

  testWidgets('parent guide call to action opens the primary guide page', (
    tester,
  ) async {
    final store = _MemoryModeStore()..value = ExplorationMode.parent;
    await tester.pumpWidget(
      NatureSoundApp(modeStore: store, preloadSoundscape: false),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('parent-park-guide-cta')));
    await _pumpNavigationFrames(tester);

    expect(
      find.byKey(const Key('current-primary-feature-parkGuide')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 13));
  });

  testWidgets('parent header feature button remains actionable', (
    tester,
  ) async {
    final store = _MemoryModeStore()..value = ExplorationMode.parent;
    await tester.pumpWidget(
      NatureSoundApp(modeStore: store, preloadSoundscape: false),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('soundscape-button')));
    await _pumpNavigationFrames(tester);

    expect(
      find.byKey(const Key('current-primary-feature-soundscape')),
      findsOneWidget,
    );
  });

  testWidgets('parent home supports horizontal feature swiping', (
    tester,
  ) async {
    final store = _MemoryModeStore()..value = ExplorationMode.parent;
    await tester.pumpWidget(
      NatureSoundApp(modeStore: store, preloadSoundscape: false),
    );
    await tester.pump();

    await tester.fling(
      find.byKey(const Key('primary-feature-page-view')),
      const Offset(-650, 0),
      1200,
    );
    await _pumpNavigationFrames(tester);

    expect(
      find.byKey(const Key('current-primary-feature-soundscape')),
      findsOneWidget,
    );
  });

  testWidgets('connected parent lands on the live companion summary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final coordinator = _ConnectedParentCoordinator();
    addTearDown(coordinator.dispose);
    final store = _MemoryModeStore()..value = ExplorationMode.parent;
    await tester.pumpWidget(
      NatureSoundApp(
        modeStore: store,
        familySessionCoordinator: coordinator,
        preloadSoundscape: false,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('parent-role-home')), findsOneWidget);
    expect(find.text('孩子在探索，你来陪伴'), findsOneWidget);
    expect(find.text('孩子主动回听了声音'), findsOneWidget);
    expect(find.byKey(const Key('open-parent-live-companion')), findsOneWidget);
    expect(
      find.byKey(const Key('debug-export-button')),
      diagnosticsEnabled ? findsOneWidget : findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('open-parent-live-companion')));
    await tester.pumpAndSettle();

    expect(find.text('家庭设备联动'), findsOneWidget);
    expect(find.text('发送共同任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small screen with 200 percent text keeps capture usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const CapturePage(),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('record-button')), findsOneWidget);
    expect(
      find.byKey(const Key('debug-export-button')),
      diagnosticsEnabled ? findsOneWidget : findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpNavigationFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

class _MemoryModeStore extends ExplorationModeStore {
  _MemoryModeStore()
    : super(directoryProvider: () async => Directory.systemTemp);

  ExplorationMode value = ExplorationMode.child;

  @override
  Future<ExplorationMode> load() async => value;

  @override
  Future<void> save(ExplorationMode mode) async => value = mode;
}

class _FakeParentGuidanceService extends ParentGuidanceNetworkService {
  _FakeParentGuidanceService()
    : super(baseUri: Uri.parse('https://api.example.test'));

  @override
  Future<ParentGuidanceQuota?> loadQuota() async =>
      const ParentGuidanceQuota(limit: 20, used: 8, remaining: 12);
}

class _ConnectedParentCoordinator extends FamilySessionCoordinator {
  final _connection = FamilySessionConnection(
    sessionId: 'family-session-parent',
    role: FamilyDeviceRole.parent,
    status: FamilySessionStatus.active,
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );

  @override
  FamilySessionConnection get connection => _connection;

  @override
  Future<void> initialize() async {}

  @override
  CompanionCue get latestCue => const CompanionCue(
    eventId: 'evt-replay',
    behavior: ExplorationBehavior.replayedAudio,
    title: '孩子主动回听了声音',
    say: '你又认真听了一遍。',
    explanation: '肯定主动求证。',
    priority: 55,
  );
}
