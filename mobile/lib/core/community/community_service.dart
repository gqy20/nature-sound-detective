import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class CommunityService {
  Future<List<SoundscapeArea>> listAreas();
  Future<List<CommunityPost>> listPosts({String? areaId});
  Future<CommunityPost> publish(PublicationRequest request);
  Future<CommunityPost> assist(
    String postId, {
    required String choice,
    bool alsoHeard,
    int? keySecond,
  });
  Future<void> withdraw(String postId);
}

class CommunityException implements Exception {
  const CommunityException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CommunityIdentityStore {
  CommunityIdentityStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;
  String? _cached;

  Future<String> load() async {
    if (_cached case final String value) return value;
    final directory = await _directoryProvider();
    final config = Directory(p.join(directory.path, 'config'));
    await config.create(recursive: true);
    final file = File(p.join(config.path, 'community_identity.txt'));
    if (await file.exists()) {
      final value = (await file.readAsString()).trim();
      if (value.length >= 12) return _cached = value;
    }
    final random = Random.secure();
    final value =
        'device_${DateTime.now().microsecondsSinceEpoch}_'
        '${List.generate(4, (_) => random.nextInt(1 << 32).toRadixString(16)).join()}';
    await file.writeAsString(value, flush: true);
    return _cached = value;
  }

  Future<String> alias() async {
    final identity = await load();
    final number =
        identity.codeUnits.fold<int>(0, (sum, item) => sum + item) % 900 + 100;
    const names = ['雾林探员', '银杏叶探员', '湖畔听者', '晨风探员'];
    return '${names[number % names.length]} $number';
  }
}

class HttpCommunityService implements CommunityService {
  HttpCommunityService({
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
  String? _cachedToken;
  DateTime? _tokenExpiresAt;
  Future<String>? _tokenRequest;

  Uri _uri(String path, [Map<String, String>? query]) => baseUri.replace(
    path: '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path',
    queryParameters: query,
  );

  Future<Map<String, String>> _headers() async => {
    'Authorization': 'Bearer ${await _token()}',
  };

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
    final request = _createSession();
    _tokenRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_tokenRequest, request)) _tokenRequest = null;
    }
  }

  Future<String> _createSession() async {
    final response = await _client.post(
      _uri('/api/community/session'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'device_id': await _identityStore.load()}),
    );
    final payload = _decodeObject(response);
    final token = payload['token'];
    final expiresAt = payload['expires_at'];
    if (token is! String || expiresAt is! num) {
      throw const CommunityException('服务器没有返回有效的匿名访问令牌。');
    }
    _cachedToken = token;
    _tokenExpiresAt = DateTime.fromMillisecondsSinceEpoch(
      expiresAt.toInt() * 1000,
      isUtc: true,
    );
    return token;
  }

  @override
  Future<List<SoundscapeArea>> listAreas() async {
    final response = await _client.get(
      _uri('/api/community/areas'),
      headers: await _headers(),
    );
    final values = _decodeList(response);
    return values.map(SoundscapeArea.fromJson).toList(growable: false);
  }

  @override
  Future<List<CommunityPost>> listPosts({String? areaId}) async {
    final response = await _client.get(
      _uri('/api/community/posts', areaId == null ? null : {'area_id': areaId}),
      headers: await _headers(),
    );
    final values = _decodeList(response);
    return values.map(_postFromJson).toList(growable: false);
  }

  @override
  Future<CommunityPost> publish(PublicationRequest request) async {
    final record = request.record;
    final primary = record.detections.firstOrNull;
    final identity = await _identityStore.load();
    final candidates = record.detections
        .map((item) => item.specificSpecies?.nameZh ?? item.nameZh)
        .where((item) => item.trim().isNotEmpty)
        .toSet()
        .take(3)
        .toList();
    final observations = record.fieldChecks.values
        .expand((items) => items)
        .toSet()
        .toList();
    final metadata = {
      'owner_id': identity,
      'alias': await _identityStore.alias(),
      'area_id': request.consent.areaId,
      'area_name': request.consent.areaName,
      'subject':
          primary?.specificSpecies?.nameZh ?? primary?.nameZh ?? '待确认的自然声音',
      'sound_type': primary?.nameZh ?? '自然声音',
      'observed_at': record.createdAt.toUtc().toIso8601String(),
      'duration_ms': record.duration.inMilliseconds.clamp(500, 20000),
      'candidate_names': candidates,
      'field_observations': observations.take(8).toList(),
      'model_snapshot': {
        'models': record.detections.map((item) => item.model).toSet().toList(),
      },
      'adult_confirmed': request.consent.adultConfirmed,
      'public_consent': request.consent.publicConsent,
      'review_consent': request.consent.reviewConsent,
    };
    final multipart =
        http.MultipartRequest('POST', _uri('/api/community/posts'))
          ..headers.addAll(await _headers())
          ..fields['metadata'] = jsonEncode(metadata)
          ..files.add(
            await http.MultipartFile.fromPath('audio', record.audioPath),
          );
    final streamed = await multipart.send();
    final response = await http.Response.fromStream(streamed);
    final payload = _decodeObject(response);
    final post = payload['post'];
    if (post is! Map<Object?, Object?>) {
      throw const CommunityException('服务器没有返回发布结果。');
    }
    return _postFromJson(post.cast<String, Object?>());
  }

  @override
  Future<CommunityPost> assist(
    String postId, {
    required String choice,
    bool alsoHeard = false,
    int? keySecond,
  }) async {
    final response = await _client.post(
      _uri('/api/community/posts/$postId/responses'),
      headers: {...await _headers(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'responder_id': await _identityStore.load(),
        'choice': choice,
        'also_heard': alsoHeard,
        'key_second': ?keySecond,
      }),
    );
    return _postFromJson(_decodeObject(response));
  }

  @override
  Future<void> withdraw(String postId) async {
    final response = await _client.delete(
      _uri('/api/community/posts/$postId'),
      headers: await _headers(),
    );
    if (response.statusCode != 204) _throwResponse(response);
  }

  List<Map<String, Object?>> _decodeList(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwResponse(response);
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List<Object?>) {
      throw const CommunityException('服务器返回了无法识别的列表。');
    }
    return decoded
        .whereType<Map<Object?, Object?>>()
        .map((item) => item.cast<String, Object?>())
        .toList();
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwResponse(response);
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<Object?, Object?>) {
      throw const CommunityException('服务器返回了无法识别的数据。');
    }
    return decoded.cast<String, Object?>();
  }

  CommunityPost _postFromJson(Map<String, Object?> json) {
    final audioUrl = json['audio_url'] as String? ?? '';
    return CommunityPost.fromJson({
      ...json,
      if (audioUrl.startsWith('/'))
        'audio_url': baseUri.resolve(audioUrl).toString(),
    });
  }

  Never _throwResponse(http.Response response) {
    var message = '共听杭州暂时无法连接（${response.statusCode}）。';
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<Object?, Object?> && decoded['detail'] is String) {
        message = decoded['detail'] as String;
      }
    } catch (_) {}
    throw CommunityException(message);
  }
}
