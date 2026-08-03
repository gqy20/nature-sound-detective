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

  void _openDiagnostics() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DiagnosticsPage()));
  }

  Future<void> _showDebugActions() async {
    if (!kDebugMode) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFFFFDF7),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: const Text('运行诊断'),
                onTap: () {
                  Navigator.pop(context);
                  _openDiagnostics();
                },
              ),
              if (_recorder is MethodChannelAudioRecorder)
                ListTile(
                  key: const Key('debug-demo-button'),
                  enabled: !_busy && !_isRecording,
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('载入演示声音'),
                  onTap: _busy || _isRecording
                      ? null
                      : () {
                          Navigator.pop(context);
                          _loadDebugDemo();
                        },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (_elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    final theme = Theme.of(context);
    const forest = Color(0xFF174936);
    final progress = (_elapsed.inMilliseconds / _maxDuration.inMilliseconds)
        .clamp(0.0, 1.0);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/hangzhou_mist.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          const Positioned.fill(child: ColoredBox(color: Color(0x12FFFDF7))),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onLongPress: kDebugMode ? _showDebugActions : null,
                        child: Text(
                          '自然声探员',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 16,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onLongPress: kDebugMode ? _showDebugActions : null,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 17,
                            color: Color(0xFF52615A),
                          ),
                          SizedBox(width: 4),
                          Text(
                            '杭州',
                            style: TextStyle(
                              color: Color(0xFF52615A),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 102),
                Text(
                  '把耳朵借给大自然',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  _isRecording ? '正在听附近的声音' : '听听，谁在附近？',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 64),
                SizedBox(
                  height: 234,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        width: _isRecording ? 228 : 220,
                        height: _isRecording ? 228 : 220,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: forest.withValues(
                              alpha: _isRecording ? 0.18 : 0.09,
                            ),
                            width: 1,
                          ),
                        ),
                      ),
                      Container(
                        width: 198,
                        height: 198,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(
                            0xFFF1F0E7,
                          ).withValues(alpha: 0.82),
                          border: Border.all(
                            color: forest.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      SizedBox.square(
                        dimension: 198,
                        child: CircularProgressIndicator(
                          value: _isRecording ? progress : 0,
                          strokeWidth: 2,
                          color: forest.withValues(alpha: 0.55),
                          backgroundColor: forest.withValues(alpha: 0.08),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: _isRecording ? '结束录音' : '开始聆听',
                        child: Material(
                          key: const Key('record-button'),
                          color: _busy ? const Color(0xFF82958C) : forest,
                          elevation: 10,
                          shadowColor: forest.withValues(alpha: 0.22),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: _busy ? null : _toggleRecording,
                            child: SizedBox.square(
                              dimension: 170,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_busy)
                                    const SizedBox.square(
                                      dimension: 36,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  else
                                    Icon(
                                      _isRecording
                                          ? Icons.stop_rounded
                                          : Icons.mic_rounded,
                                      color: Colors.white,
                                      size: 50,
                                    ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _isRecording ? '结束' : '开始聆听',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFDF7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFD9D7CC)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x12000000),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 15,
                                color: Color(0xFF66716B),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _isRecording ? '${seconds}s' : '20s',
                                key: const Key('recording-duration'),
                                style: const TextStyle(
                                  color: Color(0xFF52615A),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 118),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _ListeningHint(icon: Icons.eco_outlined, label: '靠近'),
                    _HintDivider(),
                    _ListeningHint(
                      icon: Icons.volume_off_outlined,
                      label: '安静',
                    ),
                    _HintDivider(),
                    _ListeningHint(
                      icon: Icons.directions_car_filled_outlined,
                      label: '远离车流',
                    ),
                  ],
                ),
                if (_recording != null ||
                    _quality != null ||
                    _error != null ||
                    _hasAnalyzed) ...[
                  const SizedBox(height: 34),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xF5FFFDF7),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE4E0D5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_recording case final recording?) ...[
                          Text(
                            '已录下 ${recording.duration.inSeconds}s',
                            key: const Key('recording-saved'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const Key('playback-button'),
                            onPressed: _togglePlayback,
                            icon: Icon(
                              _isPlaying
                                  ? Icons.stop_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            label: Text(_isPlaying ? '停止播放' : '回放原声'),
                          ),
                        ],
                        if (_quality case final quality?) ...[
                          const SizedBox(height: 14),
                          Text(
                            quality.usable ? '录音质量可用于识别' : '建议重新录制',
                            key: const Key('quality-status'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: quality.usable
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error,
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
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
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
                          const Text(
                            '识别在手机本地完成，模型分数只表示线索强弱。',
                            textAlign: TextAlign.center,
                          ),
                        ],
                        if (_error case final error?) ...[
                          const SizedBox(height: 16),
                          Text(
                            error,
                            key: const Key('recording-error'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ],
                        if (_hasAnalyzed) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            key: const Key('save-exploration-button'),
                            onPressed: _saved || _saving
                                ? null
                                : _saveExploration,
                            icon: Icon(
                              _saved
                                  ? Icons.check_rounded
                                  : Icons.bookmark_add_rounded,
                            ),
                            label: Text(
                              _saved
                                  ? '已保存到声音册'
                                  : (_saving ? '正在保存' : '保存到声音册'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            key: const Key('cloud-card-button'),
                            onPressed: _enriching ? null : _requestCloudCard,
                            icon: _enriching
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.auto_stories_rounded),
                            label: Text(_enriching ? '正在生成科普卡' : '生成儿童科普卡'),
                          ),
                        ],
                        if (_cloudCard case final card?) ...[
                          const SizedBox(height: 24),
                          Card(
                            color: theme.colorScheme.secondaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    card.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
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
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListeningHint extends StatelessWidget {
  const _ListeningHint({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: Column(
        children: [
          Icon(icon, size: 24, color: const Color(0xFF174936)),
          const SizedBox(height: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF66716B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HintDivider extends StatelessWidget {
  const _HintDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 34,
      child: VerticalDivider(width: 1, thickness: 1, color: Color(0xFFD9D7CC)),
    );
  }
}
