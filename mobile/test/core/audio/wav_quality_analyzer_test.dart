import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/audio/wav_quality_analyzer.dart';

void main() {
  test('accepts a clear multi-second mono recording', () async {
    final directory = await Directory.systemTemp.createTemp('xykw_wav_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}clear.wav');
    await file.writeAsBytes(_sineWav(seconds: 4, amplitude: 0.2));

    final quality = await const WavQualityAnalyzer().analyze(file.path);

    expect(quality.usable, isTrue);
    expect(quality.rms, greaterThan(0.1));
    expect(quality.clippedRatio, 0);
    expect(quality.activeWindowCount, greaterThan(0));
  });

  test('rejects an almost silent recording', () async {
    final directory = await Directory.systemTemp.createTemp('xykw_wav_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}silent.wav');
    await file.writeAsBytes(_sineWav(seconds: 2, amplitude: 0.001));

    final quality = await const WavQualityAnalyzer().analyze(file.path);

    expect(quality.usable, isFalse);
    expect(quality.warnings, isNotEmpty);
  });

  test('accepts a short clear call inside a mostly quiet recording', () async {
    final directory = await Directory.systemTemp.createTemp('xykw_wav_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}sparse.wav');
    await file.writeAsBytes(
      _sparseSineWav(seconds: 20, callStart: 8, callSeconds: 1),
    );

    final quality = await const WavQualityAnalyzer().analyze(file.path);

    expect(quality.silentRatio, greaterThan(0.9));
    expect(quality.bestWindowRms, greaterThan(0.01));
    expect(quality.activeWindowCount, greaterThan(0));
    expect(quality.usable, isTrue);
  });

  test('keeps a quiet but measurable call available for analysis', () async {
    final directory = await Directory.systemTemp.createTemp('xykw_wav_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}distant.wav');
    await file.writeAsBytes(_sineWav(seconds: 3, amplitude: 0.0045));

    final quality = await const WavQualityAnalyzer().analyze(file.path);

    expect(quality.silentRatio, 1);
    expect(quality.bestWindowRms, greaterThan(0.003));
    expect(quality.usable, isTrue);
    expect(quality.warnings, contains('声音有些远，但仍可以尝试识别。'));
  });
}

Uint8List _sineWav({required int seconds, required double amplitude}) {
  const sampleRate = 16000;
  final samples = sampleRate * seconds;
  final dataBytes = samples * 2;
  final bytes = Uint8List(44 + dataBytes);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, 36 + dataBytes, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  data.setUint32(40, dataBytes, Endian.little);
  for (var index = 0; index < samples; index++) {
    final sample = math.sin(2 * math.pi * 440 * index / sampleRate) * amplitude;
    data.setInt16(44 + index * 2, (sample * 32767).round(), Endian.little);
  }
  return bytes;
}

Uint8List _sparseSineWav({
  required int seconds,
  required int callStart,
  required int callSeconds,
}) {
  const sampleRate = 16000;
  final bytes = _sineWav(seconds: seconds, amplitude: 0);
  final data = ByteData.sublistView(bytes);
  final start = callStart * sampleRate;
  final end = (callStart + callSeconds) * sampleRate;
  for (var index = start; index < end; index++) {
    final sample = math.sin(2 * math.pi * 440 * index / sampleRate) * 0.2;
    data.setInt16(44 + index * 2, (sample * 32767).round(), Endian.little);
  }
  return bytes;
}
