import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';

class CloudSoundCard {
  const CloudSoundCard({
    required this.title,
    required this.explanation,
    required this.question,
    required this.safetyNote,
    this.uncertainty = '',
  });

  factory CloudSoundCard.fromJson(Map<String, Object?> json) {
    final result = json['result'];
    if (result is! Map<Object?, Object?>) {
      throw const FormatException('云端响应缺少识别结果。');
    }
    final resultMap = result.cast<String, Object?>();
    final card = resultMap['card'];
    if (card is! Map<Object?, Object?>) {
      throw const FormatException('云端响应缺少科普卡。');
    }
    final cardMap = card.cast<String, Object?>();
    return CloudSoundCard(
      title: cardMap['title'] as String? ?? '自然声音线索',
      explanation: cardMap['explanation'] as String? ?? '',
      question: cardMap['question'] as String? ?? '',
      safetyNote: cardMap['safety_note'] as String? ?? '',
      uncertainty: resultMap['uncertainty'] as String? ?? '',
    );
  }

  final String title;
  final String explanation;
  final String question;
  final String safetyNote;
  final String uncertainty;
}

abstract interface class CloudContentService {
  Future<CloudSoundCard> createCard({
    required RecordedAudio recording,
    required String location,
  });
}

class HttpCloudContentService implements CloudContentService {
  HttpCloudContentService({
    String? baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 90),
  }) : baseUrl = (baseUrl ?? _configuredBaseUrl).replaceAll(RegExp(r'/$'), ''),
       _client = client ?? http.Client();

  static const _configuredBaseUrl = String.fromEnvironment(
    'XYKW_API_BASE_URL',
    defaultValue: 'https://xykw-api.vercel.app',
  );

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<CloudSoundCard> createCard({
    required RecordedAudio recording,
    required String location,
  }) async {
    final timer = Stopwatch()..start();
    AppLog.info('cloud', 'request_started', traceId: recording.id);
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/analyze'))
          ..headers['X-Trace-ID'] = recording.id
          ..fields['location'] = location
          ..files.add(
            await http.MultipartFile.fromPath(
              'audio',
              recording.path,
              filename: '${recording.id}.wav',
            ),
          );
    late http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(timeout);
    } on TimeoutException catch (error, stackTrace) {
      timer.stop();
      AppLog.warning(
        'cloud',
        'request_timeout',
        traceId: recording.id,
        fields: {'duration_ms': timer.elapsedMilliseconds},
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    final body = await streamed.stream.bytesToString();
    timer.stop();
    AppLog.info(
      'cloud',
      'response_received',
      traceId: recording.id,
      fields: {
        'duration_ms': timer.elapsedMilliseconds,
        'status_code': streamed.statusCode,
        'response_bytes': utf8.encode(body).length,
      },
    );
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw CloudServiceException(
        statusCode: streamed.statusCode,
        message: _serverMessage(body) ?? '云端暂时无法生成科普卡。',
      );
    }
    final value = jsonDecode(body);
    if (value is! Map<String, Object?>) {
      throw const FormatException('云端返回了无法识别的数据。');
    }
    return CloudSoundCard.fromJson(value);
  }

  String? _serverMessage(String body) {
    try {
      final value = jsonDecode(body);
      if (value is Map<String, Object?>) return value['detail'] as String?;
    } on FormatException {
      return null;
    }
    return null;
  }
}

class CloudServiceException implements Exception {
  const CloudServiceException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}
