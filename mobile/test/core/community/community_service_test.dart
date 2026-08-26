import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';

void main() {
  test('coalesces anonymous session creation and sends bearer token', () async {
    final directory = await Directory.systemTemp.createTemp('community-auth-');
    addTearDown(() => directory.delete(recursive: true));
    var sessionRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/community/session') {
        sessionRequests++;
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['device_id'], startsWith('device_'));
        return http.Response(
          jsonEncode({
            'token': 'signed-test-token',
            'expires_at':
                DateTime.now()
                    .add(const Duration(days: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      expect(request.headers['Authorization'], 'Bearer signed-test-token');
      if (request.url.path == '/api/community/areas') {
        return http.Response('[]', 200);
      }
      if (request.url.path == '/api/community/posts') {
        return http.Response('[]', 200);
      }
      return http.Response('not found', 404);
    });
    final service = HttpCommunityService(
      baseUri: Uri.parse('https://api.example.test'),
      client: client,
      identityStore: CommunityIdentityStore(
        directoryProvider: () async => directory,
      ),
    );

    await Future.wait([service.listAreas(), service.listPosts()]);
    expect(sessionRequests, 1);
  });

  test('resolves relative audio and community media URLs', () async {
    final directory = await Directory.systemTemp.createTemp('community-url-');
    addTearDown(() => directory.delete(recursive: true));
    final client = MockClient((request) async {
      if (request.url.path == '/api/community/session') {
        return http.Response(
          jsonEncode({
            'token': 'signed-test-token',
            'expires_at':
                DateTime.now()
                    .add(const Duration(days: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
          200,
        );
      }
      if (request.url.path == '/api/community/posts') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {
                'id': 'post-1',
                'alias': '匿名探员',
                'area_id': 'xihu',
                'area_name': '西湖区',
                'subject': '乌鸫',
                'sound_type': '鸟鸣',
                'observed_at': '2026-08-25T08:00:00Z',
                'created_at': '2026-08-25T08:00:00Z',
                'audio_url': '/api/community/media/audio.wav',
                'duration_ms': 8000,
                'candidate_names': ['乌鸫'],
                'field_observations': [],
                'status': 'published_unverified',
                'review_status': 'not_requested',
                'is_demo': true,
                'media_assets': [
                  {
                    'id': 'asset-1',
                    'media_type': 'video',
                    'source_type': 'composed',
                    'url': '/api/community/media/story.mp4',
                  },
                ],
              },
            ]),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('not found', 404);
    });
    final service = HttpCommunityService(
      baseUri: Uri.parse('https://api.example.test'),
      client: client,
      identityStore: CommunityIdentityStore(
        directoryProvider: () async => directory,
      ),
    );

    final posts = await service.listPosts();
    expect(
      posts.single.audioUrl,
      'https://api.example.test/api/community/media/audio.wav',
    );
    expect(
      posts.single.mediaAssets.single.url,
      'https://api.example.test/api/community/media/story.mp4',
    );
    expect(posts.single.isDemo, isTrue);
  });

  test('times out a hanging session and allows the next attempt', () async {
    final directory = await Directory.systemTemp.createTemp(
      'community-timeout-',
    );
    addTearDown(() => directory.delete(recursive: true));
    var sessionRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/community/session') {
        sessionRequests++;
        if (sessionRequests == 1) {
          return Completer<http.Response>().future;
        }
        return http.Response(
          jsonEncode({
            'token': 'recovered-token',
            'expires_at':
                DateTime.now()
                    .add(const Duration(days: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
          200,
        );
      }
      expect(request.headers['Authorization'], 'Bearer recovered-token');
      return http.Response('[]', 200);
    });
    final service = HttpCommunityService(
      baseUri: Uri.parse('https://api.example.test'),
      client: client,
      identityStore: CommunityIdentityStore(
        directoryProvider: () async => directory,
      ),
      requestTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      service.listParks(),
      throwsA(
        isA<CommunityException>().having(
          (error) => error.message,
          'message',
          contains('超时'),
        ),
      ),
    );
    expect(await service.listParks(), isEmpty);
    expect(sessionRequests, 2);
  });

  test('times out a hanging authenticated request', () async {
    final directory = await Directory.systemTemp.createTemp(
      'community-get-timeout-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final client = MockClient((request) async {
      if (request.url.path == '/api/community/session') {
        return http.Response(
          jsonEncode({
            'token': 'signed-test-token',
            'expires_at':
                DateTime.now()
                    .add(const Duration(days: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
          200,
        );
      }
      return Completer<http.Response>().future;
    });
    final service = HttpCommunityService(
      baseUri: Uri.parse('https://api.example.test'),
      client: client,
      identityStore: CommunityIdentityStore(
        directoryProvider: () async => directory,
      ),
      requestTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(service.listParks(), throwsA(isA<CommunityException>()));
  });

  test('coalesces concurrent identity creation', () async {
    final directory = await Directory.systemTemp.createTemp(
      'community-identity-',
    );
    addTearDown(() => directory.delete(recursive: true));
    var directoryRequests = 0;
    final store = CommunityIdentityStore(
      directoryProvider: () async {
        directoryRequests++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return directory;
      },
    );

    final values = await Future.wait(List.generate(12, (_) => store.load()));

    expect(values.toSet(), hasLength(1));
    expect(values.first, startsWith('device_'));
    expect(directoryRequests, 1);
  });
}
