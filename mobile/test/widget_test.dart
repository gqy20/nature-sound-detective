import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/app.dart';

void main() {
  testWidgets('shows the Android-first capture shell', (tester) async {
    await tester.pumpWidget(const NatureSoundApp());

    expect(find.text('自然声探员'), findsOneWidget);
    expect(find.text('把耳朵借给大自然'), findsOneWidget);
    expect(find.byKey(const Key('record-button')), findsOneWidget);
  });
}
