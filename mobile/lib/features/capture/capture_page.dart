import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/audio/audio_playback.dart';
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/method_channel_audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/wav_quality_analyzer.dart';
import 'package:nature_sound_detective/core/inference/recording_analyzer.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/network/cloud_content_service.dart';
import 'package:nature_sound_detective/core/storage/exploration_store.dart';
import 'package:nature_sound_detective/features/diagnostics/diagnostics_page.dart';
import 'package:nature_sound_detective/features/result/detection_results.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({
    super.key,
    this.recorder,
    this.qualityAnalyzer,
    this.playback,
    this.analyzer,
    this.store,
    this.cloudService,
  });

  final AudioRecorder? recorder;
  final AudioQualityAnalyzer? qualityAnalyzer;
  final AudioPlayback? playback;
  final RecordingAnalyzer? analyzer;
  final ExplorationStore? store;
  final CloudContentService? cloudService;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  static const _maxDuration = Duration(seconds: 20);

  late final AudioRecorder _recorder;
  late final AudioQualityAnalyzer _qualityAnalyzer;
  late final AudioPlayback _playback;
  late final RecordingAnalyzer _analyzer;
  late final ExplorationStore _store;
  late final CloudContentService _cloudService;
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
  bool _saving = false;
  bool _saved = false;
  bool _enriching = false;
  CloudSoundCard? _cloudCard;
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
    _store = widget.store ?? FileExplorationStore();
    _cloudService = widget.cloudService ?? HttpCloudContentService();
    _playbackSubscription = _playback.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    AppLog.info('capture', 'page_ready');
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
      _saved = false;
      _cloudCard = null;
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
      AppLog.info(
        'audio',
        'recording_started',
        traceId: session.id,
        fields: {'max_duration_ms': _maxDuration.inMilliseconds},
      );
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
    } on PlatformException catch (error, stackTrace) {
      AppLog.warning(
        'audio',
        'recording_start_failed',
        fields: {'platform_code': error.code},
        error: error,
        stackTrace: stackTrace,
      );
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
      AppLog.info(
        'audio',
        'recording_completed',
        traceId: recording.id,
        fields: {
          'duration_ms': recording.duration.inMilliseconds,
          'sample_rate': recording.sampleRate,
          'channels': recording.channelCount,
          'byte_length': recording.byteLength,
          'quality_usable': quality.usable,
          'quality_issue_count': quality.warnings.length,
        },
      );
      if (!mounted) return;
      setState(() {
        _recording = recording;
        _quality = quality;
        _startedAt = null;
        _elapsed = recording.duration;
      });
    } on PlatformException catch (error, stackTrace) {
      AppLog.error(
        'audio',
        'recording_stop_failed',
        fields: {'platform_code': error.code},
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _error = error.message ?? '录音保存失败，请再试一次。';
          _startedAt = null;
        });
      }
    } catch (error, stackTrace) {
      AppLog.error(
        'audio',
        'recording_processing_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _error = '录音文件处理失败，请再试一次。';
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
    try {
      if (_isPlaying) {
        await _playback.stop();
      } else {
        await _playback.play(recording.path);
      }
    } catch (error, stackTrace) {
      AppLog.warning(
        'audio',
        'playback_failed',
        traceId: recording.id,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = '暂时无法播放这段录音。');
    }
  }

  Future<void> _loadDebugDemo() async {
    if (_busy || !kDebugMode || _recorder is! MethodChannelAudioRecorder) {
      return;
    }
    setState(() {
      _busy = true;
      _recording = null;
      _quality = null;
      _detections = const [];
      _hasAnalyzed = false;
      _saved = false;
      _cloudCard = null;
      _error = null;
    });
    try {
      final recording = await _recorder.loadDebugDemo();
      final quality = await _qualityAnalyzer.analyze(recording.path);
      AppLog.info(
        'audio',
        'debug_demo_loaded',
        traceId: recording.id,
        fields: {
          'duration_ms': recording.duration.inMilliseconds,
          'sample_rate': recording.sampleRate,
          'channels': recording.channelCount,
          'byte_length': recording.byteLength,
          'quality_usable': quality.usable,
        },
      );
      if (!mounted) return;
      setState(() {
        _recording = recording;
        _quality = quality;
        _elapsed = recording.duration;
      });
    } on PlatformException catch (error, stackTrace) {
      AppLog.warning(
        'audio',
        'debug_demo_load_failed',
        fields: {'platform_code': error.code},
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _error = error.message ?? '无法载入示例声音。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
      AppLog.info(
        'inference',
        'analysis_presented',
        traceId: recording.id,
        fields: {'detection_count': detections.length},
      );
      if (mounted) {
        setState(() {
          _detections = detections;
          _hasAnalyzed = true;
        });
      }
    } catch (error, stackTrace) {
      AppLog.error(
        'inference',
        'analysis_failed',
        traceId: recording.id,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = '本地声音模型加载失败，请稍后再试。');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _saveExploration() async {
    final recording = _recording;
    final quality = _quality;
    if (recording == null || quality == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _store.save(
        recording: recording,
        quality: quality,
        detections: _detections,
        location: '杭州',
      );
      AppLog.info(
        'storage',
        'exploration_saved',
        traceId: recording.id,
        fields: {'detection_count': _detections.length},
      );
      if (mounted) setState(() => _saved = true);
    } catch (error, stackTrace) {
      AppLog.error(
        'storage',
        'exploration_save_failed',
        traceId: recording.id,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = '保存到声音册失败，请稍后再试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestCloudCard() async {
    final recording = _recording;
    if (recording == null || _enriching) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('生成儿童科普卡？'),
        content: const Text('这一步会把本次录音上传到云端并调用 AI。只有点击继续后才会产生网络请求。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    setState(() {
      _enriching = true;
      _error = null;
    });
    try {
      final card = await _cloudService.createCard(
        recording: recording,
        location: '杭州',
      );
      AppLog.info('cloud', 'card_presented', traceId: recording.id);
      if (mounted) setState(() => _cloudCard = card);
    } on CloudServiceException catch (error, stackTrace) {
      AppLog.warning(
        'cloud',
        'card_request_rejected',
        traceId: recording.id,
        fields: {'status_code': error.statusCode},
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = error.message);
    } catch (error, stackTrace) {
      AppLog.error(
        'cloud',
        'card_request_failed',
        traceId: recording.id,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = '科普卡生成失败，录音和本地结果仍已保留。');
    } finally {
      if (mounted) setState(() => _enriching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (_elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    return Scaffold(
      appBar: AppBar(
        title: const Text('自然声探员'),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 20),
            child: Center(child: Text('杭州')),
          ),
          IconButton(
            tooltip: '运行诊断',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DiagnosticsPage()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Text('把耳朵借给大自然', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              '录下身边的声音，寻找鸟、青蛙和昆虫的线索。',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 36),
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
              icon: Icon(_isRecording ? Icons.stop_rounded : Icons.mic_rounded),
              label: Text(_isRecording ? '结束录音' : '开始录音'),
            ),
            if (kDebugMode && _recorder is MethodChannelAudioRecorder) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('debug-demo-button'),
                onPressed: _busy || _isRecording ? null : _loadDebugDemo,
                icon: const Icon(Icons.science_outlined),
                label: const Text('载入演示声音'),
              ),
            ],
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
              const SizedBox(height: 28),
              DetectionResults(detections: _detections),
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
              const Text('识别在手机本地完成，模型分数只表示线索强弱。', textAlign: TextAlign.center),
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
            if (_hasAnalyzed) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('save-exploration-button'),
                onPressed: _saved || _saving ? null : _saveExploration,
                icon: Icon(
                  _saved ? Icons.check_rounded : Icons.bookmark_add_rounded,
                ),
                label: Text(_saved ? '已保存到声音册' : (_saving ? '正在保存' : '保存到声音册')),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('cloud-card-button'),
                onPressed: _enriching ? null : _requestCloudCard,
                icon: _enriching
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_stories_rounded),
                label: Text(_enriching ? '正在生成科普卡' : '生成儿童科普卡'),
              ),
            ],
            if (_cloudCard case final card?) ...[
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(card.explanation),
                      if (card.question.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('观察任务：${card.question}'),
                      ],
                      if (card.safetyNote.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('安全提示：${card.safetyNote}'),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text('靠近目标声音，避开说话声和车辆。', textAlign: TextAlign.center),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}
