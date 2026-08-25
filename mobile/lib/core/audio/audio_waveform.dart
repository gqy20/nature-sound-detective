import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

class AudioWaveformExtractor {
  const AudioWaveformExtractor._();

  static Future<List<double>> extract(String path, {int barCount = 64}) async {
    if (!await File(path).exists()) return const [];
    return Isolate.run(() => _extract(path, barCount));
  }

  static List<double> _extract(String path, int barCount) {
    if (barCount < 1) return const [];
    final bytes = File(path).readAsBytesSync();
    final wav = _WaveformWav.parse(bytes);
    if (wav.bitsPerSample != 16) {
      throw const FormatException('波形暂时只支持 16-bit PCM WAV。');
    }
    final data = ByteData.sublistView(bytes, wav.dataOffset, wav.dataEnd);
    final frameSize = wav.channelCount * 2;
    final frameCount = data.lengthInBytes ~/ frameSize;
    if (frameCount == 0) return const [];

    final actualBars = math.min(barCount, frameCount);
    final raw = List<double>.filled(actualBars, 0);
    for (var bar = 0; bar < actualBars; bar++) {
      final start = bar * frameCount ~/ actualBars;
      final end = math.max((bar + 1) * frameCount ~/ actualBars, start + 1);
      var squares = 0.0;
      var samples = 0;
      for (var frame = start; frame < end; frame++) {
        for (var channel = 0; channel < wav.channelCount; channel++) {
          final offset = frame * frameSize + channel * 2;
          final value = data.getInt16(offset, Endian.little) / 32768.0;
          squares += value * value;
          samples++;
        }
      }
      raw[bar] = math.sqrt(squares / math.max(samples, 1));
    }

    final sorted = [...raw]..sort();
    final reference = sorted[((sorted.length - 1) * 0.9).round()];
    final scale = math.max(reference, 0.0005);
    return List<double>.unmodifiable(
      raw.map((value) => math.sqrt((value / scale).clamp(0.0, 1.0))),
    );
  }
}

class _WaveformWav {
  const _WaveformWav({
    required this.channelCount,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataEnd,
  });

  factory _WaveformWav.parse(Uint8List bytes) {
    if (bytes.length < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('文件不是有效的 WAV 录音。');
    }
    final data = ByteData.sublistView(bytes);
    int? channelCount;
    int? bitsPerSample;
    int? dataOffset;
    int? dataEnd;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = data.getUint32(offset + 4, Endian.little);
      final contentOffset = offset + 8;
      if (contentOffset + size > bytes.length) break;
      if (id == 'fmt ' && size >= 16) {
        final format = data.getUint16(contentOffset, Endian.little);
        if (format != 1) throw const FormatException('只支持 PCM WAV 录音。');
        channelCount = data.getUint16(contentOffset + 2, Endian.little);
        bitsPerSample = data.getUint16(contentOffset + 14, Endian.little);
      } else if (id == 'data') {
        dataOffset = contentOffset;
        dataEnd = contentOffset + size;
      }
      offset = contentOffset + size + (size.isOdd ? 1 : 0);
    }
    if (channelCount == null ||
        channelCount < 1 ||
        bitsPerSample == null ||
        dataOffset == null ||
        dataEnd == null) {
      throw const FormatException('WAV 录音缺少必要的数据块。');
    }
    return _WaveformWav(
      channelCount: channelCount,
      bitsPerSample: bitsPerSample,
      dataOffset: dataOffset,
      dataEnd: dataEnd,
    );
  }

  final int channelCount;
  final int bitsPerSample;
  final int dataOffset;
  final int dataEnd;
}
