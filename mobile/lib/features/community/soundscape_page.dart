import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/community/soundscape_preloader.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/storage/exploration_record.dart';
import 'package:nature_sound_detective/core/storage/exploration_store.dart';
import 'package:nature_sound_detective/features/community/community_video_page.dart';
import 'package:nature_sound_detective/features/community/native_amap_view.dart';
import 'package:nature_sound_detective/features/community/publication_page.dart';
import 'package:nature_sound_detective/shared/widgets/app_popover_menu.dart';

enum _SoundscapeView { recent, waiting }

enum _DemoFilter { real, demo }

const _soundscapeAreaPositions = <String, Alignment>{
  'yuhang': Alignment(-0.78, -0.68),
  'gongshu': Alignment(-0.34, -0.46),
  'xihu': Alignment(-0.58, -0.06),
  'shangcheng': Alignment(-0.18, 0.16),
  'binjiang': Alignment(-0.07, 0.64),
  'xiaoshan': Alignment(0.36, 0.66),
};

const _soundscapeAreaCoordinates = <String, (double, double)>{
  'yuhang': (30.4203, 119.9780),
  'gongshu': (30.3190, 120.1415),
  'xihu': (30.2590, 120.1302),
  'shangcheng': (30.2425, 120.1903),
  'binjiang': (30.2084, 120.2118),
  'xiaoshan': (30.1838, 120.2644),
};

class SoundscapePage extends StatefulWidget {
  const SoundscapePage({
    super.key,
    this.service,
    this.explorationStore,
    this.recordsLoader,
    this.preloader,
    this.primaryPagePosition,
    this.onOpenParkGuide,
    this.audioStarter,
  });

  final CommunityService? service;
  final ExplorationStore? explorationStore;
  final Future<List<ExplorationRecord>> Function()? recordsLoader;
  final SoundscapePreloader? preloader;
  final ValueListenable<double>? primaryPagePosition;
  final VoidCallback? onOpenParkGuide;
  final Future<void> Function(String audioUrl)? audioStarter;

  @override
  State<SoundscapePage> createState() => _SoundscapePageState();
}

class _SoundscapePageState extends State<SoundscapePage> {
  late final CommunityService _service;
  late final Future<List<ExplorationRecord>> Function() _recordsLoader;
  final ScrollController _scrollController = ScrollController();
  AudioPlayer? _player;
  List<SoundscapeArea> _areas = const [];
  List<CommunityPost> _posts = const [];
  List<CommunityPark> _parks = const [];
  String? _selectedAreaId;
  String? _playingPostId;
  String? _loadingAudioPostId;
  String? _requestedAudioPostId;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  String? _recentAreaId;
  String? _error;
  bool _loading = true;
  bool _acting = false;
  _SoundscapeView _view = _SoundscapeView.recent;
  _DemoFilter _demoFilter = _DemoFilter.real;
  StreamSubscription<PlayerState>? _playerSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  Timer? _highlightTimer;
  bool _wasPrimaryVisible = false;

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ?? widget.preloader?.service ?? HttpCommunityService();
    final store = widget.explorationStore ?? FileExplorationStore();
    _recordsLoader = widget.recordsLoader ?? store.list;
    widget.primaryPagePosition?.addListener(_handlePrimaryPagePosition);
    _load();
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    widget.primaryPagePosition?.removeListener(_handlePrimaryPagePosition);
    _scrollController.dispose();
    unawaited(_playerSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    if (_player case final player?) unawaited(player.dispose());
    super.dispose();
  }

  void _handlePrimaryPagePosition() {
    final position = widget.primaryPagePosition?.value;
    if (position == null) return;
    final visible = (position - 1).abs() < .04;
    if (visible && !_wasPrimaryVisible && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
      AppLog.debug('community', 'soundscape_scroll_reset_on_entry');
    }
    _wasPrimaryVisible = visible;
  }

