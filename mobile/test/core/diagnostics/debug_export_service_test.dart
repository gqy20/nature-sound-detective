import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/diagnostics/debug_export_service.dart';
import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/storage/creation_settings_store.dart';
import 'package:nature_sound_detective/core/storage/exploration_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'exports a session bundle without credentials or absolute paths',
    () async {
      final root = await Directory.systemTemp.createTemp('xykw-debug-export-');
      addTearDown(() => root.delete(recursive: true));
      final audio = File(p.join(root.path, 'source.wav'));
      await audio.writeAsBytes(List<int>.generate(128, (index) => index));
      final logs = File(p.join(root.path, 'logs.jsonl'));
      await logs.writeAsString(
        '${jsonEncode({'component': 'app', 'event': 'started'})}\n'
        '${jsonEncode({'component': 'audio', 'event': 'completed', 'trace_id': 'rec_42'})}\n',
      );
      final settingsStore = FileCreationSettingsStore(
        directoryProvider: () async => Directory(p.join(root.path, 'support')),
      );
      await settingsStore.save(
        const CreationSettings(
          minimaxApiKey: 'sk-private-minimax-key',
          dashscopeApiKey: 'sk-private-dashscope-key',
          dashscopeWorkspaceId: 'private-workspace',
        ),
      );
      final service = DebugExportService(
        explorationStore: FileExplorationStore(
          rootProvider: () async => Directory(p.join(root.path, 'records')),
        ),
        settingsStore: settingsStore,
        cacheDirectoryProvider: () async =>
            Directory(p.join(root.path, 'cache')),
        appInfoProvider: () async => {
          'name': 'Nature Sound Detective',
          'version': '1.2.3',
          'build_number': '45',
        },
        deviceInfoProvider: () async => {
          'platform': 'android',
          'model': 'test-device',
        },
        logExporter: () async => logs.path,
        now: () => DateTime.utc(2026, 8, 5, 12, 30),
      );
      final session = DebugSessionSnapshot.current(
        recording: RecordedAudio(
          id: 'rec_42',
          path: audio.path,
          duration: const Duration(seconds: 13),
          sampleRate: 48000,
          channelCount: 1,
          byteLength: 128,
        ),
        quality: const AudioQuality(
          usable: true,
          rms: 0.12,
          peak: 0.74,
          activeWindowCount: 3,
          totalWindowCount: 4,
        ),
        detections: const [
          SoundDetection(
            categoryId: 'bird',
            nameZh: '鸟类',
            confidence: 0.72,
            model: 'birdnet',
            specificSpecies: SpeciesCandidate(nameZh: '乌鸫'),
          ),
        ],
      );

      final result = await service.export(session: session);

      expect(await result.file.exists(), isTrue);
      final archive = ZipDecoder().decodeBytes(await result.file.readAsBytes());
      final names = archive.files.map((file) => file.name).toSet();
      expect(
        names,
        containsAll(<String>{
          'manifest.json',
          'device.json',
          'config.json',
          'README.txt',
          'session/result.json',
          'session/recording.wav',
          'logs/app.jsonl',
          'logs/session.jsonl',
        }),
      );
      final allText = archive.files
          .where((file) => file.isFile && !file.name.endsWith('.wav'))
          .map((file) => utf8.decode(file.readBytes()!))
          .join('\n');
      expect(allText, contains('rec_42'));
      expect(allText, contains('minimax_configured'));
      expect(allText, isNot(contains('sk-private')));
      expect(allText, isNot(contains('private-workspace')));
      expect(allText, isNot(contains(audio.path)));
      final sessionLogs = archive.files.singleWhere(
        (file) => file.name == 'logs/session.jsonl',
      );
      expect(utf8.decode(sessionLogs.readBytes()!), contains('completed'));
      expect(utf8.decode(sessionLogs.readBytes()!), isNot(contains('started')));
    },
  );

  test('fails closed when an exported log contains a likely secret', () async {
    final root = await Directory.systemTemp.createTemp('xykw-debug-secret-');
    addTearDown(() => root.delete(recursive: true));
    final logs = File(p.join(root.path, 'logs.jsonl'));
    await logs.writeAsString(
      '{"component":"cloud","authorization":"Bearer abcdefghijklmnop"}\n',
    );
    final service = DebugExportService(
      explorationStore: FileExplorationStore(
        rootProvider: () async => Directory(p.join(root.path, 'records')),
      ),
      settingsStore: FileCreationSettingsStore(
        directoryProvider: () async => Directory(p.join(root.path, 'support')),
      ),
      cacheDirectoryProvider: () async => Directory(p.join(root.path, 'cache')),
      appInfoProvider: () async => const {},
      deviceInfoProvider: () async => const {},
      logExporter: () async => logs.path,
    );

    await expectLater(service.export(includeAudio: false), throwsStateError);
    final outputDirectory = Directory(
      p.join(root.path, 'cache', 'diagnostics'),
    );
    final outputs = await outputDirectory
        .list()
        .where((entity) => entity.path.endsWith('.zip'))
        .toList();
    expect(outputs, isEmpty);
  });
}
