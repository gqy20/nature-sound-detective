import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/features/species/species_detail_page.dart';

void main() {
  testWidgets('field checks can be selected and cleared', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SpeciesDetailPage(
          detection: SoundDetection(
            categoryId: 'bird',
            nameZh: '鸟类',
            confidence: 0.72,
            model: 'test',
            specificSpecies: SpeciesCandidate(
              nameZh: '白头鹎',
              scientificName: 'Pycnonotus sinensis',
            ),
          ),
        ),
      ),
    );

    expect(find.text('看到相符的线索，就点一下'), findsOneWidget);

    await tester.tap(find.text('时间'));
    await tester.pumpAndSettle();
    expect(find.text('已核对 1 项'), findsOneWidget);

    await tester.tap(find.text('位置'));
    await tester.tap(find.text('外形'));
    await tester.pumpAndSettle();
    expect(find.text('全都对上啦！'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(3));

    await tester.tap(find.text('外形'));
    await tester.pumpAndSettle();
    expect(find.text('已核对 2 项'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
  });
}
