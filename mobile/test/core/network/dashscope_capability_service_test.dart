import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/network/dashscope_capability_service.dart';

void main() {
  test(
    'reports model inference permissions without invoking generation',
    () async {
      final requests = <http.Request>[];
      final service = DashscopeCapabilityService(
        client: MockClient((request) async {
          requests.add(request);
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
        }),
      );
      const settings = CreationSettings(dashscopeApiKey: 'test-key');

      final report = await service.check(settings, const [
        'fun-music-v1',
        'qwen-audio-3.0-tts-plus',
        'wan3.0-video',
      ]);

      expect(report.statusOf('fun-music-v1'), DashscopeCapabilityStatus.denied);
      expect(
        report.statusOf('qwen-audio-3.0-tts-plus'),
        DashscopeCapabilityStatus.denied,
      );
      expect(
        report.statusOf('wan3.0-video'),
        DashscopeCapabilityStatus.allowed,
      );
      expect(requests, hasLength(3));
      expect(
        requests.every(
          (request) => request.headers['authorization'] == 'Bearer test-key',
        ),
        isTrue,
      );
      await service.check(settings, const [
        'fun-music-v1',
        'qwen-audio-3.0-tts-plus',
        'wan3.0-video',
      ]);
      expect(requests, hasLength(3));
    },
  );

  test('uses unknown when the permission endpoint is unavailable', () async {
    final service = DashscopeCapabilityService(
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );

    final report = await service.check(
      const CreationSettings(dashscopeApiKey: 'test-key'),
      const ['wan3.0-video'],
    );

    expect(report.statusOf('wan3.0-video'), DashscopeCapabilityStatus.unknown);
  });
}
