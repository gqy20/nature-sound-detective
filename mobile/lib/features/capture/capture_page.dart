import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/audio/audio_playback.dart';
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/method_channel_audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/wav_quality_analyzer.dart';
import 'package:nature_sound_detective/core/diagnostics/debug_export_service.dart';
import 'package:nature_sound_detective/core/diagnostics/diagnostics_config.dart';
import 'package:nature_sound_detective/core/inference/recording_analyzer.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/storage/exploration_store.dart';
import 'package:nature_sound_detective/features/creation/creation_page.dart';
import 'package:nature_sound_detective/features/community/soundscape_page.dart';
import 'package:nature_sound_detective/features/library/nature_book_page.dart';
import 'package:nature_sound_detective/features/diagnostics/diagnostics_page.dart';
import 'package:nature_sound_detective/features/result/detection_results.dart';
import 'package:nature_sound_detective/features/settings/creation_settings_page.dart';
import 'package:nature_sound_detective/features/species/species_detail_page.dart';
import 'package:share_plus/share_plus.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({
    super.key,
    this.recorder,
    this.qualityAnalyzer,
    this.playback,
    this.analyzer,
    this.store,
  });

  final AudioRecorder? recorder;
  final AudioQualityAnalyzer? qualityAnalyzer;
  final AudioPlayback? playback;
  final RecordingAnalyzer? analyzer;
  final ExplorationStore? store;

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
  StreamSubscription<bool>? _playbackSubscription;
  Timer? _timer;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  bool _busy = false;
  RecordedAudio? _recording;
  AudioQuality? _quality;
  bool _isPlaying = false;
  bool _analyzing = false;
  int _analysisProcessedWindows = 0;
  int _analysisTotalWindows = 0;
  bool _hasAnalyzed = false;
  bool _saving = false;
  bool _saved = false;
  bool _resultVisible = false;
  List<SoundDetection> _detections = const [];
  final Map<String, List<String>> _fieldChecks = <String, List<String>>{};
  String? _error;
  double _liveRms = 0;
  bool _signalHeard = false;
  bool _levelPolling = false;
  String? _audioSource;
  bool _exportingDiagnostics = false;

  bool get _isRecording => _startedAt != null;
  bool get _canImport => _recorder is AudioImporter;

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder ?? MethodChannelAudioRecorder();
    _qualityAnalyzer = widget.qualityAnalyzer ?? const WavQualityAnalyzer();
    _playback = widget.playback ?? DeviceFileAudioPlayback();
    _analyzer = widget.analyzer ?? LocalRecordingAnalyzer();
    _store = widget.store ?? FileExplorationStore();
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
      _resultVisible = false;
      _recording = null;
      _quality = null;
      _detections = const [];
      _fieldChecks.clear();
      _hasAnalyzed = false;
      _saved = false;
      _error = null;
      _liveRms = 0;
      _signalHeard = false;
      _audioSource = null;
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
        unawaited(_refreshRecordingLevel());
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
        setState(() {
          _error = error.message ?? '无法开始录音。';
          _resultVisible = true;
        });
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
          'quality_rms': quality.rms,
          'quality_peak': quality.peak,
          'quality_best_window_rms': quality.bestWindowRms,
          'quality_active_windows': quality.activeWindowCount,
          'quality_total_windows': quality.totalWindowCount,
          'audio_source': _audioSource,
        },
      );
      if (!mounted) return;
      setState(() {
        _recording = recording;
        _quality = quality;
        _startedAt = null;
        _elapsed = recording.duration;
        _resultVisible = true;
        _liveRms = 0;
      });
      if (quality.usable) {
        await _analyzeRecording();
      }
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
          _resultVisible = true;
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
          _resultVisible = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshRecordingLevel() async {
    final provider = _recorder;
    if (provider is! RecordingLevelProvider || _levelPolling || !_isRecording) {
      return;
    }
    _levelPolling = true;
    try {
      final level = await (provider as RecordingLevelProvider)
          .getRecordingLevel();
      if (!mounted || !_isRecording) return;
      setState(() {
        _liveRms = level.rms;
        _audioSource = level.source;
        _signalHeard = _signalHeard || level.rms >= 0.003;
      });
    } on PlatformException catch (error) {
      AppLog.warning(
        'audio',
        'recording_level_unavailable',
        fields: {'platform_code': error.code},
      );
    } finally {
      _levelPolling = false;
    }
  }

  Future<void> _importAudio() async {
    final importer = _recorder;
    if (importer is! AudioImporter || _busy || _isRecording) return;
    setState(() {
      _busy = true;
      _resultVisible = false;
      _recording = null;
      _quality = null;
      _detections = const [];
      _fieldChecks.clear();
      _hasAnalyzed = false;
      _saved = false;
      _error = null;
    });
    try {
      final recording = await (importer as AudioImporter).pickAudio();
      if (recording == null) return;
      final quality = await _qualityAnalyzer.analyze(recording.path);
      AppLog.info(
        'audio',
        'audio_imported',
        traceId: recording.id,
        fields: {
          'duration_ms': recording.duration.inMilliseconds,
          'sample_rate': recording.sampleRate,
          'channels': recording.channelCount,
          'byte_length': recording.byteLength,
          'quality_usable': quality.usable,
          'quality_rms': quality.rms,
          'quality_peak': quality.peak,
          'quality_best_window_rms': quality.bestWindowRms,
          'quality_active_windows': quality.activeWindowCount,
          'quality_total_windows': quality.totalWindowCount,
        },
      );
      if (!mounted) return;
      setState(() {
        _recording = recording;
        _quality = quality;
        _elapsed = recording.duration;
        _resultVisible = true;
      });
      if (quality.usable) {
        await _analyzeRecording();
      }
    } on PlatformException catch (error, stackTrace) {
      AppLog.warning(
        'audio',
        'audio_import_failed',
        fields: {'platform_code': error.code},
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _error = error.message ?? '无法读取这个音频文件。';
          _resultVisible = true;
        });
      }
    } catch (error, stackTrace) {
      AppLog.error(
        'audio',
        'audio_import_processing_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _error = '音频文件处理失败，请换一个文件再试。';
          _resultVisible = true;
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
      _fieldChecks.clear();
      _hasAnalyzed = false;
      _saved = false;
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
        _resultVisible = true;
      });
      if (quality.usable) {
        await _analyzeRecording();
      }
    } on PlatformException catch (error, stackTrace) {
      AppLog.warning(
        'audio',
        'debug_demo_load_failed',
        fields: {'platform_code': error.code},
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _error = error.message ?? '无法载入示例声音。';
          _resultVisible = true;
        });
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
      _analysisProcessedWindows = 0;
      _analysisTotalWindows = 0;
    });
    try {
      final detections = await _analyzer.analyze(
        recording,
        onProgress: (partial, processed, total) {
          if (!mounted) return;
          setState(() {
            _detections = partial;
            _analysisProcessedWindows = processed;
            _analysisTotalWindows = total;
          });
        },
      );
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
        fieldChecks: Map<String, List<String>>.unmodifiable(_fieldChecks),
        location: '杭州',
      );
      AppLog.info(
        'storage',
        'exploration_saved',
        traceId: recording.id,
        fields: {'detection_count': _detections.length},
      );
      if (mounted) {
        setState(() => _saved = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已保存到自然册'),
            action: SnackBarAction(label: '查看', onPressed: _openNatureBook),
          ),
        );
      }
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

  String _speciesKey(SoundDetection detection) {
    final scientificName = detection.specificSpecies?.scientificName?.trim();
    if (scientificName != null && scientificName.isNotEmpty) {
      return scientificName.toLowerCase();
    }
    return '${detection.categoryId}:${detection.specificSpecies?.nameZh ?? detection.nameZh}';
  }

  void _updateFieldChecks(SoundDetection detection, List<String> checks) {
    final recording = _recording;
    final key = _speciesKey(detection);
    setState(() {
      if (checks.isEmpty) {
        _fieldChecks.remove(key);
      } else {
        _fieldChecks[key] = List<String>.unmodifiable(checks);
      }
    });
    if (_saved && recording != null) {
      unawaited(
        _store.setFieldChecks(recording.id, key, checks).catchError((
          error,
          stackTrace,
        ) {
          AppLog.warning(
            'storage',
            'field_checks_save_failed',
            traceId: recording.id,
            fields: {'species_key': key},
            error: error,
            stackTrace: stackTrace,
          );
        }),
      );
    }
  }

  void _openScienceCard() {
    final detection = _detections.firstOrNull;
    if (detection == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpeciesDetailPage(
          detection: detection,
          rank: 1,
          audioPath: _recording?.path,
          playback: _playback,
          initialChecks: _fieldChecks[_speciesKey(detection)] ?? const [],
          onChecksChanged: (checks) => _updateFieldChecks(detection, checks),
        ),
      ),
    );
  }

  DebugSessionSnapshot? get _debugSession {
    final recording = _recording;
    final quality = _quality;
    if (recording == null || quality == null) return null;
    return DebugSessionSnapshot.current(
      recording: recording,
      quality: quality,
      detections: _detections,
    );
  }

  void _openDiagnostics() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DiagnosticsPage(session: _debugSession, explorationStore: _store),
      ),
    );
  }

  Future<void> _exportDiagnostics() async {
    if (!diagnosticsEnabled || _exportingDiagnostics) return;
    setState(() => _exportingDiagnostics = true);
    try {
      final result = await DebugExportService(
        explorationStore: _store,
      ).export(session: _debugSession);
      await SharePlus.instance.share(
        ShareParams(
          text: '自然声探员内测诊断包',
          files: [XFile(result.file.path, mimeType: 'application/zip')],
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('诊断包已生成。')));
      }
    } catch (error, stackTrace) {
      AppLog.error(
        'diagnostics',
        'quick_export_failed',
        traceId: _recording?.id,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('诊断包导出失败，请进入诊断页查看日志。')));
      }
    } finally {
      if (mounted) setState(() => _exportingDiagnostics = false);
    }
  }

  void _openCreationSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CreationSettingsPage()),
    );
  }

  void _openCreation() {
    final primary = _detections.firstOrNull;
    final subject = primary?.tentative == true
        ? primary?.nameZh ?? '自然环境声'
        : primary?.specificSpecies?.nameZh ?? primary?.nameZh ?? '自然环境声';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreationPage(
          subject: subject,
          sourceAudioPath: _recording?.path ?? '',
        ),
      ),
    );
  }

  void _openNatureBook() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NatureBookPage(store: _store)),
    );
  }

  void _openSoundscape() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SoundscapePage(explorationStore: _store),
      ),
    );
  }

  Future<void> _showDebugActions() async {
    if (!diagnosticsEnabled) return;
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

  void _dismissResult() {
    if (!_resultVisible) return;
    setState(() => _resultVisible = false);
  }

  Future<void> _retryRecording() async {
    _dismissResult();
    await _startRecording();
  }

  void _reopenResult() {
    if (_recording == null && _error == null) return;
    setState(() => _resultVisible = true);
  }

  @override
  Widget build(BuildContext context) {
    final showResult =
        _resultVisible &&
        (_recording != null ||
            _quality != null ||
            _error != null ||
            _hasAnalyzed);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/hangzhou_mist.webp',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          const ColoredBox(color: Color(0x12FFFDF7)),
          SafeArea(child: _buildCaptureSurface(context)),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            reverseDuration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: showResult
                ? _buildResultOverlay(context)
                : const SizedBox.shrink(key: ValueKey('result-hidden')),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureSurface(BuildContext context) {
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 650 || textScale > 1.25;
        final controlDimension = compact ? 204.0 : 234.0;
        final scrollFallback = constraints.maxHeight < 560 || textScale > 1.6;

        final content = Padding(
          padding: EdgeInsets.fromLTRB(24, compact ? 12 : 16, 24, 20),
          child: Column(
            children: [
              _buildHeader(theme),
              Expanded(
                child: Column(
                  children: [
                    Spacer(flex: compact ? 2 : 3),
                    Text(
                      _isRecording ? '正在倾听' : '听听，谁在附近？',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: compact ? 28 : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRecording
                          ? (_signalHeard ? '已经听到声音，继续保持' : '保持安静，手机不要晃动')
                          : '把手机靠近想听的方向',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    Spacer(flex: compact ? 2 : 3),
                    _buildRecordControl(controlDimension),
                    Spacer(flex: compact ? 2 : 4),
                    if (_recording != null && !_resultVisible) ...[
                      SizedBox(height: compact ? 6 : 10),
                      TextButton.icon(
                        key: const Key('reopen-result-button'),
                        onPressed: _reopenResult,
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                        label: const Text('查看刚才的录音'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );

        if (!scrollFallback) return content;
        return SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: SizedBox(height: 650, child: content),
        );
      },
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onLongPress: diagnosticsEnabled ? _showDebugActions : null,
            child: Row(
              children: [
                Image.asset(
                  'assets/images/logo_mark.png',
                  width: 28,
                  height: 28,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                ),
                const SizedBox(width: 8),
                Text(
                  '自然声探员',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 16,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Icon(
          Icons.location_on_outlined,
          size: 17,
          color: Color(0xFF52615A),
        ),
        const SizedBox(width: 4),
        const Text(
          '杭州',
          style: TextStyle(
            color: Color(0xFF52615A),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        if (diagnosticsEnabled)
          IconButton(
            key: const Key('debug-export-button'),
            tooltip: '导出诊断包',
            visualDensity: VisualDensity.compact,
            onPressed: _exportingDiagnostics ? null : _exportDiagnostics,
            icon: _exportingDiagnostics
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bug_report_outlined, size: 20),
          ),
        IconButton(
          key: const Key('soundscape-button'),
          tooltip: '共听杭州',
          visualDensity: VisualDensity.compact,
          onPressed: _openSoundscape,
          icon: const Icon(Icons.radar_rounded, size: 20),
        ),
        IconButton(
          key: const Key('works-button'),
          tooltip: '自然册',
          visualDensity: VisualDensity.compact,
          onPressed: _openNatureBook,
          icon: const Icon(Icons.collections_bookmark_outlined, size: 20),
        ),
        IconButton(
          key: const Key('creation-settings-button'),
          tooltip: 'AI 创作设置',
          visualDensity: VisualDensity.compact,
          onPressed: _openCreationSettings,
          icon: const Icon(Icons.tune_rounded, size: 20),
        ),
      ],
    );
  }

  Widget _buildRecordControl(double dimension) {
    const forest = Color(0xFF174936);
    final seconds = (_elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    final progress = (_elapsed.inMilliseconds / _maxDuration.inMilliseconds)
        .clamp(0.0, 1.0);
    final progressDimension = dimension * 0.846;
    final buttonDimension = dimension * 0.726;
    final levelStrength = (_liveRms / 0.04).clamp(0.0, 1.0);

    return SizedBox.square(
      dimension: dimension,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            width: _isRecording
                ? dimension * (0.94 + 0.055 * levelStrength)
                : dimension * 0.94,
            height: _isRecording
                ? dimension * (0.94 + 0.055 * levelStrength)
                : dimension * 0.94,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: forest.withValues(alpha: _isRecording ? 0.18 : 0.09),
              ),
            ),
          ),
          Container(
            width: progressDimension,
            height: progressDimension,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF1F0E7).withValues(alpha: 0.82),
              border: Border.all(color: forest.withValues(alpha: 0.06)),
            ),
          ),
          SizedBox.square(
            dimension: progressDimension,
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
            value: _isRecording ? '已录制 ${_elapsed.inSeconds} 秒' : '最长 20 秒',
            child: Material(
              key: const Key('record-button'),
              color: _busy ? const Color(0xFF82958C) : forest,
              elevation: 10,
              shadowColor: forest.withValues(alpha: 0.22),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _busy ? null : _toggleRecording,
                onLongPress: !_busy && !_isRecording && _canImport
                    ? _importAudio
                    : null,
                child: SizedBox.square(
                  dimension: buttonDimension,
                  child: _buildRecordButtonContent(seconds),
                ),
              ),
            ),
          ),
          if (!_isRecording)
            Positioned(
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFDF7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD9D7CC)),
                ),
                child: const Text(
                  '最长 20 秒',
                  style: TextStyle(
                    color: Color(0xFF52615A),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (!_isRecording && _canImport)
            Positioned(
              right: 2,
              bottom: 12,
              child: Material(
                color: const Color(0xFFFFFDF7),
                shape: const CircleBorder(
                  side: BorderSide(color: Color(0xFFD9D7CC)),
                ),
                child: IconButton(
                  key: const Key('import-audio-button'),
                  tooltip: '选择本地录音',
                  onPressed: _busy ? null : _importAudio,
                  icon: const Icon(Icons.audio_file_outlined),
                  color: forest,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecordButtonContent(String seconds) {
    if (_busy) {
      return const Center(
        child: SizedBox.square(
          dimension: 36,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
          color: Colors.white,
          size: _isRecording ? 42 : 50,
        ),
        if (_isRecording) ...[
          const SizedBox(height: 5),
          Text(
            '${seconds}s',
            key: const Key('recording-duration'),
            style: const TextStyle(
              color: Color(0xFFE2EEE8),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
        ] else
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
    );
  }

  Widget _buildResultOverlay(BuildContext context) {
    final expanded = _detections.isNotEmpty;
    final usable = _quality?.usable == true;
    final heightFactor = expanded ? 0.74 : (usable ? 0.60 : 0.50);

    return Stack(
      key: const ValueKey('result-visible'),
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const Key('result-scrim'),
            onTap: _dismissResult,
            child: const ColoredBox(color: Color(0x330E2118)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            widthFactor: 1,
            heightFactor: heightFactor,
            child: _buildResultPanel(context),
          ),
        ),
      ],
    );
  }

  Widget _buildResultPanel(BuildContext context) {
    final theme = Theme.of(context);
    final quality = _quality;
    final recording = _recording;
    final title = _resultTitle();

    return Material(
      key: const Key('recording-result-sheet'),
      color: const Color(0xFFFFFDF7),
      elevation: 18,
      shadowColor: const Color(0x33000000),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD5D2C6),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleLarge),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '收起结果',
                    onPressed: _dismissResult,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE8E3D7)),
            Expanded(
              child: ListView(
                key: const Key('result-sheet-scroll'),
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                children: [
                  if (recording != null || quality != null)
                    Row(
                      children: [
                        if (recording != null)
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const Key('playback-button'),
                              onPressed: _togglePlayback,
                              icon: Icon(
                                _isPlaying
                                    ? Icons.stop_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              label: Text(
                                '${_isPlaying ? '停止' : '回放原声'} · ${recording.duration.inSeconds}s',
                              ),
                            ),
                          ),
                        if (recording != null && quality != null)
                          const SizedBox(width: 10),
                        if (quality != null)
                          _QualityIndicator(quality: quality),
                      ],
                    ),
                  if (quality != null) ...[
                    if (quality.warnings.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (final warning in quality.warnings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('· $warning'),
                        ),
                    ],
                  ],
                  if (quality?.usable == false) ...[
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      key: const Key('retry-recording-button'),
                      onPressed: _busy ? null : _retryRecording,
                      icon: const Icon(Icons.mic_rounded),
                      label: const Text('重新录制'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('retain-recording-button'),
                      onPressed: _saved || _saving ? null : _saveExploration,
                      icon: Icon(
                        _saved
                            ? Icons.check_rounded
                            : Icons.bookmark_add_rounded,
                      ),
                      label: Text(
                        _saved ? '已保存到声音册' : (_saving ? '正在保存' : '保留这段声音'),
                      ),
                    ),
                  ],
                  if (quality?.usable == true && _analyzing) ...[
                    const SizedBox(height: 18),
                    LinearProgressIndicator(
                      key: const Key('analysis-progress'),
                      value: _analysisTotalWindows > 0
                          ? _analysisProcessedWindows / _analysisTotalWindows
                          : null,
                    ),
                    if (_analysisTotalWindows > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '$_analysisProcessedWindows / $_analysisTotalWindows',
                        key: const Key('analysis-window-progress'),
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ],
                  if (quality?.usable == true &&
                      !_analyzing &&
                      !_hasAnalyzed &&
                      _error != null) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      key: const Key('retry-analysis-button'),
                      onPressed: _analyzeRecording,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试识别'),
                    ),
                  ],
                  if (_detections.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    DetectionResults(
                      detections: _detections,
                      onDetectionTap: (detection, rank) =>
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SpeciesDetailPage(
                                detection: detection,
                                rank: rank,
                                audioPath: _recording?.path,
                                playback: _playback,
                                initialChecks:
                                    _fieldChecks[_speciesKey(detection)] ??
                                    const [],
                                onChecksChanged: (checks) =>
                                    _updateFieldChecks(detection, checks),
                              ),
                            ),
                          ),
                    ),
                  ] else if (_hasAnalyzed && !_analyzing) ...[
                    const SizedBox(height: 20),
                    const Text(
                      '暂时没有找到足够清楚的声音线索，可以换个位置再录一次。',
                      key: Key('unknown-result'),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('unknown-retry-button'),
                      onPressed: _busy ? null : _retryRecording,
                      icon: const Icon(Icons.mic_rounded),
                      label: const Text('换个位置再录'),
                    ),
                  ],
                  if (_error case final error?) ...[
                    const SizedBox(height: 16),
                    Text(
                      error,
                      key: const Key('recording-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  if (_hasAnalyzed) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Tooltip(
                            message: _saved ? '已保存到声音册' : '保存到声音册',
                            child: OutlinedButton.icon(
                              key: const Key('save-exploration-button'),
                              style: _compactActionStyle(),
                              onPressed: _saved || _saving
                                  ? null
                                  : _saveExploration,
                              icon: _saving
                                  ? const _SmallButtonProgress()
                                  : Icon(
                                      _saved
                                          ? Icons.check_rounded
                                          : Icons.bookmark_add_rounded,
                                    ),
                              label: const Text('保存'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Tooltip(
                            message: '认识这个物种',
                            child: FilledButton.icon(
                              key: const Key('science-card-button'),
                              style: _compactActionStyle(),
                              onPressed: _detections.isEmpty
                                  ? null
                                  : _openScienceCard,
                              icon: const Icon(Icons.auto_stories_rounded),
                              label: const Text('科普卡'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Tooltip(
                            message: '创作音乐和短片',
                            child: OutlinedButton.icon(
                              key: const Key('open-creation-button'),
                              style: _compactActionStyle(),
                              onPressed: _openCreation,
                              icon: const Icon(Icons.auto_awesome_rounded),
                              label: const Text('创作'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _resultTitle() {
    if (_error != null && _recording == null) return '这次没有录下来';
    if (_quality?.usable == false) return '没有录到有效声音';
    if (_analyzing) return '正在识别声音';
    if (_error != null && !_hasAnalyzed) return '识别没有完成';
    final speciesCount = _detections
        .where((item) => item.specificSpecies != null)
        .length;
    if (speciesCount > 1) return '$speciesCount 个物种候选';
    if (speciesCount == 1) return '1 个物种候选';
    if (_detections.isNotEmpty && _detections.every((item) => item.tentative)) {
      return '找到一个较弱猜想';
    }
    if (_detections.isNotEmpty) return '找到一些声音线索';
    if (_hasAnalyzed) return '已经听到，暂时没有可靠候选';
    return '录音完成';
  }
}

ButtonStyle _compactActionStyle() => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 8, vertical: 10),
  ),
  iconSize: const WidgetStatePropertyAll(19),
  textStyle: const WidgetStatePropertyAll(
    TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  ),
);

class _SmallButtonProgress extends StatelessWidget {
  const _SmallButtonProgress();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 17,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _QualityIndicator extends StatelessWidget {
  const _QualityIndicator({required this.quality});

  final AudioQuality quality;

  @override
  Widget build(BuildContext context) {
    final (label, icon, foreground, background) = switch ((
      quality.usable,
      quality.warnings.isEmpty,
    )) {
      (true, true) => (
        '录音质量可用于识别',
        Icons.check_rounded,
        const Color(0xFF1F6B4F),
        const Color(0xFFE2F2E8),
      ),
      (true, false) => (
        '声音较弱，但仍可以识别',
        Icons.hearing_rounded,
        const Color(0xFF856018),
        const Color(0xFFF6ECD1),
      ),
      _ => (
        '没有录到可分析的声音',
        Icons.mic_off_rounded,
        Theme.of(context).colorScheme.error,
        Theme.of(context).colorScheme.errorContainer,
      ),
    };
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Container(
          key: const Key('quality-status'),
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: foreground, size: 25),
        ),
      ),
    );
  }
}
