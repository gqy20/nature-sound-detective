import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/models/exploration_feedback.dart';
import 'package:nature_sound_detective/features/result/detection_results.dart';

void main() {
  testWidgets('shows ranked confidence without calling it accuracy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DetectionResults(
            detections: [
              SoundDetection(
                categoryId: 'bird',
                nameZh: '鸟类鸣叫',
                confidence: 0.72,
                model: 'birdnet-acoustic-2.4-fp16',
                specificSpecies: SpeciesCandidate(
                  nameZh: '乌鸫',
                  scientificName: 'Turdus mandarinus',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('乌鸫'), findsOneWidget);
    expect(find.text('BirdNET'), findsNothing);
    expect(find.text('72%'), findsOneWidget);
    expect(find.text('模型置信度'), findsNothing);
    expect(find.text('准确率'), findsNothing);
    expect(find.textContaining('分数不是准确率'), findsNothing);
  });

  testWidgets('collects an explicit local review decision', (tester) async {
    ExplorationFeedback? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetectionResults(
            detections: const [
              SoundDetection(
                categoryId: 'frog',
                nameZh: '蛙类鸣叫',
                confidence: 0.8,
                model: 'hangzhou-nonbird-0.2.0',
                specificSpecies: SpeciesCandidate(
                  nameZh: '布氏泛树蛙',
                  taxonomyId: 'polypedates_braueri',
                ),
              ),
            ],
            onFeedback: (value) => submitted = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('不像'));
    await tester.pump();
    await tester.tap(find.text('保存反馈'));
    await tester.pump();
    expect(submitted?.decision, FeedbackDecision.wrong);
    expect(find.text('本地声学模型'), findsNothing);
    expect(find.textContaining('等待人工复核'), findsOneWidget);
  });

  testWidgets('shows combined evidence without duplicate model cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DetectionResults(
            detections: [
              SoundDetection(
                categoryId: 'insect',
                nameZh: '昆虫鸣叫',
                confidence: 0.72,
                model: 'challenge-nonbird',
                supportingModels: ['challenge-nonbird', 'yamnet-tflite-1'],
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('同时听到：昆虫鸣叫'), findsOneWidget);
    expect(find.text('本地声学模型 + YAMNet'), findsNothing);
  });

  testWidgets('labels a tentative species as a weak guess', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DetectionResults(
            detections: [
              SoundDetection(
                categoryId: 'bird',
                nameZh: '鸟类鸣叫',
                confidence: 0.16,
                model: 'birdnet-acoustic-2.4-fp16',
                supportingModels: ['birdnet-acoustic-2.4-fp16', 'yamnet'],
                tentative: true,
                specificSpecies: SpeciesCandidate(
                  nameZh: '乌鸫',
                  scientificName: 'Turdus mandarinus',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('较弱猜想'), findsOneWidget);
    expect(find.text('16%'), findsOneWidget);
    expect(find.text('乌鸫'), findsOneWidget);
  });

  testWidgets('opens a species clue from a ranked candidate', (tester) async {
    SoundDetection? tapped;
    int? tappedRank;
    const detection = SoundDetection(
      categoryId: 'bird',
      nameZh: '鸟类鸣叫',
      confidence: 0.62,
      model: 'birdnet',
      specificSpecies: SpeciesCandidate(
        nameZh: '乌鸫',
        scientificName: 'Turdus mandarinus',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetectionResults(
            detections: const [detection],
            onDetectionTap: (value, rank) {
              tapped = value;
              tappedRank = rank;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('乌鸫'));
    expect(tapped, same(detection));
    expect(tappedRank, 1);
  });
}
