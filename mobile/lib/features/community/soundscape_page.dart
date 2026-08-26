import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/community/route_progress_store.dart';
import 'package:nature_sound_detective/core/storage/exploration_record.dart';
import 'package:nature_sound_detective/core/storage/exploration_store.dart';
import 'package:nature_sound_detective/features/community/community_video_page.dart';
import 'package:nature_sound_detective/features/community/exploration_route_page.dart';
import 'package:nature_sound_detective/features/community/publication_page.dart';

enum _SoundscapeView { recent, waiting, mission }

enum _DemoFilter { all, real, demo }

const _soundscapeAreaPositions = <String, Alignment>{
  'yuhang': Alignment(-0.78, -0.68),
  'gongshu': Alignment(-0.34, -0.46),
  'xihu': Alignment(-0.58, -0.06),
  'shangcheng': Alignment(-0.18, 0.16),
  'binjiang': Alignment(-0.07, 0.64),
  'xiaoshan': Alignment(0.36, 0.66),
};

class SoundscapePage extends StatefulWidget {
  const SoundscapePage({
    super.key,
    this.service,
    this.explorationStore,
    this.recordsLoader,
    this.routeProgressStore,
  });

  final CommunityService? service;
  final ExplorationStore? explorationStore;
  final Future<List<ExplorationRecord>> Function()? recordsLoader;
  final RouteProgressStore? routeProgressStore;

  @override
  State<SoundscapePage> createState() => _SoundscapePageState();
}

