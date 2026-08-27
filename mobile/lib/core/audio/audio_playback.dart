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
  AudioPlayer? _player;
  Future<AudioPlayer>? _initializing;
  StreamSubscription<Duration>? _segmentSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();

  Future<AudioPlayer> _ensurePlayer() {
    final player = _player;
    if (player != null) return Future.value(player);
    final pending = _initializing;
    if (pending != null) return pending;
    final request = _createPlayer();
    _initializing = request;
    return request.whenComplete(() {
      if (identical(_initializing, request)) _initializing = null;
    });
  }

  Future<AudioPlayer> _createPlayer() async {
    final player = AudioPlayer();
    _player = player;
    await player.setReleaseMode(ReleaseMode.stop);
    _stateSubscription = player.onPlayerStateChanged.listen(
      (state) => _playingController.add(state == PlayerState.playing),
    );
    _positionSubscription = player.onPositionChanged.listen(
      _positionController.add,
    );
    return player;
  }

  @override
  Stream<bool> get playing => _playingController.stream.distinct();

  @override
  Stream<Duration> get position => _positionController.stream;

  @override
  Future<void> play(String path) async {
    final player = await _ensurePlayer();
    await player.play(DeviceFileSource(path));
  }

  @override
  Future<void> playSegment(
    String path, {
    required Duration start,
    required Duration end,
  }) async {
    final player = await _ensurePlayer();
    await _segmentSubscription?.cancel();
    _segmentSubscription = player.onPositionChanged.listen((position) {
      if (position >= end) unawaited(stop());
    });
    await player.play(DeviceFileSource(path), position: start);
  }

  @override
  Future<void> stop() async {
    await _segmentSubscription?.cancel();
    _segmentSubscription = null;
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    await _segmentSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _player?.dispose();
    await _playingController.close();
    await _positionController.close();
  }
}
