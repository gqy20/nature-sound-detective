import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/network/parent_guidance_service.dart';

void main() {
  test('parses directly generated AI guidance', () async {
    final directory = await Directory.systemTemp.createTemp('parent-ai-');
    addTearDown(() => directory.delete(recursive: true));
    var sessionRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/session')) {
        sessionRequests++;
        return http.Response(
          jsonEncode({
            'token': 'v1.payload.signature',
            'expires_at': 9999999999,
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/quota')) {
        return http.Response(
          jsonEncode({'limit': 20, 'used': 1, 'remaining': 19}),
          200,
        );
      }
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['behaviors'], contains('recordedSound'));
      return http.Response(
        jsonEncode({
          'provider': 'qwen3.7-flash',
          'ai_generated': true,
          'cached': true,
          'warning': '',
          'quota': {'limit': 20, 'used': 1, 'remaining': 19},
          'guides': [
            {
              'goal': '重新听见节奏',
              'say': '你愿意再听一次，告诉我哪一声最特别吗？',
              'action': '一起用手打出刚才听见的节奏。',
              'avoid': '不要先告诉孩子答案。',
            },
            {
              'goal': '比较两条线索',
              'say': '哪条线索支持你的猜想，哪条还对不上？',
              'action': '分别说出声音和环境中的一条证据。',
              'avoid': '不要要求必须选出候选。',
            },
          ],
          'praises': [
            for (var index = 0; index < 3; index++)
              {
                'evidence_behavior': 'recordedSound',
                'ability': '主动记录',
                'text': '你把这段声音保存下来，让好奇变成了可以继续寻找的线索。',
              },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = ParentGuidanceNetworkService(
      baseUri: Uri.parse('https://api.example.test'),
      client: client,
      identityStore: CommunityIdentityStore(
        directoryProvider: () async => directory,
      ),
    );

    final result = await service.create(
      detection: const SoundDetection(
        categoryId: 'bird',
        nameZh: '鸟类鸣叫',
        confidence: .8,
        model: 'test',
        specificSpecies: SpeciesCandidate(nameZh: '珠颈斑鸠'),
      ),
      observations: const {},
      behaviors: const {ExplorationBehavior.recordedSound},
      weakSignal: false,
    );

    expect(result.aiGenerated, isTrue);
    expect(result.provider, 'qwen3.7-flash');
    expect(result.guides, hasLength(2));
    expect(result.praiseSuggestions, hasLength(3));
    expect(result.quotaRemaining, 19);
    expect(result.cached, isTrue);
    final quota = await service.loadQuota();
    expect(quota?.remaining, 19);
    expect(sessionRequests, 1);
  });

  test('falls back locally when AI endpoint is unavailable', () async {
    final directory = await Directory.systemTemp.createTemp('parent-ai-');
    addTearDown(() => directory.delete(recursive: true));
    final service = ParentGuidanceNetworkService(
      baseUri: Uri.parse('https://api.example.test'),
      client: MockClient((_) async => http.Response('unavailable', 503)),
      identityStore: CommunityIdentityStore(
        directoryProvider: () async => directory,
      ),
    );

    final result = await service.create(
      detection: null,
      observations: const {},
      behaviors: const {ExplorationBehavior.recordedSound},
      weakSignal: true,
    );

    expect(result.aiGenerated, isFalse);
    expect(result.warning, contains('本地审核模板'));
    expect(result.praiseSuggestions, isNotEmpty);
  });

  test(
    'shows a local fallback when the twenty free calls are exhausted',
    () async {
      final directory = await Directory.systemTemp.createTemp('parent-ai-');
      addTearDown(() => directory.delete(recursive: true));
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/session')) {
          return http.Response(
            jsonEncode({
              'token': 'v1.payload.signature',
              'expires_at': 9999999999,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'detail': {
              'code': 'free_ai_quota_exhausted',
              'message': '本设备的20次免费AI亲子陪伴已用完',
              'limit': 20,
              'used': 20,
              'remaining': 0,
            },
          }),
          429,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = ParentGuidanceNetworkService(
        baseUri: Uri.parse('https://api.example.test'),
        client: client,
        identityStore: CommunityIdentityStore(
          directoryProvider: () async => directory,
        ),
      );

      final result = await service.create(
        detection: null,
        observations: const {},
        behaviors: const {ExplorationBehavior.recordedSound},
        weakSignal: false,
      );

      expect(result.aiGenerated, isFalse);
      expect(result.quotaRemaining, 0);
      expect(result.quotaLimit, 20);
      expect(result.warning, contains('20次'));
      expect(result.praiseSuggestions, hasLength(3));
    },
  );
}
