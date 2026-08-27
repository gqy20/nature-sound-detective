import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/community/route_progress_store.dart';
import 'package:nature_sound_detective/core/community/route_listening_context.dart';
import 'package:nature_sound_detective/core/park_guide/park_recommendation.dart';
import 'package:nature_sound_detective/core/park_guide/park_recommendation_engine.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/features/community/exploration_route_page.dart';

const _guideForest = Color(0xFF174936);
const _guideInk = Color(0xFF17251F);
const _guideIvory = Color(0xFFF8F5EC);
const _guidePaper = Color(0xFFFFFCF5);
const _guideOchre = Color(0xFFD39A20);
const _guideLine = Color(0xFFD8D1BF);

enum _ParkGuideStep { criteria, recommendations }

class ParkGuidePage extends StatefulWidget {
  const ParkGuidePage({
    super.key,
    this.service,
    this.routeProgressStore,
    this.listeningContextStore,
    this.parkListTimeout = const Duration(seconds: 12),
    this.parkDetailTimeout = const Duration(seconds: 10),
  });

  final CommunityService? service;
  final RouteProgressStore? routeProgressStore;
  final RouteListeningContextStore? listeningContextStore;
  final Duration parkListTimeout;
  final Duration parkDetailTimeout;

  @override
  State<ParkGuidePage> createState() => _ParkGuidePageState();
}