  Future<void> _load({bool force = false}) async {
    final timer = Stopwatch()..start();
    AppLog.info('community', 'soundscape_load_started');
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final value = widget.preloader == null
          ? await SoundscapeBootstrapData.fetch(_service)
          : await widget.preloader!.load(force: force);
      if (!mounted) return;
      setState(() {
        _areas = value.areas;
        _posts = value.posts;
        _parks = value.parks;
        if (!_posts.any((post) => !post.isDemo) &&
            _posts.any((post) => post.isDemo)) {
          _demoFilter = _DemoFilter.demo;
        }
      });
      timer.stop();
      AppLog.info(
        'community',
        'soundscape_load_completed',
        fields: {
          'duration_ms': timer.elapsedMilliseconds,
          'area_count': _areas.length,
          'post_count': _posts.length,
          'park_count': _parks.length,
          'startup_preload': widget.preloader != null,
        },
      );
    } on CommunityException catch (error) {
      timer.stop();
      AppLog.warning(
        'community',
        'soundscape_load_failed',
        fields: {'duration_ms': timer.elapsedMilliseconds},
        error: error,
      );
      if (mounted) setState(() => _error = error.message);
    } catch (error, stackTrace) {
      timer.stop();
      AppLog.error(
        'community',
        'soundscape_load_failed',
        fields: {'duration_ms': timer.elapsedMilliseconds},
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = '城市声景暂时没有连上，请稍后刷新。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openFullscreenMap() async {
    AppLog.info('amap', 'soundscape_map_fullscreen_opened');
    final areaId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _FullscreenSoundscapeMap(
          areas: _areas,
          initialAreaId: _selectedAreaId,
          mapImageUrl: _parks.firstOrNull?.mapImageUrl,
          mapProvider: _parks.firstOrNull?.mapProvider ?? 'offline',
          parks: _parks,
        ),
      ),
    );
    if (!mounted || areaId == null) return;
    setState(() {
      _selectedAreaId = areaId;
    });
  }

  List<CommunityPost> get _visiblePosts {
    var values = _posts;
    values = switch (_demoFilter) {
      _DemoFilter.real => values.where((post) => !post.isDemo).toList(),
      _DemoFilter.demo => values.where((post) => post.isDemo).toList(),
    };
    if (_selectedAreaId != null) {
      values = values.where((post) => post.areaId == _selectedAreaId).toList();
    }
    return switch (_view) {
      _SoundscapeView.recent => values,
      _SoundscapeView.waiting =>
        values.where((post) => post.responseCount == 0).toList(),
    };
  }

  SoundscapeArea? get _selectedArea {
    for (final area in _areas) {
      if (area.id == _selectedAreaId) return area;
    }
    return null;
  }

  Future<void> _toggleAudio(CommunityPost post) async {
    if (post.audioUrl.isEmpty) return;
    if (widget.audioStarter case final start?) {
      if (_loadingAudioPostId == post.id) return;
      if (_playingPostId == post.id) {
        setState(() {
          _playingPostId = null;
          _requestedAudioPostId = null;
          _audioPosition = Duration.zero;
          _audioDuration = Duration.zero;
        });
        return;
      }
      setState(() {
        _requestedAudioPostId = post.id;
        _loadingAudioPostId = post.id;
        _playingPostId = null;
        _audioPosition = Duration.zero;
        _audioDuration = Duration.zero;
      });
      try {
        await start(post.audioUrl);
        if (mounted) {
          setState(() {
            _playingPostId = post.id;
            _loadingAudioPostId = null;
          });
        }
      } catch (_) {
        if (mounted) _handleAudioFailure();
      }
      return;
    }
    final player = _player ??= AudioPlayer();
    _playerSubscription ??= player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        if (state == PlayerState.playing) {
          _playingPostId = _requestedAudioPostId;
          _loadingAudioPostId = null;
        } else if (state == PlayerState.paused) {
          _playingPostId = null;
          _loadingAudioPostId = null;
        } else if (state == PlayerState.completed ||
            (state == PlayerState.stopped && _loadingAudioPostId == null)) {
          _resetAudioState();
        }
      });
    });
    _positionSubscription ??= player.onPositionChanged.listen((position) {
      if (!mounted || _requestedAudioPostId == null) return;
      setState(() => _audioPosition = position);
    });
    _durationSubscription ??= player.onDurationChanged.listen((duration) {
      if (!mounted || _requestedAudioPostId == null) return;
      setState(() => _audioDuration = duration);
    });
    if (_loadingAudioPostId == post.id) return;
    if (_requestedAudioPostId == post.id) {
      if (player.state == PlayerState.playing) {
        await player.pause();
      } else if (player.state == PlayerState.paused) {
        await player.resume();
      }
      return;
    }
    try {
      await player.stop();
      await player.setReleaseMode(ReleaseMode.stop);
      if (!mounted) return;
      setState(() {
        _requestedAudioPostId = post.id;
        _loadingAudioPostId = post.id;
        _playingPostId = null;
        _audioPosition = Duration.zero;
        _audioDuration = Duration.zero;
      });
      await player.play(UrlSource(post.audioUrl));
      final duration = await player.getDuration();
      if (mounted && player.state == PlayerState.playing) {
        setState(() {
          _playingPostId = post.id;
          _loadingAudioPostId = null;
          if (duration != null && duration > Duration.zero) {
            _audioDuration = duration;
          }
        });
      }
    } catch (_) {
      if (mounted) _handleAudioFailure();
    }
  }

  void _handleAudioFailure() {
    setState(() {
      _resetAudioState();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('这段声音暂时无法播放。')));
  }

  void _resetAudioState() {
    _requestedAudioPostId = null;
    _loadingAudioPostId = null;
    _playingPostId = null;
    _audioPosition = Duration.zero;
    _audioDuration = Duration.zero;
  }

  Future<void> _seekAudio(CommunityPost post, double progress) async {
    final player = _player;
    if (player == null ||
        _requestedAudioPostId != post.id ||
        _audioDuration <= Duration.zero) {
      return;
    }
    final target = Duration(
      milliseconds: (_audioDuration.inMilliseconds * progress).round(),
    );
    await player.seek(target);
    if (mounted) setState(() => _audioPosition = target);
  }

  Future<void> _assist(CommunityPost post, String choice) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      final alsoHeard = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '你的判断：$choice',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('你在杭州附近也听到过相似声音吗？'),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('只提交判断'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('我也听到过'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (alsoHeard == null) return;
      final updated = await _service.assist(
        post.id,
        choice: choice,
        alsoHeard: alsoHeard,
      );
      if (!mounted) return;
      setState(() {
        _posts = _posts
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('谢谢，你为这条声音补充了一份人类判断。')));
    } on CommunityException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _withdraw(CommunityPost post) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤回这条公开声音？'),
        content: const Text('它会从共听杭州中移除，本机自然册中的原记录不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤回'),
          ),
        ],
      ),
    );
    if (agreed != true) return;
    try {
      await _service.withdraw(post.id);
      await _load(force: true);
    } on CommunityException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _startPublication() async {
    final records = await _recordsLoader();
    if (!mounted) return;
    if (records.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('自然册里还没有声音，先完成一次录音和调查。')));
      return;
    }
    final record = await showModalBottomSheet<ExplorationRecord>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  '选择一条声音线索',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final item = records[index];
                    final detection = item.detections.firstOrNull;
                    final subject =
                        detection?.specificSpecies?.nameZh ??
                        detection?.nameZh ??
                        '待确认声音';
                    return ListTile(
                      key: Key('publication-record-${item.id}'),
                      leading: const CircleAvatar(
                        child: Icon(Icons.graphic_eq_rounded),
                      ),
                      title: Text(subject),
                      subtitle: Text(
                        '${item.createdAt.toLocal().month}月${item.createdAt.toLocal().day}日 · ${item.duration.inSeconds} 秒',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (record == null || !mounted) return;
    final published = await Navigator.of(context).push<CommunityPost>(
      MaterialPageRoute(
        builder: (_) => PublicationPage(record: record, service: _service),
      ),
    );
    if (published == null || !mounted) return;
    setState(() {
      _selectedAreaId = published.areaId;
      _recentAreaId = published.areaId;
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _recentAreaId = null);
    });
    await _load(force: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('你的发现已加入${published.areaName}声景'),
        action: SnackBarAction(label: '查看', onPressed: () {}),
      ),
    );
  }

  Future<void> _showSoundscapeInfo({
    required int realCount,
    required int demoCount,
    required int waitingCount,
  }) => showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('关于共听杭州', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            _SoundscapeInfoRow(
              icon: Icons.graphic_eq_rounded,
              title: '当前数据',
              detail:
                  '$realCount 条真实观察 · $demoCount 条体验示例 · $waitingCount 条等待协助',
            ),
            const SizedBox(height: 12),
            const _SoundscapeInfoRow(
              icon: Icons.shield_outlined,
              title: '隐私范围',
              detail: '只显示公开的模糊区域，不展示录音精确位置或儿童身份。',
            ),
            const SizedBox(height: 12),
            const _SoundscapeInfoRow(
              icon: Icons.science_outlined,
              title: '数据含义',
              detail: '记录数量不代表动物数量，体验示例不作为真实社区趋势。',
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final visible = _visiblePosts;
    final realCount = _posts.where((post) => !post.isDemo).length;
    final demoCount = _posts.where((post) => post.isDemo).length;
    final total = realCount + demoCount;
    final waiting = _posts.where((post) => post.responseCount == 0).length;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5EC),
      appBar: AppBar(
        title: const Text('共听杭州'),
        actions: [
          if (!_loading && _error == null && _posts.isNotEmpty)
            TextButton.icon(
              key: const Key('publish-community-sound'),
              onPressed: _startPublication,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('发布'),
            ),
          IconButton(
            key: const Key('soundscape-info-button'),
            tooltip: '数据与隐私',
            onPressed: () => _showSoundscapeInfo(
              realCount: realCount,
              demoCount: demoCount,
              waitingCount: waiting,
            ),
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          controller: _scrollController,
          key: const PageStorageKey('soundscape-scroll-offset'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
          children: [
            Text(
              total == 0 ? '等待杭州的第一声发现' : '选择城区，听听公开声音',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.18,
              ),
            ),
            const SizedBox(height: 10),
            KeyedSubtree(
              key: const Key('soundscape-map-section'),
              child: _SoundscapeMap(
                areas: _areas,
                loading: _loading,
                selectedAreaId: _selectedAreaId,
                recentAreaId: _recentAreaId,
                onSelected: (areaId) => setState(() {
                  _selectedAreaId = _selectedAreaId == areaId ? null : areaId;
                }),
                onOpenFullscreen: _openFullscreenMap,
                mapImageUrl: _parks.firstOrNull?.mapImageUrl,
                mapProvider: _parks.firstOrNull?.mapProvider ?? 'offline',
              ),
            ),
            if (_loading || _selectedArea != null) ...[
              const SizedBox(height: 10),
              _MapSelectionSummary(area: _selectedArea, loading: _loading),
            ],
            if (!_loading && realCount == 0 && demoCount > 0) ...[
              const SizedBox(height: 10),
              const _PilotDataNotice(),
            ],
            const SizedBox(height: 14),
            SegmentedButton<_SoundscapeView>(
              segments: const [
                ButtonSegment(
                  value: _SoundscapeView.recent,
                  label: Text('最新声音'),
                ),
                ButtonSegment(
                  value: _SoundscapeView.waiting,
                  label: Text('等你辨认'),
                ),
              ],
              selected: {_view},
              showSelectedIcon: false,
              onSelectionChanged: (values) =>
                  setState(() => _view = values.first),
            ),
            const SizedBox(height: 16),
            if (_error != null && !_loading)
              _ErrorCard(message: _error!, onRetry: () => _load(force: true)),
            if (!_loading && _error == null && visible.isEmpty)
              _EmptySoundscape(
                areaSelected: _selectedAreaId != null,
                onPublish: _startPublication,
              ),
            for (final post in visible) ...[
              _CommunitySoundCard(
                post: post,
                activeAudio: _requestedAudioPostId == post.id,
                playing: _playingPostId == post.id,
                loadingAudio: _loadingAudioPostId == post.id,
                audioPosition: _requestedAudioPostId == post.id
                    ? _audioPosition
                    : Duration.zero,
                audioDuration:
                    _requestedAudioPostId == post.id &&
                        _audioDuration > Duration.zero
                    ? _audioDuration
                    : post.duration,
                acting: _acting,
                onPlay: () => _toggleAudio(post),
                onSeek: (progress) => _seekAudio(post, progress),
                onAssist: (choice) => _assist(post, choice),
                onWithdraw: post.ownedByRequester
                    ? () => _withdraw(post)
                    : null,
              ),
              const SizedBox(height: 12),
            ],
            if (widget.onOpenParkGuide != null) ...[
              const SizedBox(height: 6),
              _ParkGuideCrossLink(onTap: widget.onOpenParkGuide!),
            ],
          ],
        ),
      ),
    );
  }
}

