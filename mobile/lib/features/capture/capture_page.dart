import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/audio/audio_playback.dart';
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/method_channel_audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/wav_quality_analyzer.dart';
import 'package:nature_sound_detective/core/inference/recording_analyzer.dart';
import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({
    super.key,
    this.recorder,
    this.qualityAnalyzer,
    this.playback,
    this.analyzer,
  });

  final AudioRecorder? recorder;
  final AudioQualityAnalyzer? qualityAnalyzer;
  final AudioPlayback? playback;
  final RecordingAnalyzer? analyzer;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  static const _maxDuration = Duration(seconds: 20);

  late final AudioRecorder _recorder;
  late final AudioQualityAnalyzer _qualityAnalyzer;
  late final AudioPlayback _playback;
  late final RecordingAnalyzer _analyzer;
  StreamSubscription<bool>? _playbackSubscription;
  Timer? _timer;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  bool _busy = false;
  RecordedAudio? _recording;
  AudioQuality? _quality;
  bool _isPlaying = false;
  bool _analyzing = false;
  bool _hasAnalyzed = false;
  List<SoundDetection> _detections = const [];
  String? _error;

  bool get _isRecording => _startedAt != null;

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder ?? MethodChannelAudioRecorder();
    _qualityAnalyzer = widget.qualityAnalyzer ?? const WavQualityAnalyzer();
    _playback = widget.playback ?? DeviceFileAudioPlayback();
    _analyzer = widget.analyzer ?? LocalRecordingAnalyzer();
    _playbackSubscription = _playback.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_playbackSubscription?.cancel());
    unawaited(_playback.dispose());
    unawaited(_analyzer.dispose());
    if (_isRecording) {
      unawaited(_recorder.cancel());
    }
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_busy) return;
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    setState(() {
      _busy = true;
      _recording = null;
      _quality = null;
      _detections = const [];
      _hasAnalyzed = false;
      _error = null;
    });
    try {
      final permitted =
          await _recorder.hasPermission() ||
          await _recorder.requestPermission();
      if (!permitted) {
        throw PlatformException(
          code: 'permission_denied',
          message: '需要麦克风权限才能记录自然声音。',
        );
      }
      final session = await _recorder.start(maxDuration: _maxDuration);
      if (!mounted) return;
      setState(() {
        _startedAt = session.startedAt;
        _elapsed = Duration.zero;
      });
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted || _startedAt == null) return;
        final elapsed = DateTime.now().difference(_startedAt!);
        setState(
          () => _elapsed = elapsed > _maxDuration ? _maxDuration : elapsed,
        );
        if (elapsed >= _maxDuration && !_busy) {
          unawaited(_stopRecording());
        }
      });
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? '无法开始录音。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopRecording() async {
    if (_busy || !_isRecording) return;
    setState(() => _busy = true);
    _timer?.cancel();
    try {
      final recording = await _recorder.stop();
      final quality = await _qualityAnalyzer.analyze(recording.path);
      if (!mounted) return;
      setState(() {
        _recording = recording;
        _quality = quality;
        _startedAt = null;
        _elapsed = recording.duration;
      });
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message ?? '录音保存失败，请再试一次。';
          _startedAt = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePlayback() async {
    final recording = _recording;
    if (recording == null) return;
    if (_isPlaying) {
      await _playback.stop();
    } else {
      await _playback.play(recording.path);
    }
  }

  Future<void> _analyzeRecording() async {
    final recording = _recording;
    if (recording == null || _analyzing) return;
    setState(() {
      _analyzing = true;
      _error = null;
      _detections = const [];
      _hasAnalyzed = false;
    });
    try {
      final detections = await _analyzer.analyze(recording);
      if (mounted) {
        setState(() {
          _detections = detections;
          _hasAnalyzed = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '本地声音模型加载失败，请稍后再试。');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (_elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    return Scaffold(
      appBar: AppBar(title: const Text('自然声探员')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '把耳朵借给大自然',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                '录下杭州身边的声音，寻找鸟、青蛙和昆虫的线索。',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const Spacer(),
              Text(
                _isRecording ? '$seconds 秒' : '最长 20 秒',
                key: const Key('recording-duration'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('record-button'),
                onPressed: _busy ? null : _toggleRecording,
                icon: Icon(
                  _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                ),
                label: Text(_isRecording ? '结束录音' : '开始录音'),
              ),
              if (_recording case final recording?) ...[
                const SizedBox(height: 16),
                Text(
                  '已保存 ${recording.duration.inSeconds} 秒 WAV 录音',
                  key: const Key('recording-saved'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('playback-button'),
                  onPressed: _togglePlayback,
                  icon: Icon(
                    _isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(_isPlaying ? '停止播放' : '回放原声'),
                ),
              ],
              if (_quality case final quality?) ...[
                const SizedBox(height: 12),
                Text(
                  quality.usable ? '录音质量可用于识别' : '建议重新录制',
                  key: const Key('quality-status'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: quality.usable
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                for (final warning in quality.warnings)
                  Text('· $warning', textAlign: TextAlign.center),
                if (quality.usable) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    key: const Key('analyze-button'),
                    onPressed: _analyzing ? null : _analyzeRecording,
                    icon: _analyzing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.graphic_eq_rounded),
                    label: Text(_analyzing ? '正在本地识别' : '识别这段声音'),
                  ),
                ],
              ],
              if (_detections.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '听到的声音线索',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final detection in _detections)
                      Chip(
                        label: Text(
                          '${detection.specificSpecies?.nameZh ?? detection.nameZh} ${(_displayScore(detection.confidence) * 100).round()}%',
                        ),
                      ),
                  ],
                ),
              ] else if (_hasAnalyzed && !_analyzing) ...[
                const SizedBox(height: 16),
                const Text(
                  '暂时没有找到足够清楚的声音线索，可以换个位置再录一次。',
                  key: Key('unknown-result'),
                  textAlign: TextAlign.center,
                ),
              ] else if (!_analyzing &&
                  _quality?.usable == true &&
                  _recording != null) ...[
                const SizedBox(height: 8),
                const Text('模型会返回声音线索，不把分数当作准确率。', textAlign: TextAlign.center),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 16),
                Text(
                  error,
                  key: const Key('recording-error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              const Text('靠近目标声音，避开说话声和车辆。', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  double _displayScore(double value) => value.clamp(0, 0.99);
}
