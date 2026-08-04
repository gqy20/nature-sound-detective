import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/audio/method_channel_audio_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/audio_recorder');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps the native recording response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'startRecording') {
            return {'id': 'rec_1', 'started_at_ms': 1000};
          }
          if (call.method == 'stopRecording') {
            return {
              'id': 'rec_1',
              'path': '/tmp/rec_1.wav',
              'duration_ms': 3200,
              'sample_rate': 48000,
              'channel_count': 1,
              'byte_length': 307244,
            };
          }
          return true;
        });
    final recorder = MethodChannelAudioRecorder(channel: channel);

    final session = await recorder.start();
    final audio = await recorder.stop();

    expect(session.id, 'rec_1');
    expect(audio.sampleRate, 48000);
    expect(audio.duration, const Duration(milliseconds: 3200));
  });

  test('maps the debug demo response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'loadDebugDemo');
          return <String, Object>{
            'id': 'demo_1',
            'path': '/cache/demo/demo.wav',
            'duration_ms': 12000,
            'sample_rate': 48000,
            'channel_count': 1,
            'byte_length': 1152044,
          };
        });

    final recording = await MethodChannelAudioRecorder(
      channel: channel,
    ).loadDebugDemo();

    expect(recording.id, 'demo_1');
    expect(recording.duration, const Duration(seconds: 12));
    expect(recording.sampleRate, 48000);
  });

  test('maps imported audio and live recording level', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pickAudio') {
            return <String, Object>{
              'id': 'import_1',
              'path': '/cache/imports/import_1.wav',
              'duration_ms': 4500,
              'sample_rate': 44100,
              'channel_count': 1,
              'byte_length': 396944,
            };
          }
          if (call.method == 'getRecordingLevel') {
            return <String, Object>{
              'rms': 0.021,
              'peak': 0.18,
              'source': 'UNPROCESSED',
            };
          }
          return null;
        });
    final recorder = MethodChannelAudioRecorder(channel: channel);

    final imported = await recorder.pickAudio();
    final level = await recorder.getRecordingLevel();

    expect(imported?.id, 'import_1');
    expect(imported?.sampleRate, 44100);
    expect(level.rms, 0.021);
    expect(level.source, 'UNPROCESSED');
  });
}
