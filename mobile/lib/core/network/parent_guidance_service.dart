import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';
import 'package:nature_sound_detective/core/guidance/parent_guidance_engine.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

class ParentGuidanceNetworkService {
  ParentGuidanceNetworkService({
    Uri? baseUri,
    http.Client? client,
    CommunityIdentityStore? identityStore,
  }) : baseUri = baseUri ?? Uri.parse(_defaultBaseUrl),
       _client = client ?? http.Client(),
       _identityStore = identityStore ?? CommunityIdentityStore();

  static const _configuredBaseUrl = String.fromEnvironment('COMMUNITY_API_URL');
  static String get _defaultBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    return kReleaseMode
        ? 'https://xykw-api.vercel.app'
        : 'http://10.0.2.2:8770';
  }

  final Uri baseUri;
  final http.Client _client;
  final CommunityIdentityStore _identityStore;

  Uri _uri(String path) => baseUri.replace(
    path: '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path',
  );

  Future<GuidanceBundle> create({
    required SoundDetection? detection,
    required Map<String, List<String>> observations,
    required Set<ExplorationBehavior> behaviors,
    required bool weakSignal,
  }) async {
    final safeBehaviors = behaviors.isEmpty
        ? const {ExplorationBehavior.recordedSound}
        : behaviors;
    final fallback = const ParentGuidanceEngine().build(
      detection: detection,
      observations: observations,
      behaviors: safeBehaviors,
    );
    try {
      final sessionResponse = await _client.post(
        _uri('/api/community/session'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'device_id': await _identityStore.load()}),
      );
      if (sessionResponse.statusCode >= 400) throw const FormatException();
      final session = jsonDecode(sessionResponse.body) as Map<String, Object?>;
      final token = session['token'] as String?;
      if (token == null || token.isEmpty) throw const FormatException();
      final response = await _client.post(
        _uri('/api/community/parent-guidance'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'candidate_name':
              detection?.specificSpecies?.nameZh ?? detection?.nameZh ?? '',
          'category': detection?.nameZh ?? '',
          'confidence': detection?.confidence ?? 0,
          'weak_signal': weakSignal,
          'observations': [
            for (final entry in observations.entries)
              for (final value in entry.value)
                if (value != 'unknown') '${entry.key}:$value',
          ],
          'behaviors': safeBehaviors.map((item) => item.name).toList(),
        }),
      );
      if (response.statusCode == 429) {
        final payload = jsonDecode(response.body) as Map<String, Object?>;
        final detail = switch (payload['detail']) {
          Map<Object?, Object?> value => value.cast<String, Object?>(),
          _ => const <String, Object?>{},
        };
        return GuidanceBundle(
          guides: fallback.guides,
          praiseSuggestions: fallback.praiseSuggestions,
          warning: detail['message'] as String? ?? '20次免费AI亲子陪伴已用完',
          quotaLimit: (detail['limit'] as num?)?.toInt() ?? 20,
          quotaRemaining: 0,
        );
      }
      if (response.statusCode >= 400) throw const FormatException();
      final bundle = GuidanceBundle.fromJson(
        (jsonDecode(response.body) as Map<Object?, Object?>)
            .cast<String, Object?>(),
      );
      if (bundle.guides.length < 2 || bundle.praiseSuggestions.length < 3) {
        throw const FormatException();
      }
      return bundle;
    } catch (error) {
      if (kDebugMode) debugPrint('AI parent guidance fallback: $error');
      return GuidanceBundle(
        guides: fallback.guides,
        praiseSuggestions: fallback.praiseSuggestions,
        warning: 'AI陪伴暂时不可用，已使用本地审核模板',
      );
    }
  }
}
