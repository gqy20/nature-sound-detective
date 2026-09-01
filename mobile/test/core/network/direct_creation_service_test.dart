import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nature_sound_detective/core/media/media_composer.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/network/direct_creation_service.dart';

void main() {
  test('uses one DashScope key for music, narration and Wan video', () async {
    final directory = await Directory.systemTemp.createTemp('creation_test_');
    addTearDown(() => directory.delete(recursive: true));
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/models/permissions')) {
        final model = request.url.queryParameters['model'];
        return http.Response(
          jsonEncode({
            'success': true,
            'output': {
              'permissions': [
                {
                  'model': model,
                  'permissions': {'inference': true},
                },
              ],
            },
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/audio/music/generation')) {
        return http.Response(
          jsonEncode({
            'output': {
              'audio': {'url': 'https://download.example/music.mp3'},
            },
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/audio/tts/SpeechSynthesizer')) {
        return http.Response(
          jsonEncode({
            'output': {
              'audio': {'url': 'https://download.example/narration.mp3'},
            },
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
        return request.url.path.endsWith('.mp3')
            ? http.Response.bytes([73, 68, 51], 200)
            : http.Response.bytes([0, 0, 0, 24, 102, 116, 121, 112], 200);
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
      settings: const CreationSettings(dashscopeApiKey: 'dashscope-test-key'),
      subject: '珠颈斑鸠',
      location: '杭州',
      sourceAudioPath: source.path,
      onProgress: updates.add,
      visualMode: CreationVisualMode.bird,
    );

    expect(result.isComplete, isTrue);
    expect(result.wanTaskId, 'wan_task_1');
    expect(await File(result.musicPath!).readAsBytes(), [73, 68, 51]);
    expect(await File(result.narrationPath!).readAsBytes(), [73, 68, 51]);
    expect(await File(result.videoPath!).length(), greaterThan(0));
    expect(updates.last.stage, CreationStage.completed);
    expect(
      requests
          .where(
            (request) => request.url.path.endsWith('/audio/music/generation'),
          )
          .single
          .headers['authorization'],
      'Bearer dashscope-test-key',
    );
    final musicBody =
        jsonDecode(
              requests
                  .where(
                    (request) =>
                        request.url.path.endsWith('/audio/music/generation'),
                  )
                  .single
                  .body,
            )
            as Map<String, Object?>;
    expect(musicBody['model'], 'fun-music-v1');
    final speechBody =
        jsonDecode(
              requests
                  .where(
                    (request) => request.url.path.endsWith(
                      '/audio/tts/SpeechSynthesizer',
                    ),
                  )
                  .single
                  .body,
            )
            as Map<String, Object?>;
    final videoBody =
        jsonDecode(
              requests
                  .where(
                    (request) => request.url.path.endsWith('/video-synthesis'),
                  )
                  .single
                  .body,
            )
            as Map<String, Object?>;
    expect(videoBody['model'], 'wan3.0-video');
    final videoParameters = videoBody['parameters'] as Map<String, Object?>;
    expect(videoParameters['audio'], isFalse);
    expect(videoParameters['resolution'], '480P');
    expect(videoParameters['duration'], 5);
    final videoInput = videoBody['input'] as Map<String, Object?>;
    expect(videoInput['prompt'], contains('一只珠颈斑鸠'));
    expect(videoInput['prompt'], contains('横向树枝'));
    expect(videoInput['prompt'], isNot(contains('只展示环境')));
    expect(videoInput['negative_prompt'], contains('儿童正脸'));
    expect(videoInput['negative_prompt'], contains('额外肢体'));
    expect(speechBody['model'], 'qwen-audio-3.0-tts-plus');
    expect(
      requests
          .where((request) => request.url.path.endsWith('/video-synthesis'))
          .single
          .headers['authorization'],
      'Bearer dashscope-test-key',
    );
  });

  test(
    'skips music without permission and still completes the video',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'creation_partial_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/models/permissions')) {
          final model = request.url.queryParameters['model'];
          return http.Response(
            jsonEncode({
              'success': true,
              'output': {
                'permissions': [
                  {
                    'model': model,
                    'permissions': {'inference': model == 'wan3.0-video'},
                  },
                ],
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/audio/music/generation')) {
          return http.Response('music generation must be skipped', 500);
        }
        if (request.url.path.endsWith('/audio/tts/SpeechSynthesizer')) {
          return http.Response(jsonEncode({'message': 'invalid key'}), 403);
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
        settings: const CreationSettings(dashscopeApiKey: 'dashscope-test-key'),
        subject: '流水',
        location: '杭州',
        sourceAudioPath: source.path,
        onProgress: (_) {},
      );

      expect(result.hasMusic, isFalse);
      expect(result.hasVideo, isTrue);
      expect(result.hasFinalVideo, isTrue);
      expect(result.isComplete, isTrue);
      expect(result.musicError, contains('Fun-Music 邀测权限'));
      expect(result.musicError, contains('bailian.console.aliyun.com'));
      expect(result.narrationError, contains('invalid key'));
      expect(
        requests.where(
          (request) => request.url.path.endsWith('/audio/music/generation'),
        ),
        isEmpty,
      );
      expect(
        requests.where(
          (request) =>
              request.url.path.endsWith('/audio/tts/SpeechSynthesizer'),
        ),
        hasLength(1),
      );
    },
  );
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
