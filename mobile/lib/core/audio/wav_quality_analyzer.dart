import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:nature_sound_detective/core/models/audio_quality.dart';

abstract interface class AudioQualityAnalyzer {
  Future<AudioQuality> analyze(String path);
}

class WavQualityAnalyzer implements AudioQualityAnalyzer {
  const WavQualityAnalyzer();

  @override
  Future<AudioQuality> analyze(String path) =>
      Isolate.run(() => _analyze(path));

  static Future<AudioQuality> _analyze(String path) async {
    final bytes = await File(path).readAsBytes();
    final wav = _PcmWav.parse(bytes);
    if (wav.bitsPerSample != 16 || wav.channelCount != 1) {
      return const AudioQuality(
        usable: false,
        warnings: ['暂时只支持 16-bit 单声道 WAV 录音。'],
      );
    }

    final data = ByteData.sublistView(bytes, wav.dataOffset, wav.dataEnd);
    final sampleCount = data.lengthInBytes ~/ 2;
    if (sampleCount == 0) {
      return const AudioQuality(usable: false, warnings: ['没有检测到声音，请重新录制。']);
    }

    var sumSquares = 0.0;
    var peak = 0.0;
    var silentSamples = 0;
    var clippedSamples = 0;
    for (var index = 0; index < sampleCount; index++) {
      final normalized = data.getInt16(index * 2, Endian.little) / 32768.0;
      final absolute = normalized.abs();
      sumSquares += normalized * normalized;
      peak = math.max(peak, absolute);
      if (absolute < 0.01) silentSamples++;
      if (absolute >= 0.98) clippedSamples++;
    }

    final rms = math.sqrt(sumSquares / sampleCount);
    final silentRatio = silentSamples / sampleCount;
    final clippedRatio = clippedSamples / sampleCount;
    final durationSeconds = sampleCount / wav.sampleRate;
    final windowSamples = math.max(wav.sampleRate * 3, 1);
    final hopSamples = math.max(windowSamples ~/ 2, 1);
    var bestWindowRms = 0.0;
    var activeWindowCount = 0;
    var totalWindowCount = 0;
    for (var start = 0; start < sampleCount; start += hopSamples) {
      final end = math.min(start + windowSamples, sampleCount);
      if (end <= start) break;
      var windowSquares = 0.0;
      for (var index = start; index < end; index++) {
        final normalized = data.getInt16(index * 2, Endian.little) / 32768.0;
        windowSquares += normalized * normalized;
      }
      final count = end - start;
      final windowRms = math.sqrt(windowSquares / count);
      bestWindowRms = math.max(bestWindowRms, windowRms);
      if (windowRms >= 0.003) {
        activeWindowCount++;
      }
      totalWindowCount++;
      if (end == sampleCount) break;
    }
    final usable = durationSeconds >= 1 && activeWindowCount > 0;
    final warnings = <String>[];
    if (durationSeconds < 1) {
      warnings.add('录音不足 1 秒，请多录几次完整叫声。');
    } else if (durationSeconds < 3) {
      warnings.add('录音少于 3 秒，多录几次叫声会更容易识别。');
    }
    if (bestWindowRms < 0.012) {
      warnings.add(usable ? '声音有些远，但仍可以尝试识别。' : '没有检测到清晰声音，请检查麦克风后再试。');
    } else if (activeWindowCount < math.max(2, totalWindowCount ~/ 4)) {
      warnings.add('声音只在少数片段出现，识别会重点分析这些片段。');
    }
    if (clippedRatio > 0.025) {
      warnings.add('声音过强并出现失真，请离声源远一点。');
    }
    if (!usable && warnings.isEmpty) {
      warnings.add('这段录音暂时不适合识别，请重新录制。');
    }
    return AudioQuality(
      usable: usable,
      warnings: warnings,
      rms: rms,
      peak: peak,
      silentRatio: silentRatio,
      clippedRatio: clippedRatio,
      bestWindowRms: bestWindowRms,
      activeWindowCount: activeWindowCount,
      totalWindowCount: totalWindowCount,
    );
  }
}

class _PcmWav {
  const _PcmWav({
    required this.sampleRate,
    required this.channelCount,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataEnd,
  });

  factory _PcmWav.parse(Uint8List bytes) {
    if (bytes.length < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('文件不是有效的 WAV 录音。');
    }
    final data = ByteData.sublistView(bytes);
    int? sampleRate;
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
        sampleRate = data.getUint32(contentOffset + 4, Endian.little);
        bitsPerSample = data.getUint16(contentOffset + 14, Endian.little);
      } else if (id == 'data') {
        dataOffset = contentOffset;
        dataEnd = contentOffset + size;
      }
      offset = contentOffset + size + (size.isOdd ? 1 : 0);
    }
    if (sampleRate == null ||
        channelCount == null ||
        bitsPerSample == null ||
        dataOffset == null ||
        dataEnd == null) {
      throw const FormatException('WAV 录音缺少必要的数据块。');
    }
    return _PcmWav(
      sampleRate: sampleRate,
      channelCount: channelCount,
      bitsPerSample: bitsPerSample,
      dataOffset: dataOffset,
      dataEnd: dataEnd,
    );
  }

  final int sampleRate;
  final int channelCount;
  final int bitsPerSample;
  final int dataOffset;
  final int dataEnd;
}
