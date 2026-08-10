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
}
