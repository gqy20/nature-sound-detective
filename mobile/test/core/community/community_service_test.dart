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
          utf8.encode(jsonEncode([
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
              'media_assets': [
                {
                  'id': 'asset-1',
                  'media_type': 'video',
                  'source_type': 'composed',
                  'url': '/api/community/media/story.mp4',
                },
              ],
            },
          ])),
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
    expect(posts.single.audioUrl, 'https://api.example.test/api/community/media/audio.wav');
    expect(
      posts.single.mediaAssets.single.url,
      'https://api.example.test/api/community/media/story.mp4',
    );
  });
}
