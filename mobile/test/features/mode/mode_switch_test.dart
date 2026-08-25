import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/app.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode_store.dart';
import 'package:nature_sound_detective/features/capture/capture_page.dart';

void main() {
  testWidgets('parent view exposes the guide without replacing capture', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CapturePage(mode: ExplorationMode.parent)),
    );

    expect(find.text('和孩子一起听听'), findsOneWidget);
    expect(find.byKey(const Key('park-guide-button')), findsOneWidget);
    expect(find.byKey(const Key('parent-park-guide-cta')), findsOneWidget);
    expect(find.byKey(const Key('record-button')), findsOneWidget);
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
