import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/audio/wav_pcm_reader.dart';

void main() {
  test('extracts PCM metadata and skips the WAV header', () async {
    final directory = await Directory.systemTemp.createTemp('xykw_pcm_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}sample.wav');
    await file.writeAsBytes(_wav());

    final input = await const WavPcmReader().read(
      recordingId: 'rec_1',
      path: file.path,
    );

    expect(input.sampleRate, 48000);
    expect(input.channelCount, 1);
    expect(input.pcm16le, hasLength(4));
  });
}

Uint8List _wav() {
  final bytes = Uint8List(48);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, 40, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 48000, Endian.little);
  data.setUint32(28, 96000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  data.setUint32(40, 4, Endian.little);
  data.setInt16(44, 100, Endian.little);
  data.setInt16(46, -100, Endian.little);
  return bytes;
}
