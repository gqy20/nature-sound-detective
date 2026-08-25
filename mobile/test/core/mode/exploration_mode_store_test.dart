import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode_store.dart';

void main() {
  test('defaults to child mode and persists parent mode', () async {
    final directory = await Directory.systemTemp.createTemp('nature-mode-');
    addTearDown(() => directory.delete(recursive: true));
    final store = ExplorationModeStore(
      directoryProvider: () async => directory,
    );

    expect(await store.load(), ExplorationMode.child);
    await store.save(ExplorationMode.parent);
    expect(await store.load(), ExplorationMode.parent);
  });
}
