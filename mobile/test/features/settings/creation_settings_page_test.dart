import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/storage/creation_settings_store.dart';
import 'package:nature_sound_detective/features/settings/creation_settings_page.dart';

void main() {
  testWidgets('DashScope is the only creation provider', (tester) async {
    final store = _MemorySettingsStore();
    await tester.pumpWidget(
      MaterialApp(home: CreationSettingsPage(store: store)),
    );
    await tester.pumpAndSettle();

    expect(find.text('统一创作服务'), findsOneWidget);
    expect(find.textContaining('音乐、旁白和视频共用一个 API Key'), findsOneWidget);
    expect(find.textContaining('北京地域'), findsOneWidget);
    expect(find.textContaining('MiniMax'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('dashscope-api-key-field')),
      'dashscope-valid-key',
    );
    await tester.tap(find.byKey(const Key('save-creation-settings')));
    await tester.pumpAndSettle();

    expect(store.saved?.dashscopeApiKey, 'dashscope-valid-key');
    expect(store.saved?.dashscopeMusicModel, 'fun-music-v1');
    expect(store.saved?.dashscopeSpeechModel, 'qwen-audio-3.0-tts-plus');
  });
}

class _MemorySettingsStore implements CreationSettingsStore {
  CreationSettings? saved;

  @override
  Future<CreationSettings> load() async => const CreationSettings();

  @override
  Future<void> save(CreationSettings settings) async => saved = settings;

  @override
  Future<void> clear() async => saved = null;
}
