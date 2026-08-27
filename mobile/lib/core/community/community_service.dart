import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class CommunityService {
  Future<List<SoundscapeArea>> listAreas();
  Future<List<CommunityPark>> listParks();
  Future<List<CommunitySite>> listSites({String? parkId});
  Future<EcologySnapshot> ecologySnapshot(String parkId);
  Future<DailyNatureBrief> dailyBrief(String parkId);
  Future<List<ExplorationRoute>> listRoutes(String parkId);
  Future<List<CommunityPost>> listPosts({String? areaId});
  Future<CommunityPost> publish(PublicationRequest request);
  Future<CommunityMediaAsset> addMedia(
    String postId, {
    required String filePath,
    required String mediaType,
    required String sourceType,
    String? provider,
    String? model,
  });
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
  Future<String>? _loadRequest;

  Future<String> load() async {
    if (_cached case final String value) return value;
    final pending = _loadRequest;
    if (pending != null) return pending;
    final request = _load();
    _loadRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_loadRequest, request)) _loadRequest = null;
    }
  }

  Future<String> _load() async {
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
    this.requestTimeout = const Duration(seconds: 12),
    this.uploadTimeout = const Duration(seconds: 60),
  }) : baseUri = baseUri ?? Uri.parse(_defaultBaseUrl),
       _client = client ?? http.Client(),
       _identityStore = identityStore ?? CommunityIdentityStore(),
       _ownsClient = client == null;

  static const _configuredBaseUrl = String.fromEnvironment('COMMUNITY_API_URL');

  static String get _defaultBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    // Debug APKs are frequently installed on physical devices, where
    // 10.0.2.2 does not point to the developer computer. Local backend work
    // remains available through --dart-define=COMMUNITY_API_URL=...
    return 'https://listen-api.gqy20.top';
  }

  final Uri baseUri;
  final http.Client _client;
  final CommunityIdentityStore _identityStore;
  final bool _ownsClient;
  final Duration requestTimeout;
  final Duration uploadTimeout;
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
    final response = await _request(
      _client.post(
        _uri('/api/community/session'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'device_id': await _identityStore.load()}),
      ),
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
    final response = await _request(
      _client.get(_uri('/api/community/areas'), headers: await _headers()),
    );
    final values = _decodeList(response);
    return values.map(SoundscapeArea.fromJson).toList(growable: false);
  }

  @override
  Future<List<CommunityPark>> listParks() async {
    final response = await _request(
      _client.get(_uri('/api/community/parks'), headers: await _headers()),
    );
    return _decodeList(response)
        .map((json) => CommunityPark.fromJson(json, baseUri: baseUri))
        .toList(growable: false);
  }

  @override
  Future<List<CommunitySite>> listSites({String? parkId}) async {
    final response = await _request(
      _client.get(
        _uri(
          '/api/community/sites',
          parkId == null ? null : {'park_id': parkId},
        ),
        headers: await _headers(),
      ),
    );
    return _decodeList(
      response,
    ).map(CommunitySite.fromJson).toList(growable: false);
  }

  @override
  Future<EcologySnapshot> ecologySnapshot(String parkId) async {
    final response = await _request(
      _client.get(
        _uri('/api/community/parks/$parkId/ecology-snapshot'),
        headers: await _headers(),
      ),
    );
    return EcologySnapshot.fromJson(_decodeObject(response));
  }

  @override
  Future<DailyNatureBrief> dailyBrief(String parkId) async {
    final response = await _request(
      _client.get(
        _uri('/api/community/parks/$parkId/daily-brief'),
        headers: await _headers(),
      ),
    );
    return DailyNatureBrief.fromJson(_decodeObject(response));
  }

  @override
  Future<List<ExplorationRoute>> listRoutes(String parkId) async {
    final response = await _request(
      _client.get(
        _uri('/api/community/parks/$parkId/routes'),
        headers: await _headers(),
      ),
    );
    return _decodeList(
      response,
    ).map(ExplorationRoute.fromJson).toList(growable: false);
  }

  @override
  Future<List<CommunityPost>> listPosts({String? areaId}) async {
    final response = await _request(
      _client.get(
        _uri(
          '/api/community/posts',
          areaId == null ? null : {'area_id': areaId},
        ),
        headers: await _headers(),
      ),
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
    final observations = record.fieldObservations.values
        .expand((dimensions) => dimensions.values)
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
      if (request.consent.parkId != null) 'park_id': request.consent.parkId,
      if (request.consent.zoneId != null) 'zone_id': request.consent.zoneId,
      if (request.consent.siteId != null) 'site_id': request.consent.siteId,
      'sampling_mode': record.routeContext == null
          ? 'opportunistic'
          : 'guided_task',
      'sampling_effort': {
        'duration_seconds': record.duration.inSeconds,
        if (record.routeContext case final route?) ...{
          'route_id': route.routeId,
          'route_stop_index': route.stopIndex,
        },
      },
      'audio_quality': record.audioQuality.toJson(),
    };
    final multipart =
        http.MultipartRequest('POST', _uri('/api/community/posts'))
          ..headers.addAll(await _headers())
          ..fields['metadata'] = jsonEncode(metadata)
          ..files.add(
            await http.MultipartFile.fromPath('audio', record.audioPath),
          );
    final response = await _send(multipart, timeout: uploadTimeout);
    final payload = _decodeObject(response);
    final post = payload['post'];
    if (post is! Map<Object?, Object?>) {
      throw const CommunityException('服务器没有返回发布结果。');
    }
    return _postFromJson(post.cast<String, Object?>());
  }

  @override
  Future<CommunityMediaAsset> addMedia(
    String postId, {
    required String filePath,
    required String mediaType,
    required String sourceType,
    String? provider,
    String? model,
  }) async {
    final multipart =
        http.MultipartRequest(
            'POST',
            _uri('/api/community/posts/$postId/media'),
          )
          ..headers.addAll(await _headers())
          ..fields['media_type'] = mediaType
          ..fields['source_type'] = sourceType
          ..fields.addAll({
            if (provider != null && provider.isNotEmpty) 'provider': provider,
            if (model != null && model.isNotEmpty) 'model': model,
          })
          ..files.add(await http.MultipartFile.fromPath('file', filePath));
    final response = await _send(multipart, timeout: uploadTimeout);
    return _mediaFromJson(_decodeObject(response));
  }

  @override
  Future<CommunityPost> assist(
    String postId, {
    required String choice,
    bool alsoHeard = false,
    int? keySecond,
  }) async {
    final response = await _request(
      _client.post(
        _uri('/api/community/posts/$postId/responses'),
        headers: {...await _headers(), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'responder_id': await _identityStore.load(),
          'choice': choice,
          'also_heard': alsoHeard,
          'key_second': ?keySecond,
        }),
      ),
    );
    return _postFromJson(_decodeObject(response));
  }

  @override
  Future<void> withdraw(String postId) async {
    final response = await _request(
      _client.delete(
        _uri('/api/community/posts/$postId'),
        headers: await _headers(),
      ),
    );
    if (response.statusCode != 204) _throwResponse(response);
  }

  Future<T> _request<T>(Future<T> request) async {
    return _networkOperation(request, timeout: requestTimeout);
  }

  Future<http.Response> _send(
    http.BaseRequest request, {
    required Duration timeout,
  }) {
    return _networkOperation(
      (() async {
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      })(),
      timeout: timeout,
    );
  }

  Future<T> _networkOperation<T>(
    Future<T> operation, {
    required Duration timeout,
  }) async {
    try {
      return await operation.timeout(timeout);
    } on TimeoutException {
      throw const CommunityException('连接服务器超时，请检查网络后重试。');
    } on SocketException {
      throw const CommunityException('网络连接不可用，请检查网络后重试。');
    } on http.ClientException {
      throw const CommunityException('网络请求失败，请稍后重试。');
    }
  }

  void close() {
    if (_ownsClient) _client.close();
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
    final mediaAssets = switch (json['media_assets']) {
      final List<Object?> values =>
        values
            .whereType<Map<Object?, Object?>>()
            .map(
              (item) =>
                  _mediaJsonWithAbsoluteUrls(item.cast<String, Object?>()),
            )
            .toList(growable: false),
      _ => const <Map<String, Object?>>[],
    };
    return CommunityPost.fromJson({
      ...json,
      if (audioUrl.startsWith('/'))
        'audio_url': baseUri.resolve(audioUrl).toString(),
      'media_assets': mediaAssets,
    });
  }

  CommunityMediaAsset _mediaFromJson(Map<String, Object?> json) =>
      CommunityMediaAsset.fromJson(_mediaJsonWithAbsoluteUrls(json));

  Map<String, Object?> _mediaJsonWithAbsoluteUrls(Map<String, Object?> json) {
    final url = json['url'] as String? ?? '';
    final thumbnailUrl = json['thumbnail_url'] as String?;
    return {
      ...json,
      if (url.startsWith('/')) 'url': baseUri.resolve(url).toString(),
      if (thumbnailUrl?.startsWith('/') ?? false)
        'thumbnail_url': baseUri.resolve(thumbnailUrl!).toString(),
    };
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