class _SoundscapeInfoRow extends StatelessWidget {
  const _SoundscapeInfoRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          color: Color(0xFFE2EEE6),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF174936)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              detail,
              style: const TextStyle(
                color: Color(0xFF66716B),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _PilotDataNotice extends StatelessWidget {
  const _PilotDataNotice();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0CE),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5C16F)),
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 19, color: Color(0xFF795B20)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '杭州真实观察仍在积累，当前展示内容均标记为体验示例。',
              style: TextStyle(
                color: Color(0xFF654D20),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ParkGuideCrossLink extends StatelessWidget {
  const _ParkGuideCrossLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFE5EEE7),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      key: const Key('open-park-guide-from-soundscape'),
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.map_outlined, color: Color(0xFF174936), size: 20),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                '想去现场听？打开亲子游园指南',
                style: TextStyle(
                  color: Color(0xFF174936),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: Color(0xFF174936)),
          ],
        ),
      ),
    ),
  );
}

class _MapSelectionSummary extends StatelessWidget {
  const _MapSelectionSummary({required this.area, required this.loading});

  final SoundscapeArea? area;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final selected = area;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected == null
            ? const Color(0xFFECEFE8)
            : const Color(0xFFE1EEE5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            loading
                ? Icons.graphic_eq_rounded
                : selected == null
                ? Icons.touch_app_outlined
                : Icons.location_on_outlined,
            size: 20,
            color: const Color(0xFF315D4A),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              loading
                  ? '正在接入杭州声景'
                  : selected == null
                  ? '点选城区，看看哪里有新声音'
                  : '${selected.name} · ${selected.postCount} 条线索 · ${selected.waitingCount} 条等待协助',
              style: const TextStyle(
                color: Color(0xFF315045),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (selected != null)
            const Text(
              '再次点按取消',
              style: TextStyle(fontSize: 11, color: Color(0xFF6C7B74)),
            ),
        ],
      ),
    );
  }
}

