import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode.dart';
import 'package:nature_sound_detective/features/navigation/primary_feature.dart';
import 'package:nature_sound_detective/features/navigation/primary_feature_store.dart';

void main() {
  test('stores separate child and parent primary destinations', () async {
    final directory = await Directory.systemTemp.createTemp('primary_feature_');
    addTearDown(() => directory.delete(recursive: true));
    final store = PrimaryFeatureStore(directoryProvider: () async => directory);

    await store.save(ExplorationMode.child, PrimaryFeature.natureBook);
    await store.save(ExplorationMode.parent, PrimaryFeature.parkGuide);

    expect(await store.load(ExplorationMode.child), PrimaryFeature.natureBook);
    expect(await store.load(ExplorationMode.parent), PrimaryFeature.parkGuide);
  });
}
