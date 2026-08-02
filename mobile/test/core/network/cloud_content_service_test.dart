import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/network/cloud_content_service.dart';

void main() {
  test('parses the existing Vercel response contract', () {
    final card = CloudSoundCard.fromJson({
      'result': {
        'uncertainty': '无法确认具体物种',
        'card': {
          'title': '树梢传来的歌声',
          'explanation': '这段录音里有鸟类鸣叫的线索。',
          'question': '声音重复了几次？',
          'safety_note': '请站在步道上观察。',
        },
      },
    });

    expect(card.title, '树梢传来的歌声');
    expect(card.question, '声音重复了几次？');
    expect(card.uncertainty, '无法确认具体物种');
  });

  test('sends the recording id as the cross-service trace id', () async {
    final directory = await Directory.systemTemp.createTemp('xykw-cloud-test-');
    addTearDown(() => directory.delete(recursive: true));
    final audio = File(
      '${directory.path}${Platform.pathSeparator}recording.wav',
    );
    await audio.writeAsBytes(List.filled(44, 0));
    String? traceId;
    final client = MockClient((request) async {
      traceId = request.headers['X-Trace-ID'];
      return http.Response.bytes(
        utf8.encode(
          '{"result":{"card":{"title":"线索","explanation":"说明","question":"问题","safety_note":"安全"}}}',
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = HttpCloudContentService(
      baseUrl: 'https://example.test',
      client: client,
    );

    await service.createCard(
      recording: RecordedAudio(
        id: 'rec_test_12345678',
        path: audio.path,
        duration: const Duration(seconds: 1),
        sampleRate: 48000,
        channelCount: 1,
        byteLength: 44,
      ),
      location: '杭州',
    );

    expect(traceId, 'rec_test_12345678');
  });
}