class _HangzhouMapImage extends StatelessWidget {
  const _HangzhouMapImage({
    required this.mapImageUrl,
    this.filterQuality = FilterQuality.medium,
  });

  final String? mapImageUrl;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final url = mapImageUrl;
    if (url == null || url.isEmpty) return _offlineMap();
    return Image.network(
      url,
      key: const Key('hangzhou-amap-image'),
      fit: BoxFit.cover,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => _offlineMap(),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Stack(
              fit: StackFit.expand,
              children: [
                _offlineMap(),
                const ColoredBox(color: Color(0x0FFFFFFF)),
              ],
            ),
    );
  }

  Widget _offlineMap() => Image.asset(
    'assets/maps/hangzhou_osm.png',
    key: const Key('hangzhou-offline-map'),
    fit: BoxFit.cover,
    filterQuality: filterQuality,
  );
}

class _SoundscapeMap extends StatefulWidget {
  const _SoundscapeMap({
    required this.areas,
    required this.loading,
    required this.selectedAreaId,
    required this.recentAreaId,
    required this.onSelected,
    required this.onOpenFullscreen,
    this.mapImageUrl,
    this.mapProvider = 'offline',
  });
  final List<SoundscapeArea> areas;
  final bool loading;
  final String? selectedAreaId;
  final String? recentAreaId;
  final ValueChanged<String> onSelected;
  final VoidCallback onOpenFullscreen;
  final String? mapImageUrl;
  final String mapProvider;

  @override
  State<_SoundscapeMap> createState() => _SoundscapeMapState();
}

