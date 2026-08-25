import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/community/route_progress_store.dart';
import 'package:nature_sound_detective/core/community/route_listening_context.dart';
import 'package:nature_sound_detective/core/park_guide/park_recommendation.dart';
import 'package:nature_sound_detective/core/park_guide/park_recommendation_engine.dart';
import 'package:nature_sound_detective/features/community/exploration_route_page.dart';

class ParkGuidePage extends StatefulWidget {
  const ParkGuidePage({
    super.key,
    this.service,
    this.routeProgressStore,
    this.listeningContextStore,
  });

  final CommunityService? service;
  final RouteProgressStore? routeProgressStore;
  final RouteListeningContextStore? listeningContextStore;

  @override
  State<ParkGuidePage> createState() => _ParkGuidePageState();
}

class _ParkGuidePageState extends State<ParkGuidePage> {
  late final CommunityService _service;
  late final RouteProgressStore _routeProgressStore;
  late final RouteListeningContextStore _listeningContextStore;
  ParkGuidePreferences _preferences = const ParkGuidePreferences();
  List<ParkGuideData> _parks = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? HttpCommunityService();
    _routeProgressStore = widget.routeProgressStore ?? FileRouteProgressStore();
    _listeningContextStore =
        widget.listeningContextStore ?? RouteListeningContextStore();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final parks = await _service.listParks();
      final values = await Future.wait(parks.map(_loadPark));
      if (mounted) setState(() => _parks = values);
    } catch (_) {
      if (mounted) setState(() => _error = '游园信息暂时没有连上，请稍后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<ParkGuideData> _loadPark(CommunityPark park) async {
    final values = await Future.wait<Object?>([
      _optional(_service.listSites(parkId: park.id)),
      _optional(_service.listRoutes(park.id)),
      _optional(_service.ecologySnapshot(park.id)),
      _optional(_service.dailyBrief(park.id)),
    ]);
    final sites = values[0] as List<CommunitySite>?;
    final routes = values[1] as List<ExplorationRoute>?;
    final snapshot = values[2] as EcologySnapshot?;
    final brief = values[3] as DailyNatureBrief?;
    final warnings = <String>[
      if (sites == null) '公园分区暂时不可用',
      if (routes == null) '探索路线暂时不可用',
      if (snapshot == null || brief == null) '近期社区数据暂时不可用',
    ];
    return ParkGuideData(
      park: park,
      sites: sites ?? const [],
      routes: routes ?? const [],
      snapshot:
          snapshot ??
          EcologySnapshot(
            parkId: park.id,
            validPostCount: 0,
            independentObserverCount: 0,
            soundTypeCounts: const {},
            dataSufficiency: 'low',
            disclaimer: '近期社区数据暂时不可用，不参与本次推荐。',
          ),
      brief:
          brief ??
          DailyNatureBrief(
            parkId: park.id,
            parkName: park.name,
            headline: '${park.name}近期数据暂不可用',
            summary: '仍可根据适龄、时长和生境查看基础游园建议。',
            facts: const [],
            possibleExplanations: const [],
            mission: '选择公开步道，先完成一分钟安静倾听。',
            dataSufficiency: 'low',
            disclaimer: '当前没有使用社区活动趋势。',
          ),
      loadWarnings: warnings,
    );
  }

  Future<T?> _optional<T>(Future<T> future) async {
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final recommendations = const ParkRecommendationEngine().rank(
      _parks,
      _preferences,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('亲子游园指南')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const Key('park-guide-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
          children: [
            Text('今天去哪听？', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            const Text('选择家庭条件，我们会说明推荐依据；近期记录不代表动物数量。'),
            const SizedBox(height: 18),
            _PreferenceCard(
              preferences: _preferences,
              onChanged: (value) => setState(() => _preferences = value),
            ),
            const SizedBox(height: 20),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error case final error?)
              _ErrorCard(message: error, onRetry: _load),
            if (!_loading && _error == null) ...[
              Text('为你推荐', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              for (final (index, item) in recommendations.indexed) ...[
                _ParkRecommendationCard(
                  recommendation: item,
                  rank: index + 1,
                  onOpen: () => _openPark(item),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _openPark(ParkRecommendation recommendation) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ParkGuideDetailPage(
          recommendation: recommendation,
          routeProgressStore: _routeProgressStore,
          listeningContextStore: _listeningContextStore,
        ),
      ),
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({required this.preferences, required this.onChanged});
  final ParkGuidePreferences preferences;
  final ValueChanged<ParkGuidePreferences> onChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('孩子年龄', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _chips<int>(
            values: const [6, 8, 10, 12],
            selected: preferences.childAge,
            label: (value) => '$value岁+',
            onSelected: (value) =>
                onChanged(preferences.copyWith(childAge: value)),
          ),
          const SizedBox(height: 12),
          const Text('可用时间', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _chips<int>(
            values: const [20, 40, 60],
            selected: preferences.durationMinutes,
            label: (value) => '$value分钟',
            onSelected: (value) =>
                onChanged(preferences.copyWith(durationMinutes: value)),
          ),
          const SizedBox(height: 12),
          const Text('想听什么', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _chips<ParkInterest>(
            values: ParkInterest.values,
            selected: preferences.interest,
            label: (value) => value.label,
            onSelected: (value) =>
                onChanged(preferences.copyWith(interest: value)),
          ),
          const SizedBox(height: 12),
          const Text('活动偏好', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _chips<WalkPreference>(
            values: WalkPreference.values,
            selected: preferences.walkPreference,
            label: (value) => value.label,
            onSelected: (value) =>
                onChanged(preferences.copyWith(walkPreference: value)),
          ),
        ],
      ),
    ),
  );

  Widget _chips<T>({
    required Iterable<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
  }) => Wrap(
    spacing: 7,
    runSpacing: 6,
    children: [
      for (final value in values)
        ChoiceChip(
          label: Text(label(value)),
          selected: value == selected,
          onSelected: (_) => onSelected(value),
        ),
    ],
  );
}

class _ParkRecommendationCard extends StatelessWidget {
  const _ParkRecommendationCard({
    required this.recommendation,
    required this.rank,
    required this.onOpen,
  });
  final ParkRecommendation recommendation;
  final int rank;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final park = recommendation.data.park;
    return Card(
      child: InkWell(
        key: Key('park-recommendation-${park.id}'),
        borderRadius: BorderRadius.circular(24),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 17, child: Text('$rank')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      park.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    recommendation.displayScore,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 10),
              for (final reason in recommendation.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('· $reason'),
                ),
              const SizedBox(height: 6),
              Text(
                recommendation.communityEvidenceNote,
                style: const TextStyle(color: Color(0xFF6C7B74), fontSize: 13),
              ),
              if (recommendation.data.loadWarnings.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  recommendation.data.loadWarnings.join(' · '),
                  style: const TextStyle(
                    color: Color(0xFF9A4F32),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                recommendation.bestTime,
                style: const TextStyle(color: Color(0xFF315D4A)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ParkGuideDetailPage extends StatelessWidget {
  const ParkGuideDetailPage({
    super.key,
    required this.recommendation,
    required this.routeProgressStore,
    required this.listeningContextStore,
  });
  final ParkRecommendation recommendation;
  final RouteProgressStore routeProgressStore;
  final RouteListeningContextStore listeningContextStore;

  @override
  Widget build(BuildContext context) {
    final data = recommendation.data;
    return Scaffold(
      appBar: AppBar(title: Text(data.park.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text('为什么推荐', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final reason in recommendation.reasons) Text('· $reason'),
          const SizedBox(height: 8),
          Text(
            recommendation.communityEvidenceNote,
            style: const TextStyle(color: Color(0xFF52615A)),
          ),
          if (data.loadWarnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              data.loadWarnings.join(' · '),
              style: const TextStyle(color: Color(0xFF9A4F32)),
            ),
          ],
          const SizedBox(height: 16),
          _InfoTile(
            icon: Icons.schedule_rounded,
            text: recommendation.bestTime,
          ),
          _InfoTile(
            icon: Icons.family_restroom_rounded,
            text: recommendation.familyNote,
          ),
          _InfoTile(
            icon: Icons.shield_outlined,
            text: recommendation.safetyNote,
          ),
          const SizedBox(height: 18),
          Text('适合停下来听的区域', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          for (final site in data.sites)
            Card(
              margin: const EdgeInsets.only(bottom: 9),
              child: ListTile(
                leading: const Icon(Icons.hearing_rounded),
                title: Text(site.zoneName),
                subtitle: Text(site.habitatTags.join(' · ')),
              ),
            ),
          if (data.routes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('推荐路线', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            for (final route in data.routes)
              Card(
                child: ListTile(
                  key: Key('park-route-${route.id}'),
                  title: Text(route.name),
                  subtitle: Text(
                    '${route.durationMinutes}分钟 · ${route.distanceKm}公里 · ${route.ageMin}岁以上',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ExplorationRoutePage(
                        route: route,
                        store: routeProgressStore,
                        sites: data.sites,
                        onStartListening:
                            (stop, index, safeObservationConfirmed) async {
                              final site = data.sites
                                  .where((item) => item.id == stop.siteId)
                                  .firstOrNull;
                              if (site == null) return;
                              await listeningContextStore.save(
                                RouteListeningContext(
                                  parkId: data.park.id,
                                  parkName: data.park.name,
                                  zoneId: site.zoneId,
                                  zoneName: site.zoneName,
                                  siteId: site.id,
                                  routeId: route.id,
                                  routeName: route.name,
                                  stopIndex: index,
                                  safeObservationConfirmed:
                                      safeObservationConfirmed,
                                ),
                              );
                              if (context.mounted) {
                                Navigator.of(
                                  context,
                                ).popUntil((item) => item.isFirst);
                              }
                            },
                      ),
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 18),
          Text(
            data.brief.disclaimer,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF315D4A)),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
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
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text(message),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新加载'),
          ),
        ],
      ),
    ),
  );
}
