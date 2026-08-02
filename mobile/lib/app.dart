import 'package:flutter/material.dart';
import 'package:nature_sound_detective/features/capture/capture_page.dart';

class NatureSoundApp extends StatelessWidget {
  const NatureSoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2D6A4F);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '自然声探员',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F4EC),
        useMaterial3: true,
      ),
      home: const CapturePage(),
    );
  }
}