class _SoundscapeMapState extends State<_SoundscapeMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant _SoundscapeMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.areas != widget.areas ||
        oldWidget.recentAreaId != widget.recentAreaId) {
      _pulseController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1176 / 759,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18315449),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) => Stack(
            children: [
              Positioned.fill(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _HangzhouMapImage(mapImageUrl: widget.mapImageUrl),
                    const ColoredBox(color: Color(0x12F5F0DF)),
                    for (final area in widget.areas)
                      Align(
                        alignment:
                            _soundscapeAreaPositions[area.id] ??
                            Alignment.center,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: 0.92,
                            end: widget.recentAreaId == area.id ? 1.1 : 1,
                          ),
                          duration: const Duration(milliseconds: 680),
                          curve: Curves.easeOutBack,
                          builder: (context, scale, child) =>
                              Transform.scale(scale: scale, child: child),
                          child: _AreaRipple(
                            area: area,
                            selected: widget.selectedAreaId == area.id,
                            highlighted: widget.recentAreaId == area.id,
                            pulse: _pulseController.value,
                            onTap: () => widget.onSelected(area.id),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 14,
                top: 14,
                child: _MapLabel(
                  icon: Icons.map_outlined,
                  label: widget.mapProvider == 'amap' ? '高德静态底图' : '离线底图',
                ),
              ),
              Positioned(
                right: 10,
                top: 14,
                child: Row(
                  children: [
                    const _MapLabel(
                      icon: Icons.privacy_tip_outlined,
                      label: '仅显示区域',
                    ),
                    const SizedBox(width: 7),
                    IconButton.filledTonal(
                      key: const Key('open-fullscreen-soundscape-map'),
                      tooltip: '全屏查看杭州声音地图',
                      onPressed: widget.onOpenFullscreen,
                      icon: const Icon(Icons.fullscreen_rounded),
                    ),
                  ],
                ),
              ),
              if (widget.loading) const Positioned.fill(child: _MapLoading()),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FullscreenSoundscapeMap extends StatefulWidget {
  const _FullscreenSoundscapeMap({
    required this.areas,
    required this.parks,
    required this.initialAreaId,
    this.mapImageUrl,
    this.mapProvider = 'offline',
  });

  final List<SoundscapeArea> areas;
  final List<CommunityPark> parks;
  final String? initialAreaId;
  final String? mapImageUrl;
  final String mapProvider;

  @override
  State<_FullscreenSoundscapeMap> createState() =>
      _FullscreenSoundscapeMapState();
}

class _FullscreenSoundscapeMapState extends State<_FullscreenSoundscapeMap> {
  final TransformationController _transformationController =
      TransformationController();
  String? _selectedAreaId;
  String? _selectedParkId;
  bool? _privacyAccepted;
  bool _nativeMapAvailable = false;
  bool _preferNativeMap = true;
  bool _nativeMapReady = false;
  bool _checkingNativeMap = true;
  bool _nativeChoiceShown = false;
  String? _nativeFailureMessage;
  AmapNativeController? _nativeController;
  String? _mapApprovalNumber;
  Timer? _nativeLoadTimer;

  @override
  void initState() {
    super.initState();
    _selectedAreaId = widget.initialAreaId;
    if (nativeAmapSupported) {
      unawaited(_loadPrivacyConsent());
    } else {
      _privacyAccepted = false;
    }
  }

  @override
  void dispose() {
    _nativeLoadTimer?.cancel();
    _transformationController.dispose();
    super.dispose();
  }

  SoundscapeArea? get _selectedArea {
    for (final area in widget.areas) {
      if (area.id == _selectedAreaId) return area;
    }
    return null;
  }

  CommunityPark? get _selectedPark {
    for (final park in widget.parks) {
      if (park.id == _selectedParkId) return park;
    }
    return null;
  }

  bool get _usingNativeMap =>
      nativeAmapSupported &&
      _nativeMapAvailable &&
      _preferNativeMap &&
      _privacyAccepted == true;

  Future<void> _loadPrivacyConsent() async {
    final available = await AmapPrivacyBridge.isAvailable();
    final accepted = available && await AmapPrivacyBridge.hasConsent();
    AppLog.info(
      'amap',
      'native_map_availability_checked',
      fields: {'available': available, 'privacy_accepted': accepted},
    );
    if (mounted) {
      setState(() {
        _nativeMapAvailable = available;
        _privacyAccepted = accepted;
        _preferNativeMap = accepted;
        _checkingNativeMap = false;
        _nativeFailureMessage = available ? null : '当前安装包未启用高德动态地图';
      });
      if (available && !accepted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_offerNativeMap());
        });
      }
    }
  }

  Future<void> _offerNativeMap() async {
    if (_nativeChoiceShown ||
        !_nativeMapAvailable ||
        _privacyAccepted == true) {
      return;
    }
    _nativeChoiceShown = true;
    final enable = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: false,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Padding(
          key: const Key('native-map-choice-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE2EEE6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.public_rounded,
                      color: Color(0xFF174936),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '地图显示方式',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '高德动态地图 · 支持缩放和移动',
                          style: TextStyle(
                            color: Color(0xFF5F6D66),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 17,
                    color: Color(0xFF66736C),
                  ),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '只使用城区与公园公共坐标，不传孩子位置或录音精确位置。',
                      style: TextStyle(
                        color: Color(0xFF66736C),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('continue-offline-map'),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('暂不启用'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const Key('enable-native-amap-first-use'),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('启用动态地图'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (enable == true) {
      await _acceptPrivacyConsent();
    } else {
      setState(() => _preferNativeMap = false);
    }
  }

  Future<void> _acceptPrivacyConsent() async {
    try {
      await AmapPrivacyBridge.accept();
      if (mounted) {
        setState(() {
          _privacyAccepted = true;
          _preferNativeMap = true;
          _nativeMapReady = false;
          _nativeFailureMessage = null;
        });
      }
    } on Object catch (error, stackTrace) {
      if (!mounted) return;
      AppLog.warning(
        'amap',
        'native_map_consent_failed',
        error: error,
        stackTrace: stackTrace,
      );
      setState(() {
        _preferNativeMap = false;
        _nativeFailureMessage = '高德动态地图初始化失败';
      });
    }
  }

  void _onNativeMapCreated(AmapNativeController controller) {
    _nativeController = controller;
    _nativeLoadTimer?.cancel();
    _nativeLoadTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted || _nativeMapReady) return;
      AppLog.warning('amap', 'native_map_failed', error: '地图加载超时');
      setState(() {
        _preferNativeMap = false;
        _nativeFailureMessage = '高德动态地图加载超时';
      });
    });
  }

  void _onNativeMapReady(String? approvalNumber) {
    _nativeLoadTimer?.cancel();
    if (mounted) {
      AppLog.info(
        'amap',
        'native_map_ready',
        fields: {'has_approval_number': approvalNumber?.isNotEmpty == true},
      );
      setState(() {
        _nativeMapReady = true;
        _mapApprovalNumber = approvalNumber;
        _nativeFailureMessage = null;
      });
    }
  }

  void _onNativeMapError(String message) {
    _nativeLoadTimer?.cancel();
    if (!mounted) return;
    AppLog.warning('amap', 'native_map_failed', error: message);
    setState(() {
      _preferNativeMap = false;
      _nativeMapReady = false;
      _nativeFailureMessage = message;
    });
  }

  void _retryNativeMap() {
    if (_privacyAccepted != true) {
      _nativeChoiceShown = false;
      unawaited(_offerNativeMap());
      return;
    }
    setState(() {
      _preferNativeMap = true;
      _nativeMapReady = false;
      _nativeFailureMessage = null;
    });
  }

  Future<void> _revokeMapConsent() async {
    await AmapPrivacyBridge.revoke();
    if (!mounted) return;
    setState(() {
      _privacyAccepted = false;
      _preferNativeMap = false;
      _nativeMapReady = false;
      _mapApprovalNumber = null;
      _nativeFailureMessage = null;
    });
  }

  void _onNativeFeatureTap(String type, String id) {
    if (!mounted) return;
    setState(() {
      if (type == 'park') {
        _selectedParkId = id;
        _selectedAreaId = _selectedPark?.areaId;
      } else {
        _selectedParkId = null;
        _selectedAreaId = id;
      }
    });
  }

  void _setScale(double scale) {
    final target = scale.clamp(1.0, 4.0);
    _transformationController.value = Matrix4.diagonal3Values(
      target,
      target,
      1,
    );
  }

  void _zoomBy(double factor) {
    if (_usingNativeMap) {
      if (factor > 1) {
        unawaited(_nativeController?.zoomIn());
      } else {
        unawaited(_nativeController?.zoomOut());
      }
      return;
    }
    final current = _transformationController.value.getMaxScaleOnAxis();
    _setScale(current * factor);
  }

  void _resetMap() {
    if (_usingNativeMap) {
      unawaited(_nativeController?.reset());
      return;
    }
    _transformationController.value = Matrix4.identity();
  }

  Widget _buildFallbackMap() => GestureDetector(
    onDoubleTap: () {
      final current = _transformationController.value.getMaxScaleOnAxis();
      _setScale(current > 1.2 ? 1 : 2);
    },
    child: InteractiveViewer(
      transformationController: _transformationController,
      minScale: 1,
      maxScale: 4,
      panEnabled: true,
      scaleEnabled: true,
      boundaryMargin: const EdgeInsets.all(160),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _HangzhouMapImage(
            mapImageUrl: widget.mapImageUrl,
            filterQuality: FilterQuality.high,
          ),
          const ColoredBox(color: Color(0x12F5F0DF)),
          for (final area in widget.areas)
            Align(
              alignment: _soundscapeAreaPositions[area.id] ?? Alignment.center,
              child: _AreaRipple(
                area: area,
                selected: area.id == _selectedAreaId,
                highlighted: false,
                pulse: 0,
                onTap: () => setState(() {
                  _selectedParkId = null;
                  _selectedAreaId = area.id;
                }),
              ),
            ),
        ],
      ),
    ),
  );

  List<AmapNativeFeature> get _nativeAreas => widget.areas
      .map((area) {
        final coordinate = _soundscapeAreaCoordinates[area.id];
        if (coordinate == null) return null;
        return AmapNativeFeature(
          id: area.id,
          name: area.name,
          latitude: coordinate.$1,
          longitude: coordinate.$2,
          postCount: area.postCount,
          waitingCount: area.waitingCount,
        );
      })
      .whereType<AmapNativeFeature>()
      .toList(growable: false);

  List<AmapNativeFeature> get _nativeParks => widget.parks
      .map((park) {
        final latitude = park.latitude;
        final longitude = park.longitude;
        if (latitude == null || longitude == null) return null;
        return AmapNativeFeature(
          id: park.id,
          name: park.name,
          latitude: latitude,
          longitude: longitude,
        );
      })
      .whereType<AmapNativeFeature>()
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final selected = _selectedArea;
    final selectedPark = _selectedPark;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5EC),
      appBar: AppBar(
        title: const Text('杭州声音地图'),
        backgroundColor: const Color(0xF2F8F5EC),
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            key: const Key('map-privacy-button'),
            tooltip: '地图来源与隐私',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('仅显示区域'),
                content: Text(
                  '应用只向地图传入城区和公园的公共坐标，不传入孩子位置或录音精确坐标。高德地图可能按其隐私政策处理提供地图所需的设备与网络信息。\n\n'
                  '${_mapApprovalNumber == null ? '' : '地图审图号：$_mapApprovalNumber\n'}'
                  '这些区域声景不代表专业生态分布。',
                ),
                actions: [
                  if (_privacyAccepted == true)
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _revokeMapConsent();
                      },
                      child: const Text('停用高德地图'),
                    ),
                  if (_nativeMapAvailable && _privacyAccepted != true)
                    FilledButton(
                      key: const Key('enable-native-amap'),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _acceptPrivacyConsent();
                      },
                      child: const Text('启用高德动态地图'),
                    ),
                  TextButton(
                    onPressed: AmapPrivacyBridge.openPrivacyPolicy,
                    child: const Text('高德隐私政策'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.shield_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _usingNativeMap
                ? NativeAmapView(
                    areas: _nativeAreas,
                    parks: _nativeParks,
                    onCreated: _onNativeMapCreated,
                    onReady: _onNativeMapReady,
                    onFeatureTap: _onNativeFeatureTap,
                    onError: _onNativeMapError,
                  )
                : _buildFallbackMap(),
          ),
          Positioned(
            right: 14,
            top: 14,
            child: _MapZoomControls(
              onZoomIn: () => _zoomBy(1.35),
              onZoomOut: () => _zoomBy(1 / 1.35),
              onReset: _resetMap,
            ),
          ),
          if (_usingNativeMap && !_nativeMapReady)
            const Positioned.fill(child: _MapLoading()),
          Positioned(
            left: 14,
            top: 14,
            right: 78,
            child: _nativeFailureMessage == null
                ? _MapSourceBadge(
                    dynamicMap: _usingNativeMap,
                    checking: _checkingNativeMap,
                  )
                : _NativeMapFailureCard(
                    message: _nativeFailureMessage!,
                    onRetry: _retryNativeMap,
                  ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: SafeArea(
              top: false,
              child: _FullscreenAreaPanel(
                area: selected,
                park: selectedPark,
                onOpen: selected == null
                    ? null
                    : () => Navigator.pop(context, selected.id),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapSourceBadge extends StatelessWidget {
  const _MapSourceBadge({required this.dynamicMap, required this.checking});

  final bool dynamicMap;
  final bool checking;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF5FFFDF7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9D6CA)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              dynamicMap ? Icons.public_rounded : Icons.map_outlined,
              size: 16,
              color: const Color(0xFF174936),
            ),
            const SizedBox(width: 6),
            Text(
              checking
                  ? '正在检查地图来源'
                  : dynamicMap
                  ? '高德动态地图'
                  : '离线底图',
              style: const TextStyle(
                color: Color(0xFF174936),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NativeMapFailureCard extends StatelessWidget {
  const _NativeMapFailureCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xF5FFF8ED),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE1CDA3)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
      child: Row(
        children: [
          const Icon(Icons.map_outlined, size: 17, color: Color(0xFF795B20)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF5F4B25),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

class _MapZoomControls extends StatelessWidget {
  const _MapZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xF7FFFDF5),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0x22315449)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x18315449),
          blurRadius: 14,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('soundscape-map-zoom-in'),
          tooltip: '放大地图',
          onPressed: onZoomIn,
          icon: const Icon(Icons.add_rounded),
        ),
        const SizedBox(width: 32, child: Divider(height: 1)),
        IconButton(
          key: const Key('soundscape-map-zoom-out'),
          tooltip: '缩小地图',
          onPressed: onZoomOut,
          icon: const Icon(Icons.remove_rounded),
        ),
        const SizedBox(width: 32, child: Divider(height: 1)),
        IconButton(
          key: const Key('soundscape-map-reset'),
          tooltip: '复位地图',
          onPressed: onReset,
          icon: const Icon(Icons.center_focus_strong_rounded),
        ),
      ],
    ),
  );
}

