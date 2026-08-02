import 'package:audioplayers/audioplayers.dart';

abstract interface class AudioPlayback {
  Stream<bool> get playing;

  Future<void> play(String path);

  Future<void> stop();

  Future<void> dispose();
}

class DeviceFileAudioPlayback implements AudioPlayback {
  DeviceFileAudioPlayback() {
    _player.setReleaseMode(ReleaseMode.stop);
  }

  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<bool> get playing => _player.onPlayerStateChanged
      .map((state) => state == PlayerState.playing)
      .distinct();

  @override
  Future<void> play(String path) => _player.play(DeviceFileSource(path));

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
