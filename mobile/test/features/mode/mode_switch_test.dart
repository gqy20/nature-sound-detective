import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/app.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode_store.dart';
import 'package:nature_sound_detective/features/capture/capture_page.dart';
import 'package:nature_sound_detective/core/network/parent_guidance_service.dart';

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
    expect(find.byKey(const Key('parent-park-guide-cta')), findsOneWidget);
    expect(find.byKey(const Key('record-button')), findsOneWidget);
    expect(find.textContaining('剩余 12 / 20 次'), findsNothing);
  });

  testWidgets('app switch persists the selected mode', (tester) async {
    final store = _MemoryModeStore();
    await tester.pumpWidget(NatureSoundApp(modeStore: store));
    await tester.pump();

    await tester.tap(find.byKey(const Key('exploration-mode-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('家长陪伴'));
    await tester.pumpAndSettle();

    expect(store.value, ExplorationMode.parent);
    expect(find.text('和孩子一起听听'), findsOneWidget);
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
    expect(tester.takeException(), isNull);
  });
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
