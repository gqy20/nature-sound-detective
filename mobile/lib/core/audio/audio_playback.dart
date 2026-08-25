import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

abstract interface class AudioPlayback {
  Stream<bool> get playing;

  Stream<Duration> get position;

  Future<void> play(String path);

  Future<void> playSegment(
    String path, {
    required Duration start,
    required Duration end,
  });

  Future<void> stop();

  Future<void> dispose();
}

class DeviceFileAudioPlayback implements AudioPlayback {
  DeviceFileAudioPlayback() {
    _player.setReleaseMode(ReleaseMode.stop);
  }

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _segmentSubscription;

  @override
  Stream<bool> get playing => _player.onPlayerStateChanged
      .map((state) => state == PlayerState.playing)
      .distinct();

  @override
  Stream<Duration> get position => _player.onPositionChanged;

  @override
  Future<void> play(String path) => _player.play(DeviceFileSource(path));

  @override
  Future<void> playSegment(
    String path, {
    required Duration start,
    required Duration end,
  }) async {
    await _segmentSubscription?.cancel();
    _segmentSubscription = _player.onPositionChanged.listen((position) {
      if (position >= end) unawaited(stop());
    });
    await _player.play(DeviceFileSource(path), position: start);
  }

  @override
  Future<void> stop() async {
    await _segmentSubscription?.cancel();
    _segmentSubscription = null;
    await _player.stop();
  }

  @override
  Future<void> dispose() async {
    await _segmentSubscription?.cancel();
    await _player.dispose();
  }
}
