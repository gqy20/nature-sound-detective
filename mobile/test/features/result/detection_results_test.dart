import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/features/result/detection_results.dart';

void main() {
  testWidgets('shows explainable clues without calling scores accuracy', (
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
    expect(find.text('BirdNET'), findsOneWidget);
    expect(find.text('线索较强'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('准确率'), findsNothing);
  });
}
