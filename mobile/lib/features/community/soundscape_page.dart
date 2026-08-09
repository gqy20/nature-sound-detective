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
      floatingActionButton: FloatingActionButton.extended(
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
              selectedAreaId: _selectedAreaId,
              recentAreaId: _recentAreaId,
              onSelected: (areaId) => setState(() {
                _selectedAreaId = _selectedAreaId == areaId ? null : areaId;
              }),
            ),
            const SizedBox(height: 10),
            const Center(
              child: Text(
                '区域级声景 · 不显示精确录音位置',
                style: TextStyle(fontSize: 12, color: Color(0xFF66716B)),
              ),
            ),
            const SizedBox(height: 20),
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
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_error != null && !_loading)
              _ErrorCard(message: _error!, onRetry: _load),
            if (!_loading && _error == null && visible.isEmpty)
              _EmptySoundscape(areaSelected: _selectedAreaId != null),
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

class _SoundscapeMap extends StatelessWidget {
  const _SoundscapeMap({
    required this.areas,
    required this.selectedAreaId,
    required this.recentAreaId,
    required this.onSelected,
  });
  final List<SoundscapeArea> areas;
  final String? selectedAreaId;
  final String? recentAreaId;
  final ValueChanged<String> onSelected;

  static const _positions = <String, Alignment>{
    'yuhang': Alignment(-0.62, -0.62),
    'gongshu': Alignment(0.18, -0.55),
    'xihu': Alignment(-0.35, -0.02),
    'shangcheng': Alignment(0.42, -0.02),
    'binjiang': Alignment(0.24, 0.55),
    'xiaoshan': Alignment(0.72, 0.62),
  };

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1.42,
    child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE9EFE7), Color(0xFFDDE8E3)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _HangzhouMapPainter()),
          ),
          for (final area in areas)
            Align(
              alignment: _positions[area.id] ?? Alignment.center,
              child: TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: 0.92,
                  end: recentAreaId == area.id ? 1.15 : 1,
                ),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: _AreaRipple(
                  area: area,
                  selected: selectedAreaId == area.id,
                  highlighted: recentAreaId == area.id,
                  onTap: () => onSelected(area.id),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _HangzhouMapPainter extends CustomPainter {
  const _HangzhouMapPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final hills = Paint()..color = const Color(0x193E725A);
    canvas.drawOval(
      Rect.fromLTWH(
        -size.width * .08,
        size.height * .12,
        size.width * .58,
        size.height * .62,
      ),
      hills,
    );
    canvas.drawOval(
      Rect.fromLTWH(
        size.width * .54,
        -size.height * .12,
        size.width * .55,
        size.height * .7,
      ),
      hills,
    );
    final lake = Paint()..color = const Color(0x807FA5A2);
    final path = Path()
      ..moveTo(size.width * .31, size.height * .35)
      ..cubicTo(
        size.width * .18,
        size.height * .43,
        size.width * .23,
        size.height * .69,
        size.width * .39,
        size.height * .67,
      )
      ..cubicTo(
        size.width * .5,
        size.height * .65,
        size.width * .48,
        size.height * .51,
        size.width * .43,
        size.height * .45,
      )
      ..cubicTo(
        size.width * .39,
        size.height * .39,
        size.width * .41,
        size.height * .32,
        size.width * .31,
        size.height * .35,
      )
      ..close();
    canvas.drawPath(path, lake);
    final river = Paint()
      ..color = const Color(0x507FA5A2)
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .52, size.height * .38)
        ..cubicTo(
          size.width * .67,
          size.height * .48,
          size.width * .54,
          size.height * .76,
          size.width * .86,
          size.height * .87,
        ),
      river,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AreaRipple extends StatelessWidget {
  const _AreaRipple({
    required this.area,
    required this.selected,
    required this.highlighted,
    required this.onTap,
  });
  final SoundscapeArea area;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '${area.name}，${area.postCount} 条声音线索',
    button: true,
    child: InkWell(
      key: Key('soundscape-area-${area.id}'),
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        width: selected || highlighted
            ? 78
            : area.postCount == 0
            ? 62
            : 70,
        height: selected || highlighted
            ? 78
            : area.postCount == 0
            ? 62
            : 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? const Color(0xFF174936) : const Color(0xEFFFFFFA),
          border: Border.all(
            color: highlighted
                ? const Color(0xFFD4A45C)
                : const Color(0x66174936),
            width: highlighted ? 4 : 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22174936),
              blurRadius: 14,
              spreadRadius: 3,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              area.name,
              style: TextStyle(
                fontSize: area.postCount == 0 ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF174936),
              ),
            ),
            Text(
              '${area.postCount}',
              style: TextStyle(
                fontSize: area.postCount == 0 ? 16 : 20,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : const Color(0xFF174936),
              ),
            ),
          ],
        ),
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
  const _EmptySoundscape({required this.areaSelected});
  final bool areaSelected;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
    child: Column(
      children: [
        const Icon(Icons.hearing_rounded, size: 40, color: Color(0xFF597166)),
        const SizedBox(height: 12),
        Text(
          areaSelected ? '这个区域还没有符合条件的声音' : '等待第一位探员把声音加入城市',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Text('完成一次本地调查，就能匿名贡献关键声音片段。', textAlign: TextAlign.center),
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
