import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/inference/recording_analyzer.dart';
import 'package:nature_sound_detective/features/capture/capture_page.dart';

class NatureSoundApp extends StatelessWidget {
  const NatureSoundApp({super.key, this.analyzer});

  final RecordingAnalyzer? analyzer;

  @override
  Widget build(BuildContext context) {
    const forest = Color(0xFF174936);
    const ink = Color(0xFF17251F);
    const ivory = Color(0xFFF8F5EC);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '自然声探员',
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: forest,
              brightness: Brightness.light,
              surface: ivory,
            ).copyWith(
              primary: forest,
              onPrimary: Colors.white,
              onSurface: ink,
              outline: const Color(0xFFB9B7AB),
            ),
        scaffoldBackgroundColor: ivory,
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: ink,
            fontSize: 31,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
          ),
          titleLarge: TextStyle(
            color: ink,
            fontSize: 20,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(
            color: Color(0xFF66716B),
            fontSize: 16,
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            color: Color(0xFF66716B),
            fontSize: 14,
            height: 1.45,
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Color(0xEFFFFFFA),
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            side: const BorderSide(color: Color(0xFFD5D2C6)),
          ),
        ),
        useMaterial3: true,
      ),
      home: CapturePage(analyzer: analyzer),
    );
  }
}