class _FullscreenAreaPanel extends StatelessWidget {
  const _FullscreenAreaPanel({
    required this.area,
    required this.park,
    required this.onOpen,
  });

  final SoundscapeArea? area;
  final CommunityPark? park;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final selected = area;
    final selectedPark = park;
    if (selected == null && selectedPark == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF5FFFDF5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD9D6CA)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F315449),
                blurRadius: 16,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.touch_app_outlined,
                  size: 18,
                  color: Color(0xFF174936),
                ),
                SizedBox(width: 7),
                Text(
                  '点选地区查看声音',
                  style: TextStyle(
                    color: Color(0xFF174936),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Material(
      key: const Key('fullscreen-area-panel'),
      color: const Color(0xFAFFFDF5),
      elevation: 8,
      shadowColor: const Color(0x24315449),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('open-selected-soundscape-area'),
        borderRadius: BorderRadius.circular(24),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: Color(0xFFE2EEE6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.hearing_rounded,
                  color: Color(0xFF174936),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedPark?.name ?? selected!.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF174936),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      selectedPark != null
                          ? '${selectedPark.areaName} · ${selectedPark.habitatTags.take(2).join(' · ')}'
                          : '${selected!.postCount} 条声音 · ${selected.waitingCount} 条待协助',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF5E6D66),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFF174936),
                foregroundColor: Colors.white,
                child: Icon(Icons.arrow_forward_rounded, size: 19),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapLabel extends StatelessWidget {
  const _MapLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xDDF8F8F1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0x22315449)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF315D4A)),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF315D4A),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .4,
          ),
        ),
      ],
    ),
  );
}

