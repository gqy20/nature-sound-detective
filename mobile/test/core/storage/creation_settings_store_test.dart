import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/storage/creation_settings_store.dart';

void main() {
  test('persists and clears local creation settings', () async {
    final directory = await Directory.systemTemp.createTemp('settings_test_');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileCreationSettingsStore(
      directoryProvider: () async => directory,
    );
    const settings = CreationSettings(
      minimaxApiKey: 'minimax-key',
      dashscopeApiKey: 'dashscope-key',
      dashscopeWorkspaceId: 'workspace-1',
      dashscopeRegion: 'singapore',
    );

    await store.save(settings);
    final restored = await store.load();

    expect(restored.minimaxApiKey, 'minimax-key');
    expect(restored.dashscopeApiKey, 'dashscope-key');
    expect(
      restored.dashscopeBaseUrl,
      'https://workspace-1.ap-southeast-1.maas.aliyuncs.com',
    );

    await store.clear();
    expect((await store.load()).canCreate, isFalse);
  });
}
