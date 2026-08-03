import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/models/exploration_feedback.dart';
import 'package:nature_sound_detective/core/storage/exploration_store.dart';

void main() {
  test('persists audio and structured exploration metadata', () async {
    final root = await Directory.systemTemp.createTemp('xykw_store_test_');
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}${Platform.pathSeparator}source.wav');
    await source.writeAsBytes([1, 2, 3, 4]);
    final store = FileExplorationStore(rootProvider: () async => root);

    final saved = await store.save(
      recording: RecordedAudio(
        id: 'rec_1',
        path: source.path,
        duration: const Duration(seconds: 4),
        sampleRate: 48000,
        channelCount: 1,
        byteLength: 4,
      ),
      quality: const AudioQuality(usable: true),
      detections: const [
        SoundDetection(
          categoryId: 'frog',
          nameZh: '蛙类鸣叫',
          confidence: 0.8,
          model: 'yamnet-tflite-1',
        ),
      ],
      location: '杭州植物园',
    );

    expect(await File(saved.audioPath).exists(), isTrue);
    expect((await store.list()).single.detections.single.categoryId, 'frog');
    await store.setConfirmed('rec_1', true);
    expect((await store.list()).single.confirmedByUser, isTrue);
    await store.setFeedback(
      'rec_1',
      const ExplorationFeedback(
        decision: FeedbackDecision.wrong,
        correctedTaxonId: 'other_frog',
        consentToRetainAudio: true,
      ),
    );
    final updated = (await store.list()).single;
    expect(updated.feedback?.correctedTaxonId, 'other_frog');
    final exported = await store.exportReviewPackage(root);
    expect(
      await File(
        '${exported.path}${Platform.pathSeparator}feedback.jsonl',
      ).readAsString(),
      contains('other_frog'),
    );
    await store.delete('rec_1');
    expect(await store.list(), isEmpty);
  });

  test('rejects path traversal in record ids', () async {
    final root = await Directory.systemTemp.createTemp('xykw_store_test_');
    addTearDown(() => root.delete(recursive: true));
    final store = FileExplorationStore(rootProvider: () async => root);

    expect(() => store.delete('../outside'), throwsA(isA<FormatException>()));
  });
}
