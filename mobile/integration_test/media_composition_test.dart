import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nature_sound_detective/core/media/media_composer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('composes video, music, nature sound and narration on Android', (
    tester,
  ) async {
    const fixtureDirectory = String.fromEnvironment('MEDIA_FIXTURE_DIR');
    expect(fixtureDirectory, isNotEmpty);
    final output = File('$fixtureDirectory/composed.mp4');
    if (await output.exists()) await output.delete();

    await const AndroidMediaComposer().compose(
      videoPath: '$fixtureDirectory/video.mp4',
      musicPath: '$fixtureDirectory/music.mp3',
      naturePath: '$fixtureDirectory/nature.wav',
      narrationPath: '$fixtureDirectory/narration.mp3',
      outputPath: output.path,
    );

    expect(await output.exists(), isTrue);
    expect(await output.length(), greaterThan(1024));
  });
}
