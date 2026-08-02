import 'dart:io';
import 'dart:typed_data';

import 'package:nature_sound_detective/core/inference/audio_inference.dart';

class WavPcmReader {
  const WavPcmReader();

  Future<AudioInferenceInput> read({
    required String recordingId,
    required String path,
  }) async {
    final bytes = await File(path).readAsBytes();
    if (bytes.length < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('文件不是有效的 WAV 录音。');
    }
    final data = ByteData.sublistView(bytes);
    int? sampleRate;
    int? channelCount;
    int? bitsPerSample;
    int? pcmOffset;
    int? pcmEnd;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = data.getUint32(offset + 4, Endian.little);
      final contentOffset = offset + 8;
      if (contentOffset + size > bytes.length) break;
      if (id == 'fmt ' && size >= 16) {
        if (data.getUint16(contentOffset, Endian.little) != 1) {
          throw const FormatException('只支持 PCM WAV 录音。');
        }
        channelCount = data.getUint16(contentOffset + 2, Endian.little);
        sampleRate = data.getUint32(contentOffset + 4, Endian.little);
        bitsPerSample = data.getUint16(contentOffset + 14, Endian.little);
      } else if (id == 'data') {
        pcmOffset = contentOffset;
        pcmEnd = contentOffset + size;
      }
      offset = contentOffset + size + (size.isOdd ? 1 : 0);
    }
    if (sampleRate == null ||
        channelCount == null ||
        bitsPerSample != 16 ||
        pcmOffset == null ||
        pcmEnd == null) {
      throw const FormatException('WAV 录音缺少受支持的 PCM 数据。');
    }
    return AudioInferenceInput(
      recordingId: recordingId,
      pcm16le: Uint8List.sublistView(bytes, pcmOffset, pcmEnd),
      sampleRate: sampleRate,
      channelCount: channelCount,
    );
  }
}
