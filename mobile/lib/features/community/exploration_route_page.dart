import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/route_progress_store.dart';

class ExplorationRoutePage extends StatefulWidget {
  const ExplorationRoutePage({
    super.key,
    required this.route,
    required this.store,
    this.sites = const [],
    this.onStartListening,
  });

  final ExplorationRoute route;
  final RouteProgressStore store;
  final List<CommunitySite> sites;
  final VoidCallback? onStartListening;

  @override
  State<ExplorationRoutePage> createState() => _ExplorationRoutePageState();
}

class _ExplorationRoutePageState extends State<ExplorationRoutePage> {
  ExplorationRouteProgress? _progress;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final progress = await widget.store.load(widget.route.id);
    if (mounted) setState(() => _progress = progress);
  }

  Future<void> _toggle(ExplorationRouteStop stop, bool completed) async {
    final current = _progress;
    if (current == null || _saving) return;
    final completedSites = {...current.completedSiteIds};
    completed
        ? completedSites.add(stop.siteId)
        : completedSites.remove(stop.siteId);
    final allCompleted = widget.route.stops.every(
      (item) => completedSites.contains(item.siteId),
    );
    final next = ExplorationRouteProgress(
      routeId: current.routeId,
      completedSiteIds: completedSites,
      startedAt: current.startedAt ?? DateTime.now(),
      completedAt: allCompleted ? DateTime.now() : null,
    );
    setState(() {
      _progress = next;
      _saving = true;
    });
    try {
      await widget.store.save(next);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  CommunitySite? _site(String id) {
    for (final site in widget.sites) {
      if (site.id == id) return site;
    }
    return null;
  }

  String _parentDirection(ExplorationRouteStop stop) {
    final mission = stop.mission;
    if (mission.contains('方向') ||
        mission.contains('高处') ||
        mission.contains('低处')) {
      return '家长引导：请孩子先闭眼指出方向，再分别观察高处和低处；不要直接替孩子指出声源。';
    }
    if (mission.contains('比较')) {
      return '家长引导：请孩子各说出一条相同和不同，不评价对错，最后允许保留“不知道”。';
    }
    return '家长引导：先一起安静一分钟，再问“你最先注意到了什么变化？”';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final completed = progress?.completedSiteIds.length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('自然探索路线')),
      body: progress == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Text(
                  widget.route.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.route.durationMinutes}分钟 · ${widget.route.distanceKm}公里 · ${widget.route.ageMin}岁以上',
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: widget.route.stops.isEmpty
                      ? 0
                      : completed / widget.route.stops.length,
                ),
                const SizedBox(height: 8),
                Text('已完成 $completed / ${widget.route.stops.length} 个倾听任务'),
                const SizedBox(height: 18),
                for (final (index, stop) in widget.route.stops.indexed)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CheckboxListTile(
                            key: Key('route-stop-${stop.siteId}'),
                            value: progress.completedSiteIds.contains(
                              stop.siteId,
                            ),
                            onChanged: _saving
                                ? null
                                : (value) => _toggle(stop, value ?? false),
                            title: Text(
                              '第 ${index + 1} 站 · ${_site(stop.siteId)?.zoneName ?? '倾听点'}',
                            ),
                            subtitle: Text('儿童任务：${stop.mission}'),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              _parentDirection(stop),
                              style: const TextStyle(
                                color: Color(0xFF315D4A),
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (widget.onStartListening != null) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              key: Key('route-listen-${stop.siteId}'),
                              onPressed: widget.onStartListening,
                              icon: const Icon(Icons.mic_none_rounded),
                              label: const Text('到这里开始聆听'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (progress.completedAt != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F0E5),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.verified_rounded),
                        SizedBox(width: 10),
                        Expanded(child: Text('路线探索完成！可以回到社区发布这次听见的声音。')),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  widget.route.disclaimer,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
