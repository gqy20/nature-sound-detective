import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/storage/creation_settings_store.dart';

void main() {
  test('persists and clears local creation settings', () async {
    final directory = await Directory.systemTemp.createTemp('settings_test_');
    addTearDown(() => directory.delete(recursive: true));
    final secretStore = _MemoryCreationSecretStore();
    final store = FileCreationSettingsStore(
      directoryProvider: () async => directory,
      secretStore: secretStore,
    );
    const settings = CreationSettings(
      dashscopeApiKey: 'dashscope-key',
      dashscopeWorkspaceId: 'workspace-1',
      dashscopeMusicModel: 'fun-music-preview',
      dashscopeSpeechModel: 'qwen-audio-3.0-tts-flash',
      dashscopeSpeechVoice: 'longanfengyue',
    );

    await store.save(settings);
    final restored = await store.load();

    expect(restored.dashscopeApiKey, 'dashscope-key');
    expect(restored.dashscopeMusicModel, 'fun-music-preview');
    expect(restored.dashscopeSpeechModel, 'qwen-audio-3.0-tts-flash');
    expect(restored.dashscopeSpeechVoice, 'longanfengyue');
    expect(restored.wanVideoModel, 'wan3.0-video');
    expect(
      restored.dashscopeBaseUrl,
      'https://workspace-1.cn-beijing.maas.aliyuncs.com',
    );
    final settingsFile = File(
      '${directory.path}/config/creation_settings.json',
    );
    final persisted = await settingsFile.readAsString();
    expect(persisted, isNot(contains('dashscope-key')));
    expect(persisted, isNot(contains('dashscope_api_key')));

    await store.clear();
    expect((await store.load()).canCreate, isFalse);
  });

  test('one DashScope key enables the complete creation pipeline', () {
    const settings = CreationSettings(dashscopeApiKey: 'dashscope-key');

    expect(settings.hasMusic, isTrue);
    expect(settings.hasNarration, isTrue);
    expect(settings.canCreate, isTrue);
  });

  test('loading once removes legacy MiniMax and region fields', () async {
    final directory = await Directory.systemTemp.createTemp('legacy_settings_');
    addTearDown(() => directory.delete(recursive: true));
    final config = Directory('${directory.path}/config')..createSync();
    final file = File('${config.path}/creation_settings.json');
    await file.writeAsString(
      jsonEncode({
        'minimax_api_key': 'legacy-key',
        'minimax_music_model': 'music-2.6',
        'dashscope_region': 'singapore',
        'dashscope_api_key': 'dashscope-key',
        'wan_video_model': 'wan2.7-t2v',
      }),
    );
    final store = FileCreationSettingsStore(
      directoryProvider: () async => directory,
      secretStore: _MemoryCreationSecretStore(),
    );

    final loaded = await store.load();
    final cleaned =
        jsonDecode(await file.readAsString()) as Map<String, Object?>;

    expect(loaded.dashscopeApiKey, 'dashscope-key');
    expect(cleaned.keys.where((key) => key.startsWith('minimax_')), isEmpty);
    expect(cleaned.containsKey('dashscope_region'), isFalse);
    expect(cleaned.containsKey('dashscope_api_key'), isFalse);
    expect(loaded.wanVideoModel, 'wan3.0-video');
    expect(cleaned['wan_video_model'], 'wan3.0-video');
  });
}

class _MemoryCreationSecretStore implements CreationSecretStore {
  String value = '';

  @override
  Future<String> load() async => value;

  @override
  Future<void> save(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = '';
  }
}
