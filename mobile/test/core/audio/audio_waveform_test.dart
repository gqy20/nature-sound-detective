import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/audio/audio_waveform.dart';
import 'package:nature_sound_detective/features/capture/sound_waveform.dart';

void main() {
  test('extracts a normalized envelope from real PCM samples', () async {
    final directory = await Directory.systemTemp.createTemp('waveform-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}levels.wav');
    await file.writeAsBytes(_wavWithTwoLevels());

    final waveform = await AudioWaveformExtractor.extract(
      file.path,
      barCount: 8,
    );

    expect(waveform, hasLength(8));
    expect(waveform.first, lessThan(waveform.last));
    expect(waveform.every((value) => value >= 0 && value <= 1), isTrue);
  });

  testWidgets('renders live ring and analysis waveform as isolated painters', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Column(
            children: [
              SizedBox.square(
                dimension: 180,
                child: ListeningWaveRing(
                  levels: [0.002, 0.01, 0.025],
                  rms: 0.02,
                  peak: 0.12,
                  active: true,
                ),
              ),
              AudioWaveformView(
                samples: [0.1, 0.8, 0.3, 1],
                active: true,
                progress: 0.5,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('live-audio-wave-ring')), findsOneWidget);
    expect(find.byKey(const Key('recording-waveform')), findsOneWidget);
    expect(find.byType(RepaintBoundary), findsWidgets);
  });
}

Uint8List _wavWithTwoLevels() {
  const sampleRate = 8000;
  const frameCount = 800;
  const dataLength = frameCount * 2;
  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);
  _ascii(bytes, 0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  _ascii(bytes, 8, 'WAVE');
  _ascii(bytes, 12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  _ascii(bytes, 36, 'data');
  data.setUint32(40, dataLength, Endian.little);
  for (var frame = 0; frame < frameCount; frame++) {
    final amplitude = frame < frameCount ~/ 2 ? 1200 : 18000;
    data.setInt16(
      44 + frame * 2,
      frame.isEven ? amplitude : -amplitude,
      Endian.little,
    );
  }
  return bytes;
}

void _ascii(Uint8List bytes, int offset, String value) {
  for (var index = 0; index < value.length; index++) {
    bytes[offset + index] = value.codeUnitAt(index);
  }
}
