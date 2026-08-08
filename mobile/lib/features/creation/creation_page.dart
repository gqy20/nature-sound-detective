import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/audio/audio_playback.dart';
import 'package:nature_sound_detective/core/background/creation_background.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/network/direct_creation_service.dart';
import 'package:nature_sound_detective/core/storage/creation_settings_store.dart';
import 'package:nature_sound_detective/core/storage/creation_store.dart';
import 'package:nature_sound_detective/features/settings/creation_settings_page.dart';
import 'package:video_player/video_player.dart';

class CreationPage extends StatefulWidget {
  const CreationPage({
    super.key,
    required this.subject,
    this.sourceAudioPath = '',
    this.existingRecord,
    this.location = '杭州',
    this.service,
    this.settingsStore,
    this.playback,
  });

  final String subject;
  final String sourceAudioPath;
  final CreationRecord? existingRecord;
  final String location;
  final CreationService? service;
  final CreationSettingsStore? settingsStore;
  final AudioPlayback? playback;

  @override
  State<CreationPage> createState() => _CreationPageState();
}

class _CreationPageState extends State<CreationPage>
    with WidgetsBindingObserver {
  late final CreationService _service;
  late final CreationSettingsStore _settingsStore;
  late final CreationStore _creationStore;
  final _background = const CreationBackgroundScheduler();
  late final AudioPlayback _playback;
  CreationSettings _settings = const CreationSettings();
  CreationStage _stage = CreationStage.idle;
  String _stageMessage = '把声音线索变成音乐和短片';
  CreationArtifacts? _artifacts;
  String? _error;
  bool _loading = true;
  bool _playingMusic = false;
  StreamSubscription<bool>? _playbackSubscription;
  VideoPlayerController? _videoController;
  String _pendingRecordId = '';
  String _pendingDirectoryPath = '';

  bool get _creating => {
    CreationStage.generatingMusic,
    CreationStage.generatingNarration,
    CreationStage.submittingVideo,
    CreationStage.waitingForVideo,
    CreationStage.downloadingVideo,
    CreationStage.composing,
  }.contains(_stage);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = widget.service ?? DirectCreationService();
    _settingsStore = widget.settingsStore ?? FileCreationSettingsStore();
    _creationStore = CreationStore();
    _playback = widget.playback ?? DeviceFileAudioPlayback();
    _playbackSubscription = _playback.playing.listen((playing) {
      if (mounted) setState(() => _playingMusic = playing);
    });
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsStore.load();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        if (widget.existingRecord case final record?) {
          _stage = record.stage;
          _stageMessage = record.message;
          _artifacts = CreationArtifacts(
            id: record.id,
            directoryPath: record.directoryPath,
            musicPath: record.musicPath.isEmpty ? null : record.musicPath,
            narrationPath: record.narrationPath.isEmpty
                ? null
                : record.narrationPath,
            videoPath: record.videoPath.isEmpty ? null : record.videoPath,
            finalVideoPath: record.finalVideoPath.isEmpty
                ? null
                : record.finalVideoPath,
            musicError: record.musicError.isEmpty ? null : record.musicError,
            videoError: record.videoError.isEmpty ? null : record.videoError,
            wanTaskId: record.wanTaskId,
          );
        }
      });
      await _initializeVideo();
    } catch (error, stackTrace) {
      AppLog.error(
        'creation_ui',
        'page_initialization_failed',
        traceId: widget.existingRecord?.id,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = '作品信息读取失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_playbackSubscription?.cancel());
    unawaited(_playback.dispose());
    _videoController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_pendingRecordId.isEmpty) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_background.cancel(_pendingRecordId));
    } else if ({
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    }.contains(state)) {
      unawaited(_background.schedule(_pendingRecordId, _pendingDirectoryPath));
    }
  }

  Future<void> _openSettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreationSettingsPage(store: _settingsStore),
      ),
    );
    if (changed == true) await _loadSettings();
  }

  Future<void> _startCreation() async {
    if (!_settings.canCreate || _creating) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('开始生成音乐和视频？'),
        content: const Text('将直接调用你的 MiniMax 和阿里云百炼账户，可能消耗账户额度。原始录音不会上传。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认生成'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    AppLog.info(
      'creation_ui',
      'creation_confirmed',
      traceId: widget.existingRecord?.id,
      fields: {'resume': widget.existingRecord != null},
    );
    await _playback.stop();
    await _videoController?.dispose();
    setState(() {
      _artifacts = null;
      _videoController = null;
      _error = null;
      _stage = CreationStage.generatingMusic;
      _stageMessage = '正在生成自然配乐';
    });
    try {
      void report(CreationUpdate update) {
        if (!mounted) return;
        if (update.stage == CreationStage.waitingForVideo) {
          _pendingRecordId = update.recordId;
          _pendingDirectoryPath = update.directoryPath;
          if (WidgetsBinding.instance.lifecycleState !=
              AppLifecycleState.resumed) {
            unawaited(
              _background.schedule(update.recordId, update.directoryPath),
            );
          }
        } else if ({
          CreationStage.completed,
          CreationStage.partial,
          CreationStage.failed,
        }.contains(update.stage)) {
          unawaited(_background.cancel(update.recordId));
          _pendingRecordId = '';
          _pendingDirectoryPath = '';
        }
        setState(() {
          _stage = update.stage;
          _stageMessage = update.message;
        });
      }

      final artifacts = widget.existingRecord == null
          ? await _service.create(
              settings: _settings,
              subject: widget.subject,
              location: widget.location,
              sourceAudioPath: widget.sourceAudioPath,
              onProgress: report,
            )
          : await _service.resume(
              settings: _settings,
              record:
                  await _creationStore.load(widget.existingRecord!.id) ??
                  widget.existingRecord!,
              onProgress: report,
            );
      if (!mounted) return;
      setState(() => _artifacts = artifacts);
      await _initializeVideo();
    } on CreationException catch (error, stackTrace) {
      AppLog.warning(
        'creation_ui',
        'creation_failed',
        traceId: widget.existingRecord?.id,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _stage = CreationStage.failed;
          _stageMessage = '生成没有完成';
          _error = error.message;
        });
      }
    } catch (error, stackTrace) {
      AppLog.error(
        'creation_ui',
        'creation_unexpected_failure',
        traceId: widget.existingRecord?.id,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _stage = CreationStage.failed;
          _stageMessage = '生成没有完成';
          _error = '生成失败：$error';
        });
      }
    }
  }

  Future<void> _initializeVideo() async {
    final artifacts = _artifacts;
    final path = artifacts?.finalVideoPath ?? artifacts?.videoPath;
    if (path == null || !File(path).existsSync()) return;
    try {
      await _videoController?.dispose();
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _videoController = controller);
    } catch (error, stackTrace) {
      AppLog.warning(
        'creation_ui',
        'video_initialization_failed',
        traceId: _artifacts?.id,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = '视频暂时无法播放，但作品文件仍然保留。');
    }
  }

  Future<void> _toggleMusic() async {
    final path = _artifacts?.musicPath;
    if (path == null) return;
    try {
      if (_playingMusic) {
        await _playback.stop();
      } else {
        await _videoController?.pause();
        await _playback.play(path);
      }
    } catch (error, stackTrace) {
      AppLog.warning(
        'creation_ui',
        'music_playback_failed',
        traceId: _artifacts?.id,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = '音乐暂时无法播放。');
    }
  }

  Future<void> _toggleVideo() async {
    final controller = _videoController;
    if (controller == null) return;
    try {
      await _playback.stop();
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        await controller.play();
      }
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      AppLog.warning(
        'creation_ui',
        'video_playback_failed',
        traceId: _artifacts?.id,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = '视频暂时无法播放。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('自然创作'),
        actions: _settings.canCreate
            ? [
                IconButton(
                  tooltip: '创作设置',
                  onPressed: _creating ? null : _openSettings,
                  icon: const Icon(Icons.tune_rounded),
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9EFE8),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '音乐 · 旁白 · 短片',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.subject,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontSize: 26,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 17),
                          const SizedBox(width: 4),
                          Text(widget.location),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (!_settings.canCreate) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.key_rounded, size: 30),
                          const SizedBox(height: 18),
                          Text('连接创作服务', style: theme.textTheme.titleLarge),
                          const SizedBox(height: 4),
                          const Text('MiniMax + 阿里云百炼'),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            key: const Key('open-creation-settings'),
                            onPressed: _openSettings,
                            icon: const Icon(Icons.settings_outlined),
                            label: const Text('去设置'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  _CreationProgressCard(
                    stage: _stage,
                    message: _stageMessage,
                    active: _creating,
                  ),
                  if (_artifacts?.musicPath != null) ...[
                    const SizedBox(height: 16),
                    _ArtifactCard(
                      icon: Icons.music_note_rounded,
                      title: '自然配乐',
                      subtitle: _artifacts?.musicError,
                      buttonLabel: _playingMusic ? '停止' : '播放',
                      buttonIcon: _playingMusic
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      onPressed: _toggleMusic,
                    ),
                  ],
                  if (_videoController case final controller?) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            VideoPlayer(controller),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                key: const Key('play-created-video'),
                                onTap: _toggleVideo,
                                child: Center(
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 180),
                                    opacity: controller.value.isPlaying ? 0 : 1,
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: const BoxDecoration(
                                        color: Color(0xAA10261C),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 34,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_artifacts?.musicError case final message?) ...[
                    const SizedBox(height: 12),
                    _WarningText(label: '音乐', message: message),
                  ],
                  if (_artifacts?.videoError case final message?) ...[
                    const SizedBox(height: 12),
                    _WarningText(label: '视频', message: message),
                  ],
                  if (_error case final message?) ...[
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const Key('start-creation'),
                    onPressed: _creating ? null : _startCreation,
                    icon: _creating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      _creating
                          ? '正在创作'
                          : (widget.existingRecord?.canResume == true
                                ? '继续完成作品'
                                : (_artifacts == null ? '生成完整作品' : '重新检查作品')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '任务 ID 会保存在本机，中断后可从作品册继续，不会重复提交视频。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF66716B)),
                  ),
                ],
              ],
            ),
    );
  }
}

class _CreationProgressCard extends StatelessWidget {
  const _CreationProgressCard({
    required this.stage,
    required this.message,
    required this.active,
  });

  final CreationStage stage;
  final String message;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final icon = switch (stage) {
      CreationStage.completed => Icons.check_circle_rounded,
      CreationStage.partial => Icons.info_rounded,
      CreationStage.failed => Icons.error_outline_rounded,
      _ => Icons.auto_awesome_rounded,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            if (active)
              const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              Icon(
                icon,
                size: 30,
                color: Theme.of(context).colorScheme.primary,
              ),
            const SizedBox(width: 14),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _ArtifactCard extends StatelessWidget {
  const _ArtifactCard({
    required this.icon,
    required this.title,
    required this.buttonLabel,
    required this.buttonIcon,
    required this.onPressed,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String buttonLabel;
  final IconData buttonIcon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null) Text(subtitle!),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onPressed,
              icon: Icon(buttonIcon),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarningText extends StatelessWidget {
  const _WarningText({required this.label, required this.message});

  final String label;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label：$message',
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}