class _ParkGuidePageState extends State<ParkGuidePage> {
  late final CommunityService _service;
  late final bool _ownsService;
  late final RouteProgressStore _routeProgressStore;
  late final RouteListeningContextStore _listeningContextStore;
  ParkGuidePreferences _preferences = const ParkGuidePreferences();
  List<ParkGuideData> _parks = const [];
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;
  _ParkGuideStep _step = _ParkGuideStep.criteria;
  int _selectedRecommendationIndex = 0;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? HttpCommunityService();
    _routeProgressStore = widget.routeProgressStore ?? FileRouteProgressStore();
    _listeningContextStore =
        widget.listeningContextStore ?? RouteListeningContextStore();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final parks = await _retryOnce(
        _service.listParks,
        timeout: widget.parkListTimeout,
      );
      if (!mounted || generation != _loadGeneration) return;
      final values = <ParkGuideData>[];
      if (parks.isEmpty) setState(() => _parks = const []);
      await Future.wait(
        parks.map((park) async {
          final value = await _loadPark(park);
          if (!mounted || generation != _loadGeneration) return;
          values.add(value);
          setState(() => _parks = List.unmodifiable(values));
        }),
      );
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = _parks.isEmpty
              ? '游园信息暂时没有连上，请检查网络后重试。'
              : '刷新暂时没有完成，继续显示上次加载的游园信息。';
        });
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<ParkGuideData> _loadPark(CommunityPark park) async {
    final values = await Future.wait<Object?>([
      _optional(() => _service.listSites(parkId: park.id)),
      _optional(() => _service.listRoutes(park.id)),
      _optional(() => _service.ecologySnapshot(park.id)),
      _optional(() => _service.dailyBrief(park.id)),
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

  Future<T?> _optional<T>(Future<T> Function() request) async {
    try {
      return await _retryOnce(request, timeout: widget.parkDetailTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<T> _retryOnce<T>(
    Future<T> Function() request, {
    required Duration timeout,
  }) {
    return (() async {
      try {
        return await request();
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        return request();
      }
    })().timeout(timeout);
  }

  void _updatePreferences(ParkGuidePreferences value) {
    if (value.signature == _preferences.signature) return;
    setState(() {
      _preferences = value;
      _selectedRecommendationIndex = 0;
    });
    AppLog.info(
      'park_guide',
      'preferences_changed',
      fields: {'summary': value.shortSummary, 'signature': value.signature},
    );
  }

  @override
  void dispose() {
    _loadGeneration++;
    if (_ownsService && _service is HttpCommunityService) {
      _service.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recommendations = const ParkRecommendationEngine().rank(
      _parks,
      _preferences,
    );
    final onResults = _step == _ParkGuideStep.recommendations;
    return PopScope(
      canPop: !onResults,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && onResults) {
          setState(() => _step = _ParkGuideStep.criteria);
        }
      },
      child: Scaffold(
        backgroundColor: _guideIvory,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: onResults
              ? IconButton(
                  key: const Key('back-to-park-criteria'),
                  onPressed: () =>
                      setState(() => _step = _ParkGuideStep.criteria),
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          titleSpacing: 16,
          title: const Text('亲子游园指南'),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '今天去哪听？',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
          backgroundColor: _guideIvory,
          foregroundColor: _guideForest,
          scrolledUnderElevation: 0,
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: Offset(onResults ? .06 : -.06, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
          ),
          child: onResults
              ? _buildRecommendationsPage(recommendations)
              : _buildCriteriaPage(recommendations),
        ),
      ),
    );
  }

  Widget _buildCriteriaPage(List<ParkRecommendation> recommendations) =>
      LayoutBuilder(
        key: const Key('park-guide-criteria-page'),
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final panel = KeyedSubtree(
            key: const Key('park-preference-journal'),
            child: _PreferenceJournal(
              preferences: _preferences,
              onChanged: _updatePreferences,
            ),
          );
          final footer = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading)
                const LinearProgressIndicator(
                  key: Key('park-guide-loading'),
                  minHeight: 4,
                  color: _guideForest,
                  backgroundColor: Color(0xFFE4E0D3),
                ),
              if (_error case final error?) ...[
                const SizedBox(height: 8),
                _ErrorCard(message: error, onRetry: _load),
              ],
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('open-park-recommendations'),
                onPressed: _loading || recommendations.isEmpty
                    ? null
                    : () => setState(() {
                        _selectedRecommendationIndex = 0;
                        _step = _ParkGuideStep.recommendations;
                      }),
                icon: const Icon(Icons.eco_outlined),
                label: Text(
                  _loading
                      ? '正在整理推荐'
                      : recommendations.isEmpty
                      ? '暂无完整匹配'
                      : '查看 ${recommendations.length} 个推荐',
                ),
              ),
            ],
          );
          if (textScale > 1.4) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
              children: [panel, const SizedBox(height: 12), footer],
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: constraints.maxWidth - 28,
                      child: panel,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                footer,
              ],
            ),
          );
        },
      );

  Widget _buildRecommendationsPage(List<ParkRecommendation> recommendations) {
    if (recommendations.isEmpty) {
      return Center(
        key: const Key('park-guide-recommendations-page'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('暂时没有完整匹配，可以返回调整一项条件。'),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () =>
                    setState(() => _step = _ParkGuideStep.criteria),
                child: const Text('重新选择'),
              ),
            ],
          ),
        ),
      );
    }
    final index = _selectedRecommendationIndex.clamp(
      0,
      recommendations.length - 1,
    );
    final selected = recommendations[index];
    return Padding(
      key: const Key('park-guide-recommendations-page'),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _preferences.shortSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF5F6B65),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                key: const Key('edit-park-preferences'),
                onPressed: () =>
                    setState(() => _step = _ParkGuideStep.criteria),
                child: const Text('重新选择'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final (tabIndex, item) in recommendations.indexed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _RecommendationTab(
                      key: Key('park-recommendation-tab-${item.data.park.id}'),
                      label: item.data.park.name,
                      selected: tabIndex == index,
                      onTap: () => setState(
                        () => _selectedRecommendationIndex = tabIndex,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previousChildren, ?currentChild],
                ),
                child: FittedBox(
                  key: ValueKey(selected.data.park.id),
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: _ParkRecommendationCard(
                      recommendation: selected,
                      rank: index + 1,
                      highlighted: index == 0,
                      onOpen: () => _openPark(selected),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('open-selected-park-route'),
            onPressed: () => _openPark(selected),
            icon: const Icon(Icons.route_rounded),
            label: Text('查看${selected.data.park.name}路线'),
          ),
        ],
      ),
    );
  }

  void _openPark(ParkRecommendation recommendation) {
    AppLog.info(
      'park_guide',
      'recommendation_opened',
      fields: {
        'park_id': recommendation.data.park.id,
        'preference_signature': _preferences.signature,
      },
    );
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

class _RecommendationTab extends StatelessWidget {
  const _RecommendationTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 42,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFDCECE1) : const Color(0xFFF7F3E9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _guideForest : const Color(0xFFE2DCCA),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? _guideForest : _guideInk,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

class _PreferenceJournal extends StatelessWidget {
  const _PreferenceJournal({
    required this.preferences,
    required this.onChanged,
  });
  final ParkGuidePreferences preferences;
  final ValueChanged<ParkGuidePreferences> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _JournalHeading(icon: Icons.eco_outlined, label: '孩子年龄'),
        const SizedBox(height: 5),
        _AgeBandPicker(
          selected: preferences.ageBand,
          onSelected: (value) =>
              onChanged(preferences.copyWith(ageBand: value)),
        ),
        const _JournalDivider(),
        const _JournalHeading(icon: Icons.schedule_outlined, label: '可用时间'),
        const SizedBox(height: 5),
        _DurationPicker(
          selected: preferences.visitDuration,
          onSelected: (value) =>
              onChanged(preferences.copyWith(visitDuration: value)),
        ),
        const _JournalDivider(),
        const _JournalHeading(icon: Icons.hearing_outlined, label: '想听什么'),
        const SizedBox(height: 5),
        _InterestPicker(
          selected: preferences.interest,
          onSelected: (value) =>
              onChanged(preferences.copyWith(interest: value)),
        ),
        const _JournalDivider(),
        const _JournalHeading(icon: Icons.hiking_outlined, label: '活动偏好'),
        const SizedBox(height: 5),
        _WalkPicker(
          selected: preferences.walkPreference,
          onSelected: (value) =>
              onChanged(preferences.copyWith(walkPreference: value)),
        ),
        const _JournalDivider(),
        Semantics(
          toggled: preferences.requiresAccessibleRoute,
          label: '需要无障碍路线',
          child: Row(
            children: [
              const Icon(
                Icons.accessible_forward_rounded,
                color: _guideForest,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '需要无障碍路线',
                  style: TextStyle(
                    color: _guideInk,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: preferences.requiresAccessibleRoute,
                activeTrackColor: _guideForest,
                onChanged: (value) => onChanged(
                  preferences.copyWith(requiresAccessibleRoute: value),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _JournalHeading extends StatelessWidget {
  const _JournalHeading({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 21, color: _guideForest),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(
          color: _guideForest,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _JournalDivider extends StatelessWidget {
  const _JournalDivider();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 18);
}

class _AgeBandPicker extends StatelessWidget {
  const _AgeBandPicker({required this.selected, required this.onSelected});
  final ChildAgeBand selected;
  final ValueChanged<ChildAgeBand> onSelected;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: 6,
        right: 6,
        top: 0,
        child: IgnorePointer(
          child: Image.asset(
            'assets/images/park_guide/age_growth_strip.png',
            height: 66,
            fit: BoxFit.fill,
            errorBuilder: (_, _, _) => const SizedBox(height: 66),
          ),
        ),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final value in ChildAgeBand.values)
            Expanded(
              child: _ScaleChoice(
                key: Key('park-age-${value.name}'),
                label: value.label,
                selected: value == selected,
                onTap: () => onSelected(value),
              ),
            ),
        ],
      ),
    ],
  );
}

class _ScaleChoice extends StatelessWidget {
  const _ScaleChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: InkResponse(
      onTap: onTap,
      radius: 34,
      child: SizedBox(
        height: 104,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 56,
              height: 62,
              decoration: BoxDecoration(
                color: selected ? const Color(0xCCE8F0E3) : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _guideForest : Colors.transparent,
                  width: 2,
                ),
              ),
              alignment: Alignment.bottomCenter,
              child: selected
                  ? Transform.translate(
                      offset: const Offset(0, 7),
                      child: const _SelectionMark(),
                    )
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                color: selected ? _guideForest : _guideInk,
                fontSize: 10.5,
                height: 1.15,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DurationPicker extends StatelessWidget {
  const _DurationPicker({required this.selected, required this.onSelected});
  final VisitDuration selected;
  final ValueChanged<VisitDuration> onSelected;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: 2,
        right: 2,
        top: 0,
        child: IgnorePointer(
          child: Image.asset(
            'assets/images/park_guide/time_nature_strip.png',
            height: 94,
            fit: BoxFit.fill,
            errorBuilder: (_, _, _) => const SizedBox(height: 94),
          ),
        ),
      ),
      Row(
        children: [
          for (final value in VisitDuration.values)
            Expanded(
              child: _DurationChoice(
                key: Key('park-duration-${value.name}'),
                label: value.label,
                selected: value == selected,
                onTap: () => onSelected(value),
              ),
            ),
        ],
      ),
    ],
  );
}

class _DurationChoice extends StatelessWidget {
  const _DurationChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 130,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.fromLTRB(3, 74, 3, 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xCCE8F0E3) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _guideForest : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            if (selected) const _SelectionMark(),
            const Spacer(),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                color: selected ? _guideForest : _guideInk,
                fontSize: 10.5,
                height: 1.1,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InterestPicker extends StatelessWidget {
  const _InterestPicker({required this.selected, required this.onSelected});
  final ParkInterest selected;
  final ValueChanged<ParkInterest> onSelected;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: 4,
        right: 4,
        top: 3,
        child: IgnorePointer(
          child: Image.asset(
            'assets/images/park_guide/interest_nature_strip.png',
            height: 62,
            fit: BoxFit.fill,
            errorBuilder: (_, _, _) => const SizedBox(height: 62),
          ),
        ),
      ),
      Row(
        children: [
          for (final value in ParkInterest.values)
            Expanded(
              child: _CompactChoice(
                key: Key('park-interest-${value.name}'),
                label: value.label,
                selected: value == selected,
                onTap: () => onSelected(value),
              ),
            ),
        ],
      ),
    ],
  );
}

class _CompactChoice extends StatelessWidget {
  const _CompactChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 92,
        padding: const EdgeInsets.fromLTRB(2, 64, 2, 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0x33D8E8D2) : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? _guideForest : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          style: TextStyle(
            color: _guideInk,
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}

class _WalkPicker extends StatelessWidget {
  const _WalkPicker({required this.selected, required this.onSelected});
  final WalkPreference selected;
  final ValueChanged<WalkPreference> onSelected;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: 5,
        right: 5,
        top: 2,
        child: IgnorePointer(
          child: Image.asset(
            'assets/images/park_guide/walk_routes_strip.png',
            height: 70,
            fit: BoxFit.fill,
            errorBuilder: (_, _, _) => const SizedBox(height: 70),
          ),
        ),
      ),
      Row(
        children: [
          for (final value in WalkPreference.values) ...[
            Expanded(
              child: _WalkChoice(
                key: Key('park-walk-${value.name}'),
                value: value,
                selected: value == selected,
                onTap: () => onSelected(value),
              ),
            ),
            if (value != WalkPreference.values.last) const SizedBox(width: 10),
          ],
        ],
      ),
    ],
  );
}

class _WalkChoice extends StatelessWidget {
  const _WalkChoice({
    super.key,
    required this.value,
    required this.selected,
    required this.onTap,
  });
  final WalkPreference value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: value.label,
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 104,
        padding: const EdgeInsets.fromLTRB(12, 70, 8, 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0x26D8E8D2) : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? _guideForest : _guideLine,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  color: _guideInk,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (selected) const _SelectionMark(),
          ],
        ),
      ),
    ),
  );
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(color: _guideOchre, shape: BoxShape.circle),
    child: SizedBox.square(
      dimension: 21,
      child: Icon(Icons.check_rounded, color: Colors.white, size: 15),
    ),
  );
}

