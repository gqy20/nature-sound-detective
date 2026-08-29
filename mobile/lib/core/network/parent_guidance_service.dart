import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';
import 'package:nature_sound_detective/core/guidance/parent_guidance_engine.dart';
import 'package:nature_sound_detective/core/family/family_session_models.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

class ParentGuidanceQuota {
  const ParentGuidanceQuota({
    required this.limit,
    required this.used,
    required this.remaining,
  });
  final int limit;
  final int used;
  final int remaining;

  factory ParentGuidanceQuota.fromJson(Map<String, Object?> json) =>
      ParentGuidanceQuota(
        limit: (json['limit'] as num?)?.toInt() ?? 20,
        used: (json['used'] as num?)?.toInt() ?? 0,
        remaining: (json['remaining'] as num?)?.toInt() ?? 20,
      );
}

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
    // Debug APKs are commonly installed on physical devices, where 10.0.2.2
    // does not point to the developer computer. Local backend work remains
    // available through --dart-define=COMMUNITY_API_URL=...
    return 'https://listen-api.gqy20.top';
  }

  final Uri baseUri;
  final http.Client _client;
  final CommunityIdentityStore _identityStore;
  String? _cachedToken;
  DateTime? _tokenExpiresAt;
  Future<String>? _tokenRequest;

  Uri _uri(String path) => baseUri.replace(
    path: '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path',
  );

  Future<String> _token() async {
    final token = _cachedToken;
    final expiresAt = _tokenExpiresAt;
    if (token != null &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return token;
    }
    final pending = _tokenRequest;
    if (pending != null) return pending;
    final created = _createToken();
    _tokenRequest = created;
    try {
      return await created;
    } finally {
      if (identical(_tokenRequest, created)) _tokenRequest = null;
    }
  }

  Future<String> _createToken() async {
    final response = await _client
        .post(
          _uri('/api/community/session'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'device_id': await _identityStore.load()}),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode >= 400) throw const FormatException();
    final session = jsonDecode(response.body) as Map<String, Object?>;
    final token = session['token'] as String?;
    final expiresAt = session['expires_at'] as num?;
    if (token == null || token.isEmpty || expiresAt == null) {
      throw const FormatException();
    }
    _cachedToken = token;
    _tokenExpiresAt = DateTime.fromMillisecondsSinceEpoch(
      expiresAt.toInt() * 1000,
      isUtc: true,
    );
    return token;
  }

  Future<ParentGuidanceQuota?> loadQuota() async {
    try {
      final response = await _client
          .get(
            _uri('/api/community/parent-guidance/quota'),
            headers: {'Authorization': 'Bearer ${await _token()}'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 400) return null;
      return ParentGuidanceQuota.fromJson(
        (jsonDecode(response.body) as Map<Object?, Object?>)
            .cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<GuidanceBundle> create({
    required SoundDetection? detection,
    required Map<String, List<String>> observations,
    required Set<ExplorationBehavior> behaviors,
    required bool weakSignal,
    List<FamilyExplorationEvent> events = const [],
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
      final token = await _token();
      final response = await _client
          .post(
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
              'events': [
                for (final event in events)
                  {'type': event.type, 'sequence': event.sequence},
              ],
            }),
          )
          .timeout(const Duration(seconds: 45));
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
