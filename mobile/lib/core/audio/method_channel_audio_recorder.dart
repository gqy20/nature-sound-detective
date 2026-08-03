import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';

class MethodChannelAudioRecorder implements AudioRecorder {
  MethodChannelAudioRecorder({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.xykw.nature_sound/audio_recorder';
  final MethodChannel _channel;

  @override
  Future<bool> hasPermission() async {
    return await _channel.invokeMethod<bool>('hasPermission') ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    return await _channel.invokeMethod<bool>('requestPermission') ?? false;
  }

  @override
  Future<RecordingSession> start({
    Duration maxDuration = const Duration(seconds: 20),
  }) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'startRecording',
      {'max_duration_ms': maxDuration.inMilliseconds},
    );
    if (value == null || value['id'] is! String) {
      throw const FormatException('原生录音模块没有返回录音编号。');
    }
    return RecordingSession(
      id: value['id']! as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        value['started_at_ms']! as int,
      ),
    );
  }

  @override
  Future<RecordedAudio> stop() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'stopRecording',
    );
    if (value == null) {
      throw const FormatException('原生录音模块没有返回音频文件。');
    }
    return RecordedAudio.fromMap(value);
  }

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancelRecording');

  Future<RecordedAudio> loadDebugDemo() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'loadDebugDemo',
    );
    if (value == null) {
      throw const FormatException('调试示例声音没有返回音频文件。');
    }
    return RecordedAudio.fromMap(value);
  }
}