class _ParkRecommendationCard extends StatelessWidget {
  const _ParkRecommendationCard({
    required this.recommendation,
    required this.rank,
    required this.highlighted,
    required this.onOpen,
  });
  final ParkRecommendation recommendation;
  final int rank;
  final bool highlighted;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final park = recommendation.data.park;
    final imagePath = switch (park.id) {
      'hangzhou-botanical-garden' =>
        'assets/images/park_guide/park_botanical_thumbnail.webp',
      'taiziwan-park' =>
        'assets/images/park_guide/park_taiziwan_thumbnail.webp',
      _ => 'assets/images/park_guide/park_wetland_thumbnail.webp',
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      decoration: BoxDecoration(
        color: _guidePaper,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: highlighted ? _guideForest : const Color(0xFFE1DAC8),
          width: highlighted ? 1.8 : 1,
        ),
      ),
      child: InkWell(
        key: Key('park-recommendation-${park.id}'),
        borderRadius: BorderRadius.circular(24),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: Image.asset(
                      imagePath,
                      width: 92,
                      height: 102,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            DecoratedBox(
                              decoration: const BoxDecoration(
                                color: _guideForest,
                                shape: BoxShape.circle,
                              ),
                              child: SizedBox.square(
                                dimension: 25,
                                child: Center(
                                  child: Text(
                                    '$rank',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                park.name,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: _guideInk,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        for (final reason in recommendation.reasons.take(2))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '· $reason',
                              style: const TextStyle(
                                color: Color(0xFF53645C),
                                fontSize: 12,
                                height: 1.25,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0CE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2B34F)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Column(
                            children: [
                              Text(
                                recommendation.displayScore,
                                style: const TextStyle(
                                  color: Color(0xFF9A6A0A),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (highlighted)
                                const Text(
                                  '本次首选',
                                  style: TextStyle(
                                    color: Color(0xFF835A09),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (highlighted) ...[
                const SizedBox(height: 10),
                Container(
                  key: const Key('park-recommendation-change-reason'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F5E9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.eco_outlined,
                        color: _guideForest,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '变化原因：${recommendation.matchNote}',
                          style: const TextStyle(
                            color: _guideForest,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (recommendation.data.loadWarnings.isNotEmpty) ...[
                Text(
                  recommendation.data.loadWarnings.join(' · '),
                  style: const TextStyle(
                    color: Color(0xFF9A4F32),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 17,
                    color: _guideForest,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      recommendation.bestTime,
                      style: const TextStyle(
                        color: _guideForest,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: _guideForest),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                recommendation.communityEvidenceNote,
                style: const TextStyle(
                  color: Color(0xFF7A827D),
                  fontSize: 11.5,
                ),
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
