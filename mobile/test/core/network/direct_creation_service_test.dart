import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nature_sound_detective/core/media/media_composer.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/network/direct_creation_service.dart';

void main() {
  test('downloads MiniMax music and completed Wan video', () async {
    final directory = await Directory.systemTemp.createTemp('creation_test_');
    addTearDown(() => directory.delete(recursive: true));
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.host == 'api.minimaxi.com') {
        return http.Response(
          jsonEncode({
            'data': {'audio': '494433'},
            'base_resp': {'status_code': 0},
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/video-synthesis')) {
        return http.Response(
          jsonEncode({
            'output': {'task_id': 'wan_task_1'},
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/tasks/wan_task_1')) {
        return http.Response(
          jsonEncode({
            'output': {
              'task_status': 'SUCCEEDED',
              'video_url': 'https://download.example/video.mp4',
            },
          }),
          200,
        );
      }
      if (request.url.host == 'download.example') {
        return http.Response.bytes([0, 0, 0, 24, 102, 116, 121, 112], 200);
      }
      return http.Response('not found', 404);
    });
    final updates = <CreationUpdate>[];
    final service = DirectCreationService(
      client: client,
      directoryProvider: () async => directory,
      composer: const _FakeComposer(),
      pollInterval: Duration.zero,
      videoTimeout: const Duration(seconds: 1),
    );

    final source = File('${directory.path}/source.wav')
      ..writeAsBytesSync([1, 2]);
    final result = await service.create(
      settings: const CreationSettings(
        minimaxApiKey: 'minimax-test-key',
        dashscopeApiKey: 'dashscope-test-key',
      ),
      subject: '珠颈斑鸠',
      location: '杭州',
      sourceAudioPath: source.path,
      onProgress: updates.add,
    );

    expect(result.isComplete, isTrue);
    expect(result.wanTaskId, 'wan_task_1');
    expect(await File(result.musicPath!).readAsBytes(), [73, 68, 51]);
    expect(await File(result.videoPath!).length(), greaterThan(0));
    expect(updates.last.stage, CreationStage.completed);
    expect(requests.first.headers['authorization'], 'Bearer minimax-test-key');
    expect(
      requests
          .where((request) => request.url.path.endsWith('/video-synthesis'))
          .single
          .headers['authorization'],
      'Bearer dashscope-test-key',
    );
  });

  test('keeps a completed video when music generation fails', () async {
    final directory = await Directory.systemTemp.createTemp(
      'creation_partial_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final client = MockClient((request) async {
      if (request.url.host == 'api.minimaxi.com') {
        return http.Response(
          jsonEncode({
            'base_resp': {'status_code': 1004, 'status_msg': 'invalid key'},
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/video-synthesis')) {
        return http.Response(
          jsonEncode({
            'output': {'task_id': 'wan_task_2'},
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/tasks/wan_task_2')) {
        return http.Response(
          jsonEncode({
            'output': {
              'task_status': 'SUCCEEDED',
              'video_url': 'https://download.example/video.mp4',
            },
          }),
          200,
        );
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    final service = DirectCreationService(
      client: client,
      directoryProvider: () async => directory,
      composer: const _FakeComposer(),
      pollInterval: Duration.zero,
      videoTimeout: const Duration(seconds: 1),
    );

    final source = File('${directory.path}/source.wav')
      ..writeAsBytesSync([1, 2]);
    final result = await service.create(
      settings: const CreationSettings(
        minimaxApiKey: 'minimax-test-key',
        dashscopeApiKey: 'dashscope-test-key',
      ),
      subject: '流水',
      location: '杭州',
      sourceAudioPath: source.path,
      onProgress: (_) {},
    );

    expect(result.hasMusic, isFalse);
    expect(result.hasVideo, isTrue);
    expect(result.musicError, contains('invalid key'));
  });
}

class _FakeComposer implements MediaComposer {
  const _FakeComposer();

  @override
  Future<void> compose({
    required String videoPath,
    required String musicPath,
    required String naturePath,
    required String narrationPath,
    required String outputPath,
  }) async {
    await File(outputPath).writeAsBytes([0, 0, 0, 24]);
  }
}
