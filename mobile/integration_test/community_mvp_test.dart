import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nature_sound_detective/features/community/soundscape_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('community soundscape reaches the local API on Android', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: SoundscapePage(recordsLoader: () async => const []),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('共听杭州'), findsOneWidget);
    expect(find.textContaining('城市声景暂时没有连上'), findsNothing);
    expect(find.byKey(const Key('soundscape-area-xihu')), findsOneWidget);

    await tester.tap(find.byKey(const Key('soundscape-area-xihu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('publish-community-sound')));
    await tester.pumpAndSettle();

    expect(find.text('自然册里还没有声音'), findsOneWidget);
    expect(find.textContaining('先完成一次录音和调查'), findsOneWidget);
  });
}
