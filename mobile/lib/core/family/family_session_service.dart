import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/family/family_session_models.dart';

class FamilySessionException implements Exception {
  const FamilySessionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ParentSessionCreated {
  const ParentSessionCreated({required this.connection});
  final FamilySessionConnection connection;
}

class FamilySessionService {
  FamilySessionService({
    Uri? baseUri,
    http.Client? client,
    CommunityIdentityStore? identityStore,
  }) : baseUri = baseUri ?? Uri.parse(_defaultBaseUrl),
       _client = client ?? http.Client(),
       _identityStore = identityStore ?? CommunityIdentityStore(),
       _ownsClient = client == null;

  static const _configuredBaseUrl = String.fromEnvironment('COMMUNITY_API_URL');
  static String get _defaultBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    return 'https://listen-api.gqy20.top';
  }

  final Uri baseUri;
  final http.Client _client;
  final CommunityIdentityStore _identityStore;
  final bool _ownsClient;
  String? _cachedToken;
  DateTime? _tokenExpiresAt;
  Future<String>? _tokenRequest;

  Uri _uri(String path, [Map<String, String>? query]) => baseUri.replace(
    path: '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path',
    queryParameters: query,
  );

  Future<String> _token() async {
    final token = _cachedToken;
    final expiresAt = _tokenExpiresAt;
    if (token != null &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return token;
    }
    if (_tokenRequest case final pending?) return pending;
    final request = _createToken();
    _tokenRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_tokenRequest, request)) _tokenRequest = null;
    }
  }

  Future<String> _createToken() async {
    final response = await _client
        .post(
          _uri('/api/community/session'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'device_id': await _identityStore.load()}),
        )
        .timeout(const Duration(seconds: 12));
    final value = _decodeObject(response);
    final token = value['token'] as String?;
    final expiresAt = value['expires_at'] as num?;
    if (token == null || expiresAt == null) {
      throw const FamilySessionException('服务器没有返回有效的设备连接凭证。');
    }
    _cachedToken = token;
    _tokenExpiresAt = DateTime.fromMillisecondsSinceEpoch(
      expiresAt.toInt() * 1000,
      isUtc: true,
    );
    return token;
  }

  Future<Map<String, String>> _headers({bool json = false}) async => {
    'Authorization': 'Bearer ${await _token()}',
    if (json) 'Content-Type': 'application/json',
  };

  Future<FamilySessionConnection> createParentSession() async {
    final response = await _client
        .post(_uri('/api/family-sessions'), headers: await _headers())
        .timeout(const Duration(seconds: 12));
    final value = _decodeObject(response);
    return FamilySessionConnection.fromJson({...value, 'role': 'parent'});
  }

  Future<FamilySessionConnection> joinAsChild(String pairCode) async {
    final response = await _client
        .post(
          _uri('/api/family-sessions/join'),
          headers: await _headers(json: true),
          body: jsonEncode({'pair_code': pairCode}),
        )
        .timeout(const Duration(seconds: 12));
    return FamilySessionConnection.fromJson(_decodeObject(response));
  }

  Future<FamilySessionConnection> loadSession(String sessionId) async {
    final response = await _client
        .get(_uri('/api/family-sessions/$sessionId'), headers: await _headers())
        .timeout(const Duration(seconds: 12));
    return FamilySessionConnection.fromJson(_decodeObject(response));
  }

  Future<FamilySessionConnection> approve(String sessionId) async {
    final response = await _client
        .post(
          _uri('/api/family-sessions/$sessionId/approve'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 12));
    return FamilySessionConnection.fromJson(_decodeObject(response));
  }

  Future<int> sendEvents(
    String sessionId,
    List<FamilyExplorationEvent> events,
  ) async {
    final response = await _client
        .post(
          _uri('/api/family-sessions/$sessionId/events/batch'),
          headers: await _headers(json: true),
          body: jsonEncode({
            'events': events.map((event) => event.toTransportJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 12));
    return (_decodeObject(response)['accepted'] as num?)?.toInt() ?? 0;
  }

  Future<List<FamilyExplorationEvent>> loadEvents(
    String sessionId,
    int afterSequence,
  ) async {
    final response = await _client
        .get(
          _uri('/api/family-sessions/$sessionId/events', {
            'after_sequence': '$afterSequence',
          }),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 12));
    return _decodeList(
      response,
    ).map(FamilyExplorationEvent.fromJson).toList(growable: false);
  }

  Future<FamilyCommand> sendCommand(String sessionId, String templateId) async {
    final response = await _client
        .post(
          _uri('/api/family-sessions/$sessionId/commands'),
          headers: await _headers(json: true),
          body: jsonEncode({'template_id': templateId}),
        )
        .timeout(const Duration(seconds: 12));
    return FamilyCommand.fromJson(_decodeObject(response));
  }

  Future<List<FamilyCommand>> loadCommands(
    String sessionId,
    int afterSequence,
  ) async {
    final response = await _client
        .get(
          _uri('/api/family-sessions/$sessionId/commands', {
            'after_sequence': '$afterSequence',
          }),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 12));
    return _decodeList(
      response,
    ).map(FamilyCommand.fromJson).toList(growable: false);
  }

  Future<void> end(String sessionId) async {
    final response = await _client
        .post(
          _uri('/api/family-sessions/$sessionId/end'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 204) _throwResponse(response);
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwResponse(response);
    }
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! Map<Object?, Object?>) {
      throw const FamilySessionException('服务器返回了无法识别的家庭会话数据。');
    }
    return value.cast<String, Object?>();
  }

  List<Map<String, Object?>> _decodeList(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwResponse(response);
    }
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! List<Object?>) {
      throw const FamilySessionException('服务器返回了无法识别的事件列表。');
    }
    return value
        .whereType<Map<Object?, Object?>>()
        .map((item) => item.cast<String, Object?>())
        .toList(growable: false);
  }

  Never _throwResponse(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final detail = body is Map<Object?, Object?> ? body['detail'] : null;
      if (detail is String && detail.isNotEmpty) {
        throw FamilySessionException(detail);
      }
    } on FamilySessionException {
      rethrow;
    } catch (_) {}
    throw FamilySessionException('家庭设备连接失败（${response.statusCode}）。');
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
