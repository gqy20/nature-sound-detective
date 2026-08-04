import 'package:flutter/services.dart';

abstract interface class MediaComposer {
  Future<void> compose({
    required String videoPath,
    required String musicPath,
    required String naturePath,
    required String narrationPath,
    required String outputPath,
  });
}

class AndroidMediaComposer implements MediaComposer {
  const AndroidMediaComposer();

  static const _channel = MethodChannel('com.xykw.nature_sound/media_composer');

  @override
  Future<void> compose({
    required String videoPath,
    required String musicPath,
    required String naturePath,
    required String narrationPath,
    required String outputPath,
  }) async {
    await _channel.invokeMethod<void>('compose', {
      'video_path': videoPath,
      'music_path': musicPath,
      'nature_path': naturePath,
      'narration_path': narrationPath,
      'output_path': outputPath,
    });
  }
}