class _SoundscapePageState extends State<SoundscapePage> {
  late final CommunityService _service;
  late final Future<List<ExplorationRecord>> Function() _recordsLoader;
  late final RouteProgressStore _routeProgressStore;
  final AudioPlayer _player = AudioPlayer();
  List<SoundscapeArea> _areas = const [];
  List<CommunityPost> _posts = const [];
  List<CommunityPark> _parks = const [];
  List<CommunitySite> _parkSites = const [];
  String? _selectedParkId;
  String? _selectedParkZoneId;
  DailyNatureBrief? _dailyBrief;
  EcologySnapshot? _ecologySnapshot;
  List<ExplorationRoute> _routes = const [];
  String? _selectedAreaId;
  String? _playingPostId;
  String? _recentAreaId;
  String? _error;
  bool _loading = true;
  bool _acting = false;
  _SoundscapeView _view = _SoundscapeView.recent;
  _DemoFilter _demoFilter = _DemoFilter.all;
  StreamSubscription<PlayerState>? _playerSubscription;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? HttpCommunityService();
    final store = widget.explorationStore ?? FileExplorationStore();
    _recordsLoader = widget.recordsLoader ?? store.list;
    _routeProgressStore = widget.routeProgressStore ?? FileRouteProgressStore();
    _playerSubscription = _player.onPlayerStateChanged.listen((state) {
      if (mounted && state != PlayerState.playing) {
        setState(() => _playingPostId = null);
      }
    });
    _load();
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    unawaited(_playerSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final values = await Future.wait([
        _service.listAreas(),
        _service.listPosts(),
        _service.listParks(),
      ]);
      if (!mounted) return;
      setState(() {
        _areas = values[0] as List<SoundscapeArea>;
        _posts = values[1] as List<CommunityPost>;
        _parks = values[2] as List<CommunityPark>;
        _selectedParkId ??= _parks.firstOrNull?.id;
      });
      if (_selectedParkId != null) await _loadParkInsight(_selectedParkId!);
    } on CommunityException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '城市声景暂时没有连上，请稍后刷新。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadParkInsight(String parkId) async {
    try {
      final values = await Future.wait([
        _service.dailyBrief(parkId),
        _service.ecologySnapshot(parkId),
        _service.listRoutes(parkId),
        _service.listSites(parkId: parkId),
      ]);
      if (!mounted || _selectedParkId != parkId) return;
      setState(() {
        _dailyBrief = values[0] as DailyNatureBrief;
        _ecologySnapshot = values[1] as EcologySnapshot;
        _routes = values[2] as List<ExplorationRoute>;
        _parkSites = values[3] as List<CommunitySite>;
      });
    } catch (_) {
      if (mounted && _selectedParkId == parkId) {
        setState(() {
          _dailyBrief = null;
          _ecologySnapshot = null;
          _routes = const [];
          _parkSites = const [];
        });
      }
    }
  }

  Future<void> _openRoute(ExplorationRoute route) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ExplorationRoutePage(route: route, store: _routeProgressStore),
      ),
    );
  }

  Future<void> _openFullscreenMap() async {
    final areaId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _FullscreenSoundscapeMap(
          areas: _areas,
          initialAreaId: _selectedAreaId,
        ),
      ),
    );
    if (!mounted || areaId == null) return;
    setState(() {
      _selectedParkZoneId = null;
      _selectedAreaId = areaId;
    });
  }

  List<CommunityPost> get _visiblePosts {
    var values = _posts;
    values = switch (_demoFilter) {
      _DemoFilter.all => values,
      _DemoFilter.real => values.where((post) => !post.isDemo).toList(),
      _DemoFilter.demo => values.where((post) => post.isDemo).toList(),
    };
    if (_selectedAreaId != null) {
      values = values.where((post) => post.areaId == _selectedAreaId).toList();
    }
    if (_selectedParkZoneId != null) {
      values = values
          .where(
            (post) =>
                post.parkId == _selectedParkId &&
                post.zoneId == _selectedParkZoneId,
          )
          .toList();
    }
    return switch (_view) {
      _SoundscapeView.recent => values,
      _SoundscapeView.waiting =>
        values.where((post) => post.responseCount == 0).toList(),
      _SoundscapeView.mission =>
        values
            .where((post) => {'鸟鸣', '鸣虫', '蛙鸣'}.contains(post.soundType))
            .toList(),
    };
  }

  SoundscapeArea? get _selectedArea {
    for (final area in _areas) {
      if (area.id == _selectedAreaId) return area;
    }
    return null;
  }

  Future<void> _toggleAudio(CommunityPost post) async {
    if (_playingPostId == post.id) {
      await _player.stop();
      return;
    }
    if (post.audioUrl.isEmpty) return;
    try {
      await _player.play(UrlSource(post.audioUrl));
      if (mounted) setState(() => _playingPostId = post.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这段声音暂时无法播放。')));
    }
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
      await _load();
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
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('自然册里还没有声音'),
          content: const Text('先完成一次录音和调查，再把最有价值的声音线索加入杭州声景。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
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
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('你的发现已加入${published.areaName}声景'),
        action: SnackBarAction(label: '查看', onPressed: () {}),
      ),
    );
  }

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
            IconButton(
              key: const Key('publish-community-sound'),
              tooltip: '发布线索',
              onPressed: _startPublication,
              icon: const Icon(Icons.radar_rounded),
            ),
          IconButton(
            tooltip: '隐私说明',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('区域级城市声景'),
                content: const Text('地图只展示经过授权的模糊区域，不代表精确位置或专业生态分布。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.shield_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
          children: [
            Text(
              total == 0 ? '等待杭州的第一声发现' : '今天，杭州正在共同倾听',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.18,
              ),
            ),
            const SizedBox(height: 6),
            Text('$realCount 条真实观察 · $demoCount 条体验示例 · $waiting 条等待协助'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final value in _DemoFilter.values)
                  ChoiceChip(
                    key: Key('demo-filter-${value.name}'),
                    label: Text(switch (value) {
                      _DemoFilter.all => '全部',
                      _DemoFilter.real => '真实观察',
                      _DemoFilter.demo => '体验示例',
                    }),
                    selected: _demoFilter == value,
                    onSelected: (_) => setState(() => _demoFilter = value),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_parks.isNotEmpty) ...[
              Text('试点公园', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final park in _parks) ...[
                      ChoiceChip(
                        key: Key('community-park-${park.id}'),
                        label: Text(park.name),
                        selected: _selectedParkId == park.id,
                        onSelected: (_) {
                          setState(() {
                            _selectedParkId = park.id;
                            _dailyBrief = null;
                            _ecologySnapshot = null;
                            _routes = const [];
                            _parkSites = const [];
                            _selectedParkZoneId = null;
                          });
                          unawaited(_loadParkInsight(park.id));
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_dailyBrief case final brief?)
                _DailyNatureBriefCard(brief: brief, snapshot: _ecologySnapshot),
              if (_parkSites.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ParkZoneSoundMap(
                  sites: _parkSites,
                  posts: _posts
                      .where((post) => post.parkId == _selectedParkId)
                      .toList(growable: false),
                  selectedZoneId: _selectedParkZoneId,
                  onSelected: (zoneId) => setState(() {
                    _selectedAreaId = null;
                    _selectedParkZoneId = _selectedParkZoneId == zoneId
                        ? null
                        : zoneId;
                  }),
                ),
              ],
              if (_routes case [final route, ...]) ...[
                const SizedBox(height: 12),
                _ExplorationRouteCard(
                  route: route,
                  onOpen: () => _openRoute(route),
                ),
              ],
              const SizedBox(height: 18),
            ],
            _SoundscapeMap(
              areas: _areas,
              loading: _loading,
              selectedAreaId: _selectedAreaId,
              recentAreaId: _recentAreaId,
              onSelected: (areaId) => setState(() {
                _selectedParkZoneId = null;
                _selectedAreaId = _selectedAreaId == areaId ? null : areaId;
              }),
              onOpenFullscreen: _openFullscreenMap,
            ),
            const SizedBox(height: 10),
            _MapSelectionSummary(area: _selectedArea, loading: _loading),
            const SizedBox(height: 16),
            SegmentedButton<_SoundscapeView>(
              segments: const [
                ButtonSegment(
                  value: _SoundscapeView.recent,
                  label: Text('今日新声'),
                ),
                ButtonSegment(
                  value: _SoundscapeView.waiting,
                  label: Text('等待协助'),
                ),
                ButtonSegment(
                  value: _SoundscapeView.mission,
                  label: Text('本周任务'),
                ),
              ],
              selected: {_view},
              showSelectedIcon: false,
              onSelectionChanged: (values) =>
                  setState(() => _view = values.first),
            ),
            if (_view == _SoundscapeView.mission) ...[
              const SizedBox(height: 14),
              const _MissionBanner(),
            ],
            const SizedBox(height: 16),
            if (_error != null && !_loading)
              _ErrorCard(message: _error!, onRetry: _load),
            if (!_loading && _error == null && visible.isEmpty)
              _EmptySoundscape(
                areaSelected: _selectedAreaId != null,
                onPublish: _startPublication,
              ),
            for (final post in visible) ...[
              _CommunitySoundCard(
                post: post,
                playing: _playingPostId == post.id,
                acting: _acting,
                onPlay: () => _toggleAudio(post),
                onAssist: (choice) => _assist(post, choice),
                onWithdraw: post.ownedByRequester
                    ? () => _withdraw(post)
                    : null,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
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

class _ParkZoneSoundMap extends StatelessWidget {
  const _ParkZoneSoundMap({
    required this.sites,
    required this.posts,
    required this.selectedZoneId,
    required this.onSelected,
  });

  final List<CommunitySite> sites;
  final List<CommunityPost> posts;
  final String? selectedZoneId;
  final ValueChanged<String> onSelected;

  String _zoneCountLabel(String zoneId) {
    final values = posts.where((post) => post.zoneId == zoneId).toList();
    final real = values.where((post) => !post.isDemo).length;
    final demo = values.where((post) => post.isDemo).length;
    if (real > 0) return '$real 条真实${demo > 0 ? ' · $demo 条体验' : ''}';
    return '$demo 条体验';
  }

  @override
  Widget build(BuildContext context) {
    const alignments = [
      Alignment(-.82, .55),
      Alignment(0, -.7),
      Alignment(.82, .45),
    ];
    return Container(
      key: const Key('park-zone-sound-map'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF244E3D),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.park_outlined, color: Color(0xFFF5F1E5)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '公园分区声景',
                  style: TextStyle(
                    color: Color(0xFFF5F1E5),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                selectedZoneId == null ? '点选查看' : '已筛选',
                style: const TextStyle(color: Color(0xFFCFE0D5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 148,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: Center(
                    child: Icon(
                      Icons.eco_outlined,
                      size: 116,
                      color: Color(0x1828A274),
                    ),
                  ),
                ),
                for (final (index, site) in sites.take(3).indexed)
                  Align(
                    alignment: alignments[index],
                    child: InkWell(
                      key: Key('park-zone-${site.zoneId}'),
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onSelected(site.zoneId),
                      child: Container(
                        width: 104,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selectedZoneId == site.zoneId
                              ? const Color(0xFFFFE5A8)
                              : const Color(0xFFF6F2E8),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.hearing_rounded, size: 18),
                            const SizedBox(height: 3),
                            Text(
                              site.zoneName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _zoneCountLabel(site.zoneId),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Text(
            '仅显示公开分区，不代表录音的精确位置。',
            style: TextStyle(color: Color(0xFFCFE0D5), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _DailyNatureBriefCard extends StatelessWidget {
  const _DailyNatureBriefCard({required this.brief, this.snapshot});
  final DailyNatureBrief brief;
  final EcologySnapshot? snapshot;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFE8F0E8),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wb_sunny_outlined, size: 19),
              const SizedBox(width: 8),
              const Text('今日自然声讯'),
              const Spacer(),
              _PostBadge(
                label: '数据${_sufficiencyLabel(brief.dataSufficiency)}',
                color: const Color(0xFFFFF7DC),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(brief.headline, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(brief.summary),
          if (brief.facts.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final fact in brief.facts) Text('· $fact'),
          ],
          if (brief.possibleExplanations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('为什么可能这样', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            for (final explanation in brief.possibleExplanations)
              Text('· $explanation'),
          ],
          const SizedBox(height: 12),
          Text('今日小任务', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(brief.mission),
          const SizedBox(height: 10),
          Text(brief.disclaimer, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );

  static String _sufficiencyLabel(String value) => switch (value) {
    'high' => '充分',
    'medium' => '中等',
    _ => '不足',
  };
}

class _ExplorationRouteCard extends StatelessWidget {
  const _ExplorationRouteCard({required this.route, required this.onOpen});

  final ExplorationRoute route;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('exploration-route-${route.id}'),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF2D8),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.route_outlined, size: 20),
            const SizedBox(width: 8),
            const Text('亲子自然探索'),
            const Spacer(),
            Text('${route.durationMinutes}分钟 · ${route.distanceKm}公里'),
          ],
        ),
        const SizedBox(height: 10),
        Text(route.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _PostBadge(
              label: '${route.ageMin}岁以上',
              color: const Color(0xFFFFFDF5),
            ),
            for (final tag in route.tags)
              _PostBadge(label: tag, color: const Color(0xFFFFFDF5)),
          ],
        ),
        const SizedBox(height: 12),
        for (final (index, stop) in route.stops.indexed) ...[
          Text(
            '${index + 1}. ${stop.mission}（约${stop.minutes}分钟）',
            style: const TextStyle(height: 1.4),
          ),
          if (index < route.stops.length - 1) const SizedBox(height: 6),
        ],
        const SizedBox(height: 10),
        Text(route.disclaimer, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: Key('open-exploration-route-${route.id}'),
          onPressed: onOpen,
          icon: const Icon(Icons.directions_walk_rounded),
          label: const Text('开始探索'),
        ),
      ],
    ),
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
  });
  final List<SoundscapeArea> areas;
  final bool loading;
  final String? selectedAreaId;
  final String? recentAreaId;
  final ValueChanged<String> onSelected;
  final VoidCallback onOpenFullscreen;

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
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 2.4,
                  panEnabled: true,
                  scaleEnabled: true,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/maps/hangzhou_osm.png',
                        key: const Key('hangzhou-offline-map'),
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                      ),
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
              ),
              const Positioned(
                left: 14,
                top: 14,
                child: _MapLabel(icon: Icons.map_outlined, label: '杭州实景'),
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
              const Positioned(
                left: 16,
                bottom: 12,
                child: Text(
                  '双指缩放 · 点击右上角全屏查看',
                  style: TextStyle(
                    color: Color(0xFF61746B),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
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
    required this.initialAreaId,
  });

  final List<SoundscapeArea> areas;
  final String? initialAreaId;

  @override
  State<_FullscreenSoundscapeMap> createState() =>
      _FullscreenSoundscapeMapState();
}

class _FullscreenSoundscapeMapState extends State<_FullscreenSoundscapeMap> {
  final TransformationController _transformationController =
      TransformationController();
  String? _selectedAreaId;
  bool _showGestureHint = true;
  Timer? _gestureHintTimer;

  @override
  void initState() {
    super.initState();
    _selectedAreaId = widget.initialAreaId;
    _gestureHintTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showGestureHint = false);
    });
  }

  @override
  void dispose() {
    _gestureHintTimer?.cancel();
    _transformationController.dispose();
    super.dispose();
  }

  SoundscapeArea? get _selectedArea {
    for (final area in widget.areas) {
      if (area.id == _selectedAreaId) return area;
    }
    return null;
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
    final current = _transformationController.value.getMaxScaleOnAxis();
    _setScale(current * factor);
  }

  void _resetMap() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedArea;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5EC),
      appBar: AppBar(
        title: const Text('杭州声音地图'),
        backgroundColor: const Color(0xF2F8F5EC),
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: '地图隐私说明',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('仅显示区域'),
                content: const Text('地图不展示录音的精确位置，也不代表专业生态分布。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('知道了'),
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
            child: GestureDetector(
              onDoubleTap: () {
                final current = _transformationController.value
                    .getMaxScaleOnAxis();
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
                    Image.asset(
                      'assets/maps/hangzhou_osm.png',
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                    const ColoredBox(color: Color(0x12F5F0DF)),
                    for (final area in widget.areas)
                      Align(
                        alignment:
                            _soundscapeAreaPositions[area.id] ??
                            Alignment.center,
                        child: _AreaRipple(
                          area: area,
                          selected: area.id == _selectedAreaId,
                          highlighted: false,
                          pulse: 0,
                          onTap: () => setState(() {
                            _selectedAreaId = area.id;
                            _showGestureHint = false;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ),
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
          if (_showGestureHint)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 166,
              child: Center(child: _MapGestureHint()),
            ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: SafeArea(
              top: false,
              child: _FullscreenAreaPanel(
                area: selected,
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

class _MapGestureHint extends StatelessWidget {
  const _MapGestureHint();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xE6174936),
      borderRadius: BorderRadius.circular(22),
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Text(
        '双指缩放 · 单指移动 · 双击放大',
        style: TextStyle(color: Colors.white, fontSize: 12),
      ),
    ),
  );
}

class _FullscreenAreaPanel extends StatelessWidget {
  const _FullscreenAreaPanel({required this.area, required this.onOpen});

  final SoundscapeArea? area;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final selected = area;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFAFFFDF5),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24315449),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 15, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selected?.name ?? '选择一个城区',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF174936),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              selected == null
                  ? '点击地图上的声音节点查看区域声景'
                  : '${selected.postCount} 条声音 · ${selected.waitingCount} 条待协助',
              style: const TextStyle(color: Color(0xFF5E6D66)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('open-selected-soundscape-area'),
              onPressed: onOpen,
              icon: const Icon(Icons.hearing_rounded),
              label: const Text('查看这里的声音'),
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.shield_outlined, size: 16, color: Color(0xFF7A847F)),
                SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '仅显示区域，不展示精确录音位置',
                    style: TextStyle(color: Color(0xFF7A847F), fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
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
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (area.postCount > 0 || highlighted)
            Transform.scale(
              scale: .76 + pulse * .28,
              child: Opacity(
                opacity: .36 * (1 - pulse),
                child: Container(
                  width: 68,
                  height: 68,
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
                  ? 62
                  : area.postCount == 0
                  ? 48
                  : 56,
              height: selected || highlighted
                  ? 62
                  : area.postCount == 0
                  ? 48
                  : 56,
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
          if (area.waitingCount > 0)
            Positioned(
              right: 3,
              top: 4,
              child: Container(
                width: 17,
                height: 17,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A45C),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFFDF5), width: 2),
                ),
                child: const Icon(
                  Icons.question_mark_rounded,
                  size: 10,
                  color: Color(0xFF503814),
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
    required this.playing,
    required this.acting,
    required this.onPlay,
    required this.onAssist,
    this.onWithdraw,
  });
  final CommunityPost post;
  final bool playing;
  final bool acting;
  final VoidCallback onPlay;
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
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'withdraw') onWithdraw!();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'withdraw', child: Text('撤回公开记录')),
                    ],
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
              children: [
                IconButton.filled(
                  key: Key('play-community-${post.id}'),
                  tooltip: playing ? '停止' : '先听声音',
                  onPressed: post.audioUrl.isEmpty ? null : onPlay,
                  icon: Icon(
                    playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _Waveform(active: playing)),
                const SizedBox(width: 10),
                Text('${post.duration.inSeconds}s'),
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

class _Waveform extends StatelessWidget {
  const _Waveform({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(22, (index) {
        final height = 8.0 + ((index * 17) % 29);
        return Expanded(
          child: AnimatedContainer(
            duration: Duration(milliseconds: 300 + index * 10),
            margin: const EdgeInsets.symmetric(horizontal: 1.2),
            height: active ? height : height * .65,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF174936) : const Color(0x667FA5A2),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    ),
  );
}

class _MissionBanner extends StatelessWidget {
  const _MissionBanner();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFFFEED0),
      borderRadius: BorderRadius.circular(22),
    ),
    child: const Row(
      children: [
        Icon(Icons.nightlight_round, color: Color(0xFF8A6124)),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('本周共同任务', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 3),
              Text('寻找杭州夏夜的鸟鸣、蛙鸣与鸣虫'),
            ],
          ),
        ),
      ],
    ),
  );
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
