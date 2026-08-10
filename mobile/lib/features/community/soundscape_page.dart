import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/storage/exploration_record.dart';
import 'package:nature_sound_detective/core/storage/exploration_store.dart';
import 'package:nature_sound_detective/features/community/publication_page.dart';

enum _SoundscapeView { recent, waiting, mission }

class SoundscapePage extends StatefulWidget {
  const SoundscapePage({
    super.key,
    this.service,
    this.explorationStore,
    this.recordsLoader,
  });

  final CommunityService? service;
  final ExplorationStore? explorationStore;
  final Future<List<ExplorationRecord>> Function()? recordsLoader;

  @override
  State<SoundscapePage> createState() => _SoundscapePageState();
}

class _SoundscapePageState extends State<SoundscapePage> {
  late final CommunityService _service;
  late final Future<List<ExplorationRecord>> Function() _recordsLoader;
  final AudioPlayer _player = AudioPlayer();
  List<SoundscapeArea> _areas = const [];
  List<CommunityPost> _posts = const [];
  String? _selectedAreaId;
  String? _playingPostId;
  String? _recentAreaId;
  String? _error;
  bool _loading = true;
  bool _acting = false;
  _SoundscapeView _view = _SoundscapeView.recent;
  StreamSubscription<PlayerState>? _playerSubscription;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? HttpCommunityService();
    final store = widget.explorationStore ?? FileExplorationStore();
    _recordsLoader = widget.recordsLoader ?? store.list;
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
      ]);
      if (!mounted) return;
      setState(() {
        _areas = values[0] as List<SoundscapeArea>;
        _posts = values[1] as List<CommunityPost>;
      });
    } on CommunityException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '城市声景暂时没有连上，请稍后刷新。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CommunityPost> get _visiblePosts {
    var values = _posts;
    if (_selectedAreaId != null) {
      values = values.where((post) => post.areaId == _selectedAreaId).toList();
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
    final total = _areas.fold<int>(0, (sum, area) => sum + area.postCount);
    final waiting = _areas.fold<int>(0, (sum, area) => sum + area.waitingCount);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5EC),
      appBar: AppBar(
        title: const Text('共听杭州'),
        actions: [
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
      floatingActionButton: !_loading && _error == null && _posts.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const Key('publish-community-sound'),
              onPressed: _startPublication,
              icon: const Icon(Icons.radar_rounded),
              label: const Text('发布线索'),
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
            Text('$total 条公开线索 · $waiting 条等待探员协助'),
            const SizedBox(height: 16),
            _SoundscapeMap(
              areas: _areas,
              loading: _loading,
              selectedAreaId: _selectedAreaId,
              recentAreaId: _recentAreaId,
              onSelected: (areaId) => setState(() {
                _selectedAreaId = _selectedAreaId == areaId ? null : areaId;
              }),
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

class _SoundscapeMap extends StatefulWidget {
  const _SoundscapeMap({
    required this.areas,
    required this.loading,
    required this.selectedAreaId,
    required this.recentAreaId,
    required this.onSelected,
  });
  final List<SoundscapeArea> areas;
  final bool loading;
  final String? selectedAreaId;
  final String? recentAreaId;
  final ValueChanged<String> onSelected;

  @override
  State<_SoundscapeMap> createState() => _SoundscapeMapState();
}

class _SoundscapeMapState extends State<_SoundscapeMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  static const _positions = <String, Alignment>{
    'yuhang': Alignment(-0.66, -0.56),
    'gongshu': Alignment(0.16, -0.61),
    'xihu': Alignment(-0.34, -0.02),
    'shangcheng': Alignment(0.46, -0.02),
    'binjiang': Alignment(0.25, 0.58),
    'xiaoshan': Alignment(0.72, 0.64),
  };

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
    aspectRatio: 1.36,
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
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.42, -0.28),
                      radius: 1.25,
                      colors: [Color(0xFFF2F5EE), Color(0xFFD7E5DD)],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _HangzhouMapPainter(
                    pulse: _pulseController.value,
                    selectedAreaId: widget.selectedAreaId,
                  ),
                ),
              ),
              const Positioned(
                left: 14,
                top: 14,
                child: _MapLabel(icon: Icons.waves_rounded, label: '杭州声景'),
              ),
              const Positioned(
                right: 14,
                top: 14,
                child: _MapLabel(
                  icon: Icons.privacy_tip_outlined,
                  label: '区域级',
                ),
              ),
              for (final area in widget.areas)
                Align(
                  alignment: _positions[area.id] ?? Alignment.center,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: 0.92,
                      end: widget.recentAreaId == area.id ? 1.13 : 1,
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
              if (widget.loading) const Positioned.fill(child: _MapLoading()),
              const Positioned(
                left: 16,
                bottom: 12,
                child: Text(
                  '不显示精确录音位置',
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

class _HangzhouMapPainter extends CustomPainter {
  const _HangzhouMapPainter({
    required this.pulse,
    required this.selectedAreaId,
  });

  final double pulse;
  final String? selectedAreaId;

  @override
  void paint(Canvas canvas, Size size) {
    final contour = Paint()
      ..color = const Color(0x19315449)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var index = 0; index < 4; index++) {
      final inset = index * size.width * .035;
      canvas.drawOval(
        Rect.fromLTWH(
          -size.width * .16 + inset,
          size.height * .02 + inset,
          size.width * .64 - inset * 1.1,
          size.height * .7 - inset,
        ),
        contour,
      );
    }

    final hills = Paint()..color = const Color(0x143E725A);
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height * .2)
        ..quadraticBezierTo(
          size.width * .22,
          size.height * .04,
          size.width * .48,
          size.height * .2,
        )
        ..quadraticBezierTo(
          size.width * .29,
          size.height * .31,
          0,
          size.height * .42,
        )
        ..close(),
      hills,
    );

    final districtLine = Paint()
      ..color = const Color(0x24315449)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .5, size.height * .08)
        ..quadraticBezierTo(
          size.width * .53,
          size.height * .35,
          size.width * .45,
          size.height * .58,
        )
        ..moveTo(size.width * .18, size.height * .47)
        ..quadraticBezierTo(
          size.width * .47,
          size.height * .45,
          size.width * .78,
          size.height * .3,
        ),
      districtLine,
    );

    final riverShadow = Paint()
      ..color = const Color(0x24739691)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * .13
      ..strokeCap = StrokeCap.round;
    final river = Path()
      ..moveTo(-size.width * .06, size.height * .82)
      ..cubicTo(
        size.width * .25,
        size.height * .63,
        size.width * .52,
        size.height * .88,
        size.width * 1.06,
        size.height * .58,
      );
    canvas.drawPath(river, riverShadow);
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xB88CB8B1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * .09
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0x669ECAC1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * .018
        ..strokeCap = StrokeCap.round,
    );

    final lake = Paint()..color = const Color(0xD875A29C);
    final lakePath = Path()
      ..moveTo(size.width * .31, size.height * .3)
      ..cubicTo(
        size.width * .2,
        size.height * .34,
        size.width * .2,
        size.height * .59,
        size.width * .33,
        size.height * .62,
      )
      ..cubicTo(
        size.width * .45,
        size.height * .65,
        size.width * .49,
        size.height * .52,
        size.width * .42,
        size.height * .43,
      )
      ..cubicTo(
        size.width * .38,
        size.height * .37,
        size.width * .4,
        size.height * .27,
        size.width * .31,
        size.height * .3,
      )
      ..close();
    canvas.drawPath(
      lakePath,
      Paint()
        ..color = const Color(0x55FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawPath(lakePath, lake);
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .28, size.height * .46)
        ..quadraticBezierTo(
          size.width * .34,
          size.height * .42,
          size.width * .42,
          size.height * .43,
        ),
      Paint()
        ..color = const Color(0xCCEBEFE5)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke,
    );

    final bridge = Paint()
      ..color = const Color(0x99315449)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    for (final x in [.45, .67, .84]) {
      canvas.drawLine(
        Offset(size.width * x, size.height * (.69 - x * .08)),
        Offset(size.width * (x + .045), size.height * (.77 - x * .08)),
        bridge,
      );
    }

    _paintLabel(canvas, size, '西湖', const Offset(.14, .6));
    _paintLabel(canvas, size, '钱塘江', const Offset(.28, .84));

    if (selectedAreaId != null) {
      const selectedCenters = <String, Offset>{
        'yuhang': Offset(.17, .22),
        'gongshu': Offset(.58, .20),
        'xihu': Offset(.33, .49),
        'shangcheng': Offset(.73, .49),
        'binjiang': Offset(.63, .79),
        'xiaoshan': Offset(.86, .82),
      };
      final center = selectedCenters[selectedAreaId] ?? const Offset(.5, .5);
      final glow = Paint()
        ..color = Color.lerp(
          const Color(0x00315449),
          const Color(0x26315449),
          1 - pulse,
        )!;
      canvas.drawCircle(
        Offset(size.width * center.dx, size.height * center.dy),
        size.shortestSide * (.12 + pulse * .035),
        glow,
      );
    }
  }

  void _paintLabel(Canvas canvas, Size size, String text, Offset alignment) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xAA315D4A),
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        size.width * alignment.dx - painter.width / 2,
        size.height * alignment.dy - painter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _HangzhouMapPainter oldDelegate) =>
      oldDelegate.pulse != pulse ||
      oldDelegate.selectedAreaId != selectedAreaId;
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
      width: 86,
      height: 86,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (area.postCount > 0 || highlighted)
            Transform.scale(
              scale: .76 + pulse * .28,
              child: Opacity(
                opacity: .36 * (1 - pulse),
                child: Container(
                  width: 82,
                  height: 82,
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
                  ? 72
                  : area.postCount == 0
                  ? 58
                  : 66,
              height: selected || highlighted
                  ? 72
                  : area.postCount == 0
                  ? 58
                  : 66,
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
                      fontSize: area.postCount == 0 ? 10 : 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : const Color(0xFF174936),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    area.postCount == 0 ? '待发现' : '${area.postCount} 条',
                    style: TextStyle(
                      fontSize: area.postCount == 0 ? 9 : 12,
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
              right: 5,
              top: 6,
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
    final choices = post.candidateNames.isEmpty
        ? <String>[post.subject, '暂时无法判断']
        : <String>[...post.candidateNames, '暂时无法判断'];
    return Card(
      key: Key('community-post-${post.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EFE8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${post.areaName} · ${post.soundType}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const Spacer(),
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
            const SizedBox(height: 12),
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