class _MapLoading extends StatelessWidget {
  const _MapLoading();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0x33F8F5EC),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xEFFFFFFA),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Color(0x18315449), blurRadius: 12),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 9),
            Text('正在接入城市声景', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}

class _AreaRipple extends StatelessWidget {
  const _AreaRipple({
    required this.area,
    required this.selected,
    required this.highlighted,
    required this.pulse,
    required this.onTap,
  });
  final SoundscapeArea area;
  final bool selected;
  final bool highlighted;
  final double pulse;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '${area.name}，${area.postCount} 条声音线索',
    button: true,
    child: SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (area.postCount > 0 || highlighted)
            Transform.scale(
              scale: .76 + pulse * .28,
              child: Opacity(
                opacity: .36 * (1 - pulse),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: highlighted
                          ? const Color(0xFFD4A45C)
                          : const Color(0xFF315D4A),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          InkWell(
            key: Key('soundscape-area-${area.id}'),
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: selected || highlighted
                  ? 58
                  : area.postCount == 0
                  ? 44
                  : 52,
              height: selected || highlighted
                  ? 58
                  : area.postCount == 0
                  ? 44
                  : 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? const Color(0xFF174936)
                    : const Color(0xF7FFFDF5),
                border: Border.all(
                  color: highlighted
                      ? const Color(0xFFD4A45C)
                      : const Color(0x66315449),
                  width: highlighted ? 3 : 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x29315449),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    area.name,
                    style: TextStyle(
                      fontSize: area.postCount == 0 ? 9 : 10,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : const Color(0xFF174936),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    area.postCount == 0 ? '待发现' : '${area.postCount} 条',
                    style: TextStyle(
                      fontSize: area.postCount == 0 ? 8 : 10,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? const Color(0xFFDDECE3)
                          : const Color(0xFF44695A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CommunitySoundCard extends StatelessWidget {
  const _CommunitySoundCard({
    required this.post,
    required this.activeAudio,
    required this.playing,
    required this.loadingAudio,
    required this.audioPosition,
    required this.audioDuration,
    required this.acting,
    required this.onPlay,
    required this.onSeek,
    required this.onAssist,
    this.onWithdraw,
  });
  final CommunityPost post;
  final bool activeAudio;
  final bool playing;
  final bool loadingAudio;
  final Duration audioPosition;
  final Duration audioDuration;
  final bool acting;
  final VoidCallback onPlay;
  final ValueChanged<double> onSeek;
  final ValueChanged<String> onAssist;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final local = post.observedAt.toLocal();
    final candidates = post.candidateNames
        .where((item) => item != '暂时无法判断')
        .toSet()
        .toList(growable: false);
    final choices = candidates.isEmpty
        ? <String>[post.subject, '暂时无法判断']
        : <String>[...candidates, '暂时无法判断'];
    final isDemo = post.isDemo;
    final durationMilliseconds = audioDuration.inMilliseconds;
    final progress = durationMilliseconds <= 0
        ? 0.0
        : (audioPosition.inMilliseconds / durationMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble();
    return Card(
      key: Key('community-post-${post.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      _PostBadge(
                        label: '${post.areaName} · ${post.soundType}',
                        color: const Color(0xFFE8EFE8),
                      ),
                      if (isDemo)
                        const _PostBadge(
                          label: '比赛体验',
                          color: Color(0xFFFFE5B6),
                          foreground: Color(0xFF73501B),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${local.month}月${local.day}日',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (onWithdraw != null)
                  AppPopoverMenu<String>(
                    tooltip: '公开记录操作',
                    minWidth: 190,
                    onSelected: (value) {
                      if (value == 'withdraw') onWithdraw!();
                    },
                    actions: const [
                      AppPopoverAction(
                        value: 'withdraw',
                        label: '撤回公开记录',
                        icon: Icons.visibility_off_outlined,
                        destructive: true,
                      ),
                    ],
                    child: const SizedBox.square(
                      dimension: 44,
                      child: Icon(Icons.more_horiz_rounded),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              post.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF183C2E),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (post.mediaAssets.isNotEmpty) ...[
              const SizedBox(height: 10),
              _PostMediaPreview(asset: post.mediaAssets.first),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton.filled(
                  key: Key('play-community-${post.id}'),
                  tooltip: loadingAudio
                      ? '正在加载声音'
                      : (playing ? '暂停' : (activeAudio ? '继续播放' : '先听声音')),
                  onPressed: post.audioUrl.isEmpty || loadingAudio
                      ? null
                      : onPlay,
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: loadingAudio
                        ? const SizedBox.square(
                            key: Key('community-audio-loading'),
                            dimension: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            key: ValueKey(playing),
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              loadingAudio
                                  ? '正在读取声音…'
                                  : (playing
                                        ? '正在播放'
                                        : (activeAudio ? '已暂停' : '播放声音')),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: const Color(0xFF466157),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                          Text(
                            '${_formatAudioDuration(audioPosition)} / ${_formatAudioDuration(audioDuration)}',
                            key: Key('community-audio-time-${post.id}'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF60756D)),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          activeTrackColor: const Color(0xFF1D6B50),
                          inactiveTrackColor: const Color(0xFFD6E2DB),
                          disabledActiveTrackColor: const Color(0xFF8EAAA0),
                          disabledInactiveTrackColor: const Color(0xFFD6E2DB),
                          thumbColor: const Color(0xFF1D6B50),
                          overlayColor: const Color(0x221D6B50),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                            disabledThumbRadius: 0,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 15,
                          ),
                        ),
                        child: Slider(
                          key: Key('community-audio-progress-${post.id}'),
                          value: progress,
                          onChanged: activeAudio && durationMilliseconds > 0
                              ? onSeek
                              : null,
                          semanticFormatterCallback: (value) =>
                              '播放进度 ${(value * 100).round()}%',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '先听，再判断这条线索更像谁？',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: choices
                  .take(4)
                  .map(
                    (choice) => OutlinedButton(
                      onPressed: acting ? null : () => onAssist(choice),
                      child: Text(choice),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.people_alt_outlined, size: 17),
                const SizedBox(width: 6),
                Text(
                  post.responseCount == 0
                      ? '还没有人判断，等待第一位探员'
                      : '${post.responseCount} 位探员参与判断',
                ),
              ],
            ),
            if (post.responseSummary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                post.responseSummary.entries
                    .map((item) => '${item.key} ${item.value}')
                    .join(' · '),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '由 ${post.alias} 匿名贡献 · 公众协助中，尚未专业确认',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PostBadge extends StatelessWidget {
  const _PostBadge({
    required this.label,
    required this.color,
    this.foreground = const Color(0xFF315045),
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label, style: TextStyle(fontSize: 12, color: foreground)),
  );
}

class _PostMediaPreview extends StatelessWidget {
  const _PostMediaPreview({required this.asset});
  final CommunityMediaAsset asset;

  @override
  Widget build(BuildContext context) {
    final label = switch (asset.sourceType) {
      'original' => '真实素材',
      'composed' => 'AI合成作品',
      _ => 'AI生成内容',
    };
    if (asset.mediaType == 'image' || asset.mediaType == 'thumbnail') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                asset.url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFFE8EFE8),
                  child: Center(
                    child: Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: _PostBadge(label: label, color: const Color(0xEFFFFDF5)),
            ),
          ],
        ),
      );
    }
    return InkWell(
      key: Key('open-community-video-${asset.id}'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              CommunityVideoPage(url: asset.url, sourceLabel: label),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFE8EFE8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.play_circle_outline_rounded),
            const SizedBox(width: 9),
            Expanded(child: Text('自然明信片视频 · $label')),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

String _formatAudioDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 359999).toInt();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _EmptySoundscape extends StatelessWidget {
  const _EmptySoundscape({required this.areaSelected, required this.onPublish});
  final bool areaSelected;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 2),
    padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
    decoration: BoxDecoration(
      color: const Color(0xFFE8EFE7),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(
            color: Color(0xFF315D4A),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.hearing_rounded,
            color: Color(0xFFF8F5EC),
            size: 27,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '第一声计划 · 0 → 1',
                style: TextStyle(
                  color: Color(0xFF6B775E),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                areaSelected ? '这个城区正在等待一条新声音' : '成为第一位点亮杭州声景的探员',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF183C2E),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '完成本地调查后，可匿名贡献关键片段；只公开城区，随时可以撤回。',
                style: TextStyle(
                  color: Color(0xFF5D6D65),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('empty-publish-community-sound'),
                onPressed: onPublish,
                icon: const Icon(Icons.radar_rounded, size: 18),
                label: const Text('发布第一声'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 34),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重新连接'),
          ),
        ],
      ),
    ),
  );
}
