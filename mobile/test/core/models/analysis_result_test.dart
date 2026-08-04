import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/models/analysis_result.dart';

void main() {
  test('round-trips the shared analysis contract', () {
    final result = AnalysisResult.fromJson({
      'recording_id': 'rec_001',
      'source': 'mobile',
      'platform': 'android',
      'contract_version': '1.0',
      'audio_quality': {'usable': true, 'warnings': <String>[], 'rms': 0.12},
      'detections': [
        {
          'category_id': 'frog',
          'name_zh': '蛙类鸣叫',
          'confidence': 0.82,
          'model': 'yamnet-local-head-v1',
          'supporting_models': ['yamnet-local-head-v1', 'hangzhou-nonbird'],
          'tentative': true,
          'intervals': [
            {'start': 2.4, 'end': 7.2},
          ],
          'specific_species': null,
        },
      ],
      'unknown': false,
      'requires_confirmation': true,
      'confirmed_by_user': false,
    });

    expect(result.platform, ClientPlatform.android);
    expect(result.audioQuality.usable, isTrue);
    expect(result.detections.single.nameZh, '蛙类鸣叫');
    expect(result.detections.single.intervals.single.startSeconds, 2.4);
    expect(result.detections.single.evidenceModels, hasLength(2));
    expect(result.detections.single.tentative, isTrue);
    expect((result.toJson()['detections'] as List).single['tentative'], isTrue);
    expect(result.toJson()['recording_id'], 'rec_001');
  });

  test('uses safe defaults for incomplete server data', () {
    final result = AnalysisResult.fromJson({'recording_id': 'rec_bad'});

    expect(result.audioQuality.usable, isFalse);
    expect(result.detections, isEmpty);
    expect(result.requiresConfirmation, isTrue);
  });
}
