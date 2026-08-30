import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/audio/audio_playback.dart';
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/audio_waveform.dart';
import 'package:nature_sound_detective/core/audio/method_channel_audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/wav_quality_analyzer.dart';
import 'package:nature_sound_detective/core/diagnostics/debug_export_service.dart';
import 'package:nature_sound_detective/core/diagnostics/diagnostics_config.dart';
import 'package:nature_sound_detective/core/community/route_listening_context.dart';
import 'package:nature_sound_detective/core/family/family_session_coordinator.dart';
import 'package:nature_sound_detective/core/creation/creation_visual_policy.dart';
import 'package:nature_sound_detective/core/family/family_session_models.dart';
import 'package:nature_sound_detective/core/inference/recording_analyzer.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode.dart';
import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/storage/exploration_store.dart';
import 'package:nature_sound_detective/features/creation/creation_page.dart';
import 'package:nature_sound_detective/features/capture/sound_waveform.dart';
import 'package:nature_sound_detective/features/library/nature_book_page.dart';
import 'package:nature_sound_detective/features/navigation/primary_feature.dart';
import 'package:nature_sound_detective/features/parent/parent_companion_sheet.dart';
import 'package:nature_sound_detective/features/park_guide/park_guide_page.dart';
import 'package:nature_sound_detective/features/diagnostics/diagnostics_page.dart';
import 'package:nature_sound_detective/features/family/family_link_page.dart';
import 'package:nature_sound_detective/features/result/detection_results.dart';
import 'package:nature_sound_detective/features/settings/creation_settings_page.dart';
import 'package:nature_sound_detective/shared/widgets/app_popover_menu.dart';
import 'package:nature_sound_detective/features/species/species_detail_page.dart';
import 'package:nature_sound_detective/core/network/parent_guidance_service.dart';
import 'package:share_plus/share_plus.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({
    super.key,
    this.recorder,
    this.qualityAnalyzer,
    this.playback,
    this.analyzer,
    this.store,
    this.routeContextStore,
    this.parentGuidanceService,
    this.mode = ExplorationMode.child,
    this.onModeChanged,
    this.familySessionCoordinator,
    this.onPrimaryFeatureSelected,
    this.onPrimarySwipeLockChanged,
  });

  final AudioRecorder? recorder;
  final AudioQualityAnalyzer? qualityAnalyzer;
  final AudioPlayback? playback;
  final RecordingAnalyzer? analyzer;
  final ExplorationStore? store;
  final RouteListeningContextStore? routeContextStore;
  final ParentGuidanceNetworkService? parentGuidanceService;
  final ExplorationMode mode;
  final ValueChanged<ExplorationMode>? onModeChanged;
  final FamilySessionCoordinator? familySessionCoordinator;
  final ValueChanged<PrimaryFeature>? onPrimaryFeatureSelected;
  final ValueChanged<bool>? onPrimarySwipeLockChanged;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  static const _maxDuration = Duration(seconds: 20);

  late final AudioRecorder _recorder;
  late final AudioQualityAnalyzer _qualityAnalyzer;
  late final AudioPlayback _playback;
  late final RecordingAnalyzer _analyzer;
  late final bool _ownsAnalyzer;
  late final ExplorationStore _store;
  late final RouteListeningContextStore _routeContextStore;
  late final ParentGuidanceNetworkService _parentGuidanceService;
  StreamSubscription<bool>? _playbackSubscription;
  StreamSubscription<Duration>? _playbackPositionSubscription;
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
  final Map<String, Map<String, List<String>>> _fieldObservations = {};
  String? _error;
  double _liveRms = 0;
  double _livePeak = 0;
  List<double> _liveLevels = const [];
  List<double> _waveformSamples = const [];
  double _playbackProgress = 0;
  bool _signalHeard = false;
  bool _levelPolling = false;
  String? _audioSource;
  bool _exportingDiagnostics = false;
  final Set<ExplorationBehavior> _behaviors = {};
  int _familyEventStartIndex = 0;
  RouteListeningContext? _routeContext;
  ParentGuidanceQuota? _parentGuidanceQuota;
  bool? _reportedPrimarySwipeLock;

  bool get _isRecording => _startedAt != null;
  bool get _canImport => _recorder is AudioImporter;

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder ?? MethodChannelAudioRecorder();
    _qualityAnalyzer = widget.qualityAnalyzer ?? const WavQualityAnalyzer();
    _playback = widget.playback ?? DeviceFileAudioPlayback();
    _ownsAnalyzer = widget.analyzer == null;
    _analyzer = widget.analyzer ?? LocalRecordingAnalyzer();
    _store = widget.store ?? FileExplorationStore();
    _routeContextStore =
        widget.routeContextStore ?? RouteListeningContextStore();
    _parentGuidanceService =
        widget.parentGuidanceService ?? ParentGuidanceNetworkService();
    unawaited(_restoreRouteContext());
    if (widget.mode == ExplorationMode.parent) unawaited(_loadParentQuota());
    _playbackSubscription = _playback.playing.listen((playing) {
      if (!mounted) return;
      setState(() => _isPlaying = playing);
      if (!playing && _playbackProgress != 0) {
        setState(() => _playbackProgress = 0);
      }
    });
    _playbackPositionSubscription = _playback.position.listen((position) {
      final duration = _recording?.duration ?? Duration.zero;
      if (!mounted || duration <= Duration.zero) return;
      setState(() {
        _playbackProgress = (position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0);
      });
    });
    AppLog.info('capture', 'page_ready');
  }

  @override
  void didUpdateWidget(covariant CapturePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != ExplorationMode.parent &&
        widget.mode == ExplorationMode.parent) {
      unawaited(_loadParentQuota());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_playbackSubscription?.cancel());
    unawaited(_playbackPositionSubscription?.cancel());
    unawaited(_playback.dispose());
    if (_ownsAnalyzer) unawaited(_analyzer.dispose());
    if (_isRecording) {
      unawaited(_recorder.cancel());
    }
    widget.onPrimarySwipeLockChanged?.call(false);
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
    final routeContext = _routeContextStore.cached ?? _routeContext;
    _familyEventStartIndex =
        widget.familySessionCoordinator?.events.length ?? 0;
    setState(() {
      _busy = true;
      _resultVisible = false;
      _recording = null;
      _quality = null;
      _detections = const [];
      _fieldChecks.clear();
      _fieldObservations.clear();
      _hasAnalyzed = false;
      _saved = false;
      _error = null;
      _liveRms = 0;
      _livePeak = 0;
      _liveLevels = const [];
      _waveformSamples = const [];
      _playbackProgress = 0;
      _signalHeard = false;
      _audioSource = null;
      _behaviors.clear();
      if (routeContext?.safeObservationConfirmed == true) {
        _recordBehavior(ExplorationBehavior.observedSafely);
      }
      _routeContext = routeContext;
    });
    try {
      var permitted = await _recorder.hasPermission();
      if (!permitted) {
        AppLog.info('permission', 'microphone_permission_requested');
        permitted = await _recorder.requestPermission();
        AppLog.info(
          'permission',
          'microphone_permission_result',
          fields: {'granted': permitted},
        );
      }
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
        _busy = false;
      });
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
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

  Future<void> _restoreRouteContext() async {
    final context = await _routeContextStore.load();
    if (mounted && context != null) setState(() => _routeContext = context);
  }

  Future<void> _loadParentQuota() async {
    final quota = await _parentGuidanceService.loadQuota();
    if (mounted && quota != null) {
      setState(() => _parentGuidanceQuota = quota);
    }
  }

  void _recordBehavior(
    ExplorationBehavior behavior, {
    Map<String, Object?> payload = const {},
    bool allowRepeat = false,
  }) {
    final added = _behaviors.add(behavior);
    if (!added && !allowRepeat) return;
    final coordinator = widget.familySessionCoordinator;
    if (coordinator != null) {
      unawaited(coordinator.recordBehavior(behavior, payload: payload));
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
        _recordBehavior(
          ExplorationBehavior.capturedSound,
          payload: {
            'duration_seconds': recording.duration.inSeconds,
            'weak_signal': quality.weakSignal,
          },
        );
        _startedAt = null;
        _elapsed = recording.duration;
        _resultVisible = true;
        _liveRms = 0;
        _livePeak = 0;
        _waveformSamples = const [];
      });
      unawaited(_loadRecordingWaveform(recording));
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
        _liveRms = _liveRms * 0.42 + level.rms * 0.58;
        _livePeak = _livePeak * 0.3 + level.peak * 0.7;
        _liveLevels = List<double>.unmodifiable([
          ...(_liveLevels.length >= 36 ? _liveLevels.skip(1) : _liveLevels),
          _liveRms,
        ]);
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
    await _routeContextStore.clear();
    setState(() {
      _busy = true;
      _resultVisible = false;
      _recording = null;
      _quality = null;
      _detections = const [];
      _fieldChecks.clear();
      _fieldObservations.clear();
      _hasAnalyzed = false;
      _saved = false;
      _error = null;
      _routeContext = null;
      _waveformSamples = const [];
      _playbackProgress = 0;
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
        _recordBehavior(ExplorationBehavior.importedSound);
        _elapsed = recording.duration;
        _waveformSamples = const [];
        _resultVisible = true;
      });
      unawaited(_loadRecordingWaveform(recording));
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
        setState(
          () => _recordBehavior(
            ExplorationBehavior.replayedAudio,
            allowRepeat: true,
          ),
        );
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

  Future<List<double>> _extractWaveform(String path) async {
    try {
      return await AudioWaveformExtractor.extract(path);
    } catch (error, stackTrace) {
      AppLog.warning(
        'audio',
        'waveform_extract_failed',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  Future<void> _loadRecordingWaveform(RecordedAudio recording) async {
    final samples = await _extractWaveform(recording.path);
    if (!mounted || _recording?.id != recording.id) return;
    setState(() => _waveformSamples = samples);
  }

  Future<void> _loadDebugDemo() async {
    if (_busy || !kDebugMode || _recorder is! MethodChannelAudioRecorder) {
      return;
    }
    await _routeContextStore.clear();
    setState(() {
      _busy = true;
      _recording = null;
      _quality = null;
      _detections = const [];
      _fieldChecks.clear();
      _fieldObservations.clear();
      _hasAnalyzed = false;
      _saved = false;
      _error = null;
      _routeContext = null;
      _waveformSamples = const [];
      _playbackProgress = 0;
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
        _recordBehavior(ExplorationBehavior.importedSound);
        _elapsed = recording.duration;
        _waveformSamples = const [];
        _resultVisible = true;
      });
      unawaited(_loadRecordingWaveform(recording));
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
        fieldObservations: Map<String, Map<String, List<String>>>.unmodifiable(
          _fieldObservations,
        ),
        location: _routeContext?.parkName ?? '杭州',
        routeContext: _routeContext,
        familyEvents:
            widget.familySessionCoordinator?.events
                .skip(_familyEventStartIndex)
                .toList(growable: false) ??
            const [],
      );
      await _routeContextStore.clear();
      AppLog.info(
        'storage',
        'exploration_saved',
        traceId: recording.id,
        fields: {'detection_count': _detections.length},
      );
      if (mounted) {
        setState(() {
          _saved = true;
          _routeContext = null;
        });
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

  void _updateFieldObservations(
    SoundDetection detection,
    Map<String, List<String>> observations,
  ) {
    final recording = _recording;
    final key = _speciesKey(detection);
    setState(() {
      if (observations.isEmpty) {
        _fieldObservations.remove(key);
      } else {
        _fieldObservations[key] = observations.map(
          (dimension, values) =>
              MapEntry(dimension, List<String>.unmodifiable(values)),
        );
      }
      final meaningfulDimensions = observations.values
          .where(
            (values) =>
                values.any((value) => value.isNotEmpty && value != 'unknown'),
          )
          .length;
      if (meaningfulDimensions > 0) {
        _recordBehavior(ExplorationBehavior.completedObservation);
      }
      if (meaningfulDimensions >= 2) {
        _recordBehavior(ExplorationBehavior.comparedEvidence);
      }
      if (observations.values.any((values) => values.contains('unknown'))) {
        _recordBehavior(ExplorationBehavior.acceptedUncertainty);
      }
    });
    if (_saved && recording != null) {
      unawaited(
        _store.setFieldObservations(recording.id, key, observations).catchError(
          (error, stackTrace) {
            AppLog.warning(
              'storage',
              'field_observations_save_failed',
              traceId: recording.id,
              fields: {'species_key': key},
              error: error,
              stackTrace: stackTrace,
            );
          },
        ),
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
          initialObservations:
              _fieldObservations[_speciesKey(detection)] ?? const {},
          onChecksChanged: (checks) => _updateFieldChecks(detection, checks),
          onObservationsChanged: (values) =>
              _updateFieldObservations(detection, values),
          mode: widget.mode,
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
    AppLog.info('diagnostics', 'diagnostic_export_requested');
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
    final visualMode = selectCreationVisualMode(primary);
    final subject = primary?.tentative == true
        ? primary?.nameZh ?? '自然环境声'
        : primary?.specificSpecies?.nameZh ?? primary?.nameZh ?? '自然环境声';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreationPage(
          subject: subject,
          sourceAudioPath: _recording?.path ?? '',
          visualMode: visualMode,
        ),
      ),
    );
  }

  void _openNatureBook() {
    if (widget.onPrimaryFeatureSelected case final select?) {
      select(PrimaryFeature.natureBook);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NatureBookPage(store: _store)),
    );
  }

  void _openParkGuide() {
    if (widget.mode != ExplorationMode.parent) return;
    if (widget.onPrimaryFeatureSelected case final select?) {
      select(PrimaryFeature.parkGuide);
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ParkGuidePage()));
  }

  void _openFamilyLink() {
    final coordinator = widget.familySessionCoordinator;
    if (coordinator == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FamilyLinkPage(
          coordinator: coordinator,
          preferredRole: widget.mode == ExplorationMode.parent
              ? FamilyDeviceRole.parent
              : FamilyDeviceRole.child,
        ),
      ),
    );
  }

  Future<void> _openParentCompanion() async {
    final primary = _detections.firstOrNull;
    final observations = primary == null
        ? const <String, List<String>>{}
        : _fieldObservations[_speciesKey(primary)] ?? const {};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFFFFDF7),
      builder: (_) => ParentCompanionSheet(
        detection: primary,
        observations: observations,
        behaviors: {..._behaviors},
        weakSignal: _quality?.weakSignal ?? false,
        service: _parentGuidanceService,
        quota: _parentGuidanceQuota,
      ),
    );
    await _loadParentQuota();
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
    if (mounted) {
      setState(
        () => _recordBehavior(
          ExplorationBehavior.retriedRecording,
          allowRepeat: true,
        ),
      );
    }
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

    _syncPrimarySwipeLock();
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/hangzhou_mist_home_v2.webp',
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

  void _syncPrimarySwipeLock() {
    final locked = _busy || _isRecording || _analyzing;
    if (_reportedPrimarySwipeLock == locked) return;
    _reportedPrimarySwipeLock = locked;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onPrimarySwipeLockChanged?.call(locked);
    });
  }

  Widget _buildCaptureSurface(BuildContext context) {
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 650 || textScale > 1.25;
        final controlDimension = compact ? 204.0 : 234.0;
        final scrollFallback = constraints.maxHeight < 560 || textScale > 1.6;
        final familyCoordinator = widget.familySessionCoordinator;
        final showParentHome =
            !_isRecording &&
            widget.mode == ExplorationMode.parent &&
            familyCoordinator != null;

        final content = Padding(
          padding: EdgeInsets.fromLTRB(24, compact ? 12 : 16, 24, 20),
          child: Column(
            children: [
              _buildHeader(theme),
              Expanded(
                child: showParentHome
                    ? ListenableBuilder(
                        listenable: familyCoordinator,
                        builder: (context, _) => _buildParentHome(
                          theme,
                          familyCoordinator,
                          compact: compact,
                        ),
                      )
                    : Column(
                        children: [
                          Spacer(flex: compact ? 2 : 3),
                          if (!_isRecording &&
                              widget.mode == ExplorationMode.child &&
                              _routeContext == null) ...[
                            const _CaptureLocationLabel(),
                            SizedBox(height: compact ? 8 : 10),
                          ],
                          if (_routeContext case final route?) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xE6FFF2CE),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                '${route.parkName} · 第${route.stopIndex + 1}站 · ${route.zoneName}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Text(
                            _isRecording
                                ? '正在倾听'
                                : widget.mode == ExplorationMode.parent
                                ? '和孩子一起听听'
                                : '听听，谁在附近？',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontSize: compact ? 28 : null,
                            ),
                          ),
                          SizedBox(height: compact ? 12 : 16),
                          Text(
                            _isRecording
                                ? (_signalHeard ? '已经听到声音，继续保持' : '保持安静，手机不要晃动')
                                : widget.mode == ExplorationMode.parent
                                ? '先让孩子指出方向，再把手机靠近想听的位置'
                                : '把手机靠近想听的方向',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                          if (!_isRecording &&
                              widget.mode == ExplorationMode.parent)
                            TextButton.icon(
                              key: const Key('parent-park-guide-cta'),
                              onPressed: _openParkGuide,
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('先看看今天适合去哪听'),
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

  Widget _buildParentHome(
    ThemeData theme,
    FamilySessionCoordinator coordinator, {
    required bool compact,
  }) {
    final connection = coordinator.connection;
    final activeParent =
        connection?.active == true &&
        connection?.role == FamilyDeviceRole.parent;
    final cue = coordinator.latestCue;
    return ListView(
      key: const Key('parent-role-home'),
      padding: EdgeInsets.fromLTRB(0, compact ? 22 : 42, 0, 22),
      children: [
        Text(
          activeParent ? '孩子正在探索' : '家长陪伴',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: compact ? 27 : 31,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          activeParent ? '跟着孩子的进度，给出恰到好处的回应' : '和孩子保持在同一次探索里',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        if (activeParent) ...[
          Container(
            key: const Key('parent-live-summary'),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xEFFFF2CE),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE4CF96)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.devices_rounded, color: Color(0xFF174936)),
                    const SizedBox(width: 8),
                    Text(
                      coordinator.error == null ? '儿童端已连接' : '连接需要留意',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    if (coordinator.syncing)
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  cue?.title ?? '等待孩子完成下一步探索',
                  style: theme.textTheme.titleLarge,
                ),
                if (cue != null) ...[
                  const SizedBox(height: 6),
                  Text('现在可以说：“${cue.say}”'),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('open-parent-live-companion'),
                  onPressed: _openFamilyLink,
                  icon: const Icon(Icons.favorite_outline_rounded),
                  label: const Text('打开实时陪伴'),
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            key: const Key('parent-connection-card'),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xEDF1F4EE),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFD8E1D8)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFFDDEADF),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.devices_other_rounded,
                          color: Color(0xFF174936),
                          size: 24,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '还没有连接儿童端',
                        style: TextStyle(
                          color: Color(0xFF203C31),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('连接后，可以看到孩子的探索进度和现在适合说的话。'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('parent-connect-family-primary'),
                    onPressed: _openFamilyLink,
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('连接孩子的设备'),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          activeParent ? '计划下一次探索' : '还没准备出发？',
          style: theme.textTheme.titleSmall?.copyWith(
            color: const Color(0xFF52615A),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('parent-park-guide-cta'),
          onPressed: _openParkGuide,
          icon: const Icon(Icons.map_outlined),
          label: Text(activeParent ? '看看新的亲子路线' : '先看看今天适合去哪听'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const Key('record-button'),
          onPressed: _busy ? null : _toggleRecording,
          icon: const Icon(Icons.mic_none_rounded),
          label: const Text('家长也录一段声音'),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final compact = constraints.maxWidth < 430 || textScale > 1.4;
        return Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  container: true,
                  label: '自然声探员',
                  child: GestureDetector(
                    key: const Key('app-brand'),
                    behavior: HitTestBehavior.opaque,
                    onLongPress: diagnosticsEnabled ? _showDebugActions : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/logo_mark.png',
                          key: const Key('app-brand-mark'),
                          width: 28,
                          height: 28,
                          filterQuality: FilterQuality.medium,
                          excludeFromSemantics: true,
                        ),
                        if (!compact) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '自然声探员',
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontSize: 16,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.familySessionCoordinator case final coordinator?)
                  ListenableBuilder(
                    listenable: coordinator,
                    builder: (context, _) =>
                        coordinator.connection?.active == true
                        ? _LinkedFamilyRoleChip(
                            role: coordinator.connection!.role,
                            compact: compact,
                          )
                        : _ModeMenu(
                            mode: widget.mode,
                            onChanged: widget.onModeChanged,
                          ),
                  )
                else
                  _ModeMenu(mode: widget.mode, onChanged: widget.onModeChanged),
                const SizedBox(width: 4),
                if (widget.familySessionCoordinator case final coordinator?)
                  ListenableBuilder(
                    listenable: coordinator,
                    builder: (context, _) => Badge(
                      isLabelVisible: coordinator.hasUnseenCue,
                      smallSize: 8,
                      child: IconButton(
                        key: const Key('family-link-button'),
                        tooltip: coordinator.connection?.active == true
                            ? '家庭设备已连接'
                            : '连接家庭设备',
                        visualDensity: VisualDensity.compact,
                        style: _headerToolButtonStyle(),
                        onPressed: _openFamilyLink,
                        icon: Icon(
                          coordinator.connection?.active == true
                              ? Icons.devices_rounded
                              : Icons.devices_other_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                if (diagnosticsEnabled) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    key: const Key('debug-export-button'),
                    tooltip: '导出诊断包',
                    visualDensity: VisualDensity.compact,
                    style: _headerToolButtonStyle(),
                    onPressed: _exportingDiagnostics
                        ? null
                        : _exportDiagnostics,
                    icon: _exportingDiagnostics
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bug_report_outlined, size: 20),
                  ),
                ],
                const SizedBox(width: 4),
                IconButton(
                  key: const Key('creation-settings-button'),
                  tooltip: 'AI 创作设置',
                  visualDensity: VisualDensity.compact,
                  style: _headerToolButtonStyle(),
                  onPressed: _openCreationSettings,
                  icon: const Icon(Icons.tune_rounded, size: 20),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecordControl(double dimension) {
    const forest = Color(0xFF174936);
    final seconds = (_elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    final progress = (_elapsed.inMilliseconds / _maxDuration.inMilliseconds)
        .clamp(0.0, 1.0);
    final progressDimension = dimension * 0.846;
    final buttonDimension = dimension * 0.726;

    return SizedBox.square(
      dimension: dimension,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: dimension,
            child: ListeningWaveRing(
              levels: _liveLevels,
              rms: _liveRms,
              peak: _livePeak,
              active: _isRecording,
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
              bottom: -22,
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
                  key: Key('record-limit-label'),
                  style: TextStyle(
                    color: Color(0xFF52615A),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (_isRecording)
            Positioned(
              bottom: -22,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Container(
                  key: ValueKey(_signalHeard),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFBFCFC5)),
                  ),
                  child: Text(
                    _signalHeard ? '听到了，声纹在跳动' : '轻轻等一等，听听周围',
                    key: const Key('live-wave-hint'),
                    style: const TextStyle(
                      color: forest,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
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
    final heightFactor = expanded ? 0.78 : (usable ? 0.68 : 0.64);

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
    const forest = Color(0xFF174936);
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
                  if (recording != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      key: const Key('audio-waveform-card'),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F5EF),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFDCE6DE)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                _analyzing
                                    ? Icons.travel_explore_rounded
                                    : (_isPlaying
                                          ? Icons.graphic_eq_rounded
                                          : Icons.waves_rounded),
                                size: 18,
                                color: forest,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  _analyzing
                                      ? '正在沿着声纹寻找线索'
                                      : (_isPlaying ? '正在回放这段声音' : '这段声音的声纹'),
                                  style: const TextStyle(
                                    color: forest,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          AudioWaveformView(
                            samples: _waveformSamples,
                            active: _analyzing || _isPlaying,
                            progress: _isPlaying
                                ? _playbackProgress
                                : (_analyzing && _analysisTotalWindows > 0
                                      ? _analysisProcessedWindows /
                                            _analysisTotalWindows
                                      : null),
                            label: _analyzing
                                ? '模型正在读取录音声纹'
                                : (_isPlaying ? '正在回放录音声纹' : '录音声纹'),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                    if (quality?.weakSignal == true) ...[
                      Container(
                        key: const Key('weak-evidence-notice'),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0D2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          '模型找到了声音候选，但这段录音证据较弱。分数只表示模型线索，请结合声音方向、节奏和现场环境继续确认。',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
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
                                initialObservations:
                                    _fieldObservations[_speciesKey(
                                      detection,
                                    )] ??
                                    const {},
                                onChecksChanged: (checks) =>
                                    _updateFieldChecks(detection, checks),
                                onObservationsChanged: (values) =>
                                    _updateFieldObservations(detection, values),
                                mode: widget.mode,
                              ),
                            ),
                          ),
                    ),
                  ] else if (_hasAnalyzed && !_analyzing) ...[
                    const SizedBox(height: 20),
                    Container(
                      key: const Key('unknown-result'),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2EC),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '声音已经录下来了，只是暂时没有可靠候选。',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 5),
                          Text('可以先保存为“未知声音”，再观察声音方向、节奏和周围环境。'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('save-unknown-sound-button'),
                      onPressed: _saved || _saving ? null : _saveExploration,
                      icon: Icon(
                        _saved
                            ? Icons.check_rounded
                            : Icons.bookmark_add_rounded,
                      ),
                      label: Text(
                        _saved ? '已保存为未知声音' : (_saving ? '正在保存' : '保存为未知声音'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('unknown-retry-button'),
                      onPressed: _busy ? null : _retryRecording,
                      icon: const Icon(Icons.mic_none_rounded),
                      label: const Text('再录一段试试'),
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
                  if (_hasAnalyzed && _detections.isNotEmpty) ...[
                    if (widget.mode == ExplorationMode.parent) ...[
                      const SizedBox(height: 14),
                      FilledButton.tonalIcon(
                        key: const Key('parent-companion-button'),
                        onPressed: _openParentCompanion,
                        icon: const Icon(Icons.family_restroom_rounded),
                        label: const Text('查看家长引导与回应'),
                      ),
                    ],
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

class _CaptureLocationLabel extends StatelessWidget {
  const _CaptureLocationLabel();

  @override
  Widget build(BuildContext context) => Semantics(
    label: '当前位置，杭州',
    child: const Row(
      key: Key('capture-location-label'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF657269)),
        SizedBox(width: 4),
        Text(
          '杭州 · 自然声探索',
          style: TextStyle(
            color: Color(0xFF657269),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    ),
  );
}

class _LinkedFamilyRoleChip extends StatelessWidget {
  const _LinkedFamilyRoleChip({required this.role, this.compact = false});
  final FamilyDeviceRole role;
  final bool compact;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: role == FamilyDeviceRole.parent ? '家长陪伴设备已连接' : '儿童探索设备已连接',
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE4F0E7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            role == FamilyDeviceRole.parent
                ? Icons.family_restroom_rounded
                : Icons.explore_outlined,
            size: 15,
            color: const Color(0xFF174936),
          ),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(
              role == FamilyDeviceRole.parent ? '家长端' : '儿童端',
              style: const TextStyle(
                color: Color(0xFF174936),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _ModeMenu extends StatelessWidget {
  const _ModeMenu({required this.mode, this.onChanged});

  final ExplorationMode mode;
  final ValueChanged<ExplorationMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    return AppPopoverMenu<ExplorationMode>(
      key: const Key('exploration-mode-menu'),
      tooltip: '切换使用模式',
      onSelected: onChanged ?? (_) {},
      actions: [
        for (final value in ExplorationMode.values)
          AppPopoverAction(
            value: value,
            label: value.label,
            icon: value == ExplorationMode.child
                ? Icons.explore_outlined
                : Icons.family_restroom_rounded,
            selected: value == mode,
          ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xE6FFFDF7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2DDCF)),
        ),
        child: Text(
          compact
              ? (mode == ExplorationMode.child ? '儿童' : '家长')
              : (mode == ExplorationMode.child ? '儿童模式' : '家长模式'),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

ButtonStyle _headerToolButtonStyle() => IconButton.styleFrom(
  minimumSize: const Size.square(40),
  maximumSize: const Size.square(40),
  padding: EdgeInsets.zero,
  backgroundColor: const Color(0xCFFFFDF7),
  foregroundColor: const Color(0xFF34483F),
  disabledBackgroundColor: const Color(0x99FFFDF7),
  side: const BorderSide(color: Color(0xFFE2DDCF)),
  shape: const CircleBorder(),
);

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
