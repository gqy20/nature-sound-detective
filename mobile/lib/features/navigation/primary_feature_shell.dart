import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/family/family_session_coordinator.dart';
import 'package:nature_sound_detective/core/community/community_activity_guide.dart';
import 'package:nature_sound_detective/core/community/soundscape_preloader.dart';
import 'package:nature_sound_detective/core/inference/recording_analyzer.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode.dart';
import 'package:nature_sound_detective/core/storage/exploration_store.dart';
import 'package:nature_sound_detective/features/capture/capture_page.dart';
import 'package:nature_sound_detective/features/community/soundscape_page.dart';
import 'package:nature_sound_detective/features/library/nature_book_page.dart';
import 'package:nature_sound_detective/features/navigation/primary_feature.dart';
import 'package:nature_sound_detective/features/navigation/primary_feature_store.dart';
import 'package:nature_sound_detective/features/park_guide/park_guide_page.dart';

class PrimaryFeatureShell extends StatefulWidget {
  const PrimaryFeatureShell({
    super.key,
    this.analyzer,
    required this.mode,
    required this.onModeChanged,
    required this.familySessionCoordinator,
    this.preloadSoundscape = true,
    this.featureStore,
  });

  final RecordingAnalyzer? analyzer;
  final ExplorationMode mode;
  final ValueChanged<ExplorationMode> onModeChanged;
  final FamilySessionCoordinator familySessionCoordinator;
  final bool preloadSoundscape;
  final PrimaryFeatureStore? featureStore;

  @override
  State<PrimaryFeatureShell> createState() => _PrimaryFeatureShellState();
}

class _PrimaryFeatureShellState extends State<PrimaryFeatureShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final PageController _controller = PageController();
  final ValueNotifier<double> _pagePositionNotifier = ValueNotifier(0);
  final ValueNotifier<String?> _soundscapeSpeciesFilter = ValueNotifier(null);
  final ValueNotifier<CommunitySoundscapeFocus?> _soundscapeFocus =
      ValueNotifier(null);
  final ExplorationStore _store = FileExplorationStore();
  late final AnimationController _directTransitionController;
  late final PrimaryFeatureStore _featureStore;
  SoundscapePreloader? _soundscapePreloader;
  CommunityActivityGuide? _communityActivityGuide;
  int _selectedIndex = 0;
  int _settledIndex = 0;
  bool _swipeLocked = false;
  bool _transitioning = false;
  bool _directTransitionActive = false;
  bool _userDragging = false;
  int _gestureStartIndex = 0;
  String? _activeNavigationTrigger;
  Timer? _navigationSettleTimer;
  bool _soundscapeMapPrecacheStarted = false;
  int _restoreRevision = 0;
  String? _preferredParkId;

  List<PrimaryFeature> _featuresFor(ExplorationMode mode) =>
      mode == ExplorationMode.parent
      ? PrimaryFeature.values
      : const [
          PrimaryFeature.capture,
          PrimaryFeature.soundscape,
          PrimaryFeature.natureBook,
        ];

  List<PrimaryFeature> get _availableFeatures => _featuresFor(widget.mode);

  int _pageIndexOf(PrimaryFeature feature) =>
      _availableFeatures.indexOf(feature);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _featureStore = widget.featureStore ?? PrimaryFeatureStore();
    _directTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    if (widget.preloadSoundscape) {
      _soundscapePreloader = SoundscapePreloader();
      final preloader = _soundscapePreloader!;
      _communityActivityGuide = CommunityActivityGuide(
        postsLoader: () async => (await preloader.load()).posts,
        parksLoader: () async => (await preloader.load()).parks,
        sitesLoader: preloader.service.listSites,
      );
      unawaited(_startSoundscapePreload());
    }
    _controller.addListener(_trackPagePosition);
    unawaited(_restoreSelectedFeature());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_soundscapeMapPrecacheStarted) return;
    _soundscapeMapPrecacheStarted = true;
    unawaited(_precacheSoundscapeMap());
  }

  @override
  void didUpdateWidget(covariant PrimaryFeatureShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode == widget.mode) return;
    final oldFeatures = _featuresFor(oldWidget.mode);
    if (_selectedIndex >= 0 && _selectedIndex < oldFeatures.length) {
      unawaited(
        _featureStore
            .save(oldWidget.mode, oldFeatures[_selectedIndex])
            .catchError((_) {}),
      );
    }
    _selectedIndex = 0;
    _settledIndex = 0;
    _gestureStartIndex = 0;
    _pagePositionNotifier.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) _controller.jumpToPage(0);
    });
    unawaited(_restoreSelectedFeature());
  }

  Future<void> _precacheSoundscapeMap() async {
    final preloader = _soundscapePreloader;
    if (preloader == null) return;
    try {
      final data = await preloader.load();
      final url = data.parks.firstOrNull?.mapImageUrl;
      if (!mounted || url == null || url.isEmpty) return;
      await precacheImage(NetworkImage(url), context);
      AppLog.info('community', 'soundscape_map_image_precached');
    } catch (error) {
      AppLog.debug(
        'community',
        'soundscape_map_image_precache_skipped',
        fields: {'reason': error.runtimeType.toString()},
      );
    }
  }

  Future<void> _startSoundscapePreload() async {
    try {
      await _soundscapePreloader?.load();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_persistSelectedFeature());
    _controller
      ..removeListener(_trackPagePosition)
      ..dispose();
    _pagePositionNotifier.dispose();
    _soundscapeSpeciesFilter.dispose();
    _soundscapeFocus.dispose();
    _directTransitionController.dispose();
    _navigationSettleTimer?.cancel();
    _soundscapePreloader?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ({
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    }.contains(state)) {
      unawaited(_persistSelectedFeature());
    }
  }

  Future<void> _restoreSelectedFeature() async {
    final revision = ++_restoreRevision;
    final mode = widget.mode;
    final feature = await _featureStore.load(mode);
    if (!mounted || revision != _restoreRevision || mode != widget.mode) return;
    final available = _availableFeatures;
    final targetIndex = feature == null ? -1 : available.indexOf(feature);
    if (targetIndex <= 0) return;
    setState(() {
      _selectedIndex = targetIndex;
      _settledIndex = targetIndex;
      _gestureStartIndex = targetIndex;
      _pagePositionNotifier.value = targetIndex.toDouble();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) {
        _controller.jumpToPage(targetIndex);
      }
    });
  }

  Future<void> _persistSelectedFeature() async {
    final available = _availableFeatures;
    if (_selectedIndex < 0 || _selectedIndex >= available.length) return;
    try {
      await _featureStore.save(widget.mode, available[_selectedIndex]);
    } catch (_) {}
  }

  void _trackPagePosition() {
    final value = _controller.hasClients
        ? _controller.page ?? _selectedIndex.toDouble()
        : _selectedIndex.toDouble();
    if (!mounted || (value - _pagePositionNotifier.value).abs() < .001) return;
    _pagePositionNotifier.value = value;
  }

  Future<void> _selectFeature(
    PrimaryFeature feature, {
    String trigger = 'button',
  }) async {
    final available = _availableFeatures;
    final targetIndex = _pageIndexOf(feature);
    if (targetIndex < 0) return;
    final fromIndex = _settledIndex;
    final from = available[fromIndex];
    AppLog.info(
      'navigation',
      'primary_navigation_requested',
      fields: {
        'from': from.name,
        'to': feature.name,
        'trigger': trigger,
        'locked': _swipeLocked || _transitioning,
      },
    );
    if (_swipeLocked || _transitioning) {
      AppLog.warning(
        'navigation',
        'primary_navigation_blocked',
        fields: {
          'from': from.name,
          'to': feature.name,
          'trigger': trigger,
          'reason': _swipeLocked
              ? 'recording_or_analysis_active'
              : 'navigation_transition_active',
        },
      );
      if (_swipeLocked) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('录音或分析结束后再切换功能。')));
      }
      return;
    }
    if (!_controller.hasClients) {
      AppLog.warning(
        'navigation',
        'primary_navigation_blocked',
        fields: {
          'from': from.name,
          'to': feature.name,
          'trigger': trigger,
          'reason': 'page_controller_not_ready',
        },
      );
      return;
    }
    if (targetIndex == fromIndex) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion ||
        trigger == 'system_back' ||
        (targetIndex - fromIndex).abs() > 1) {
      await _fadeThroughTo(feature, trigger: trigger, animate: !reduceMotion);
      return;
    }
    setState(() => _transitioning = true);
    _activeNavigationTrigger = trigger;
    try {
      await _controller.animateToPage(
        targetIndex,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      _settleNavigation();
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  void _onPageChanged(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  Future<void> _fadeThroughTo(
    PrimaryFeature feature, {
    required String trigger,
    required bool animate,
  }) async {
    final available = _availableFeatures;
    final targetIndex = _pageIndexOf(feature);
    if (targetIndex < 0) return;
    final fromIndex = _settledIndex;
    setState(() {
      _transitioning = true;
      _directTransitionActive = true;
    });
    try {
      if (animate) {
        _directTransitionController.value = 0;
        await _directTransitionController.animateTo(
          .35,
          duration: const Duration(milliseconds: 85),
          curve: Curves.easeOutCubic,
        );
      }
      _controller.jumpToPage(targetIndex);
      _pagePositionNotifier.value = targetIndex.toDouble();
      if (_selectedIndex != targetIndex && mounted) {
        setState(() => _selectedIndex = targetIndex);
      }
      _settledIndex = targetIndex;
      if (animate) {
        await _directTransitionController.animateTo(
          1,
          duration: const Duration(milliseconds: 155),
          curve: Curves.easeOutCubic,
        );
      }
      AppLog.info(
        'navigation',
        'primary_navigation_completed',
        fields: {
          'from': available[fromIndex].name,
          'to': feature.name,
          'trigger': trigger,
          'transition': 'fade_through',
        },
      );
      unawaited(HapticFeedback.selectionClick());
    } finally {
      _directTransitionController.value = 0;
      if (mounted) {
        setState(() {
          _directTransitionActive = false;
          _transitioning = false;
        });
      }
    }
  }

  bool _onPageScrollNotification(ScrollNotification notification) {
    final available = _availableFeatures;
    if (notification.metrics.axis != Axis.horizontal) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _navigationSettleTimer?.cancel();
      _userDragging = true;
      _gestureStartIndex = _settledIndex;
      _activeNavigationTrigger = 'swipe';
      AppLog.debug(
        'navigation',
        'primary_swipe_started',
        fields: {'from': available[_gestureStartIndex].name},
      );
      AppLog.info(
        'navigation',
        'primary_navigation_requested',
        fields: {
          'from': available[_gestureStartIndex].name,
          'to': 'adjacent',
          'trigger': 'swipe',
          'locked': false,
        },
      );
    } else if (notification is ScrollEndNotification ||
        (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle)) {
      _scheduleNavigationSettle(delay: Duration.zero);
    }
    return false;
  }

  void _scheduleNavigationSettle({
    Duration delay = const Duration(milliseconds: 340),
  }) {
    _navigationSettleTimer?.cancel();
    _navigationSettleTimer = Timer(delay, _settleNavigation);
  }

  void _settleNavigation() {
    if (_directTransitionActive || !_controller.hasClients) return;
    final available = _availableFeatures;
    final finalIndex = (_controller.page ?? _selectedIndex.toDouble())
        .round()
        .clamp(0, available.length - 1)
        .toInt();
    if (_selectedIndex != finalIndex && mounted) {
      setState(() => _selectedIndex = finalIndex);
    }
    if (finalIndex == _settledIndex) {
      if (_userDragging) {
        AppLog.debug(
          'navigation',
          'primary_swipe_cancelled',
          fields: {'current': available[finalIndex].name},
        );
      }
      _userDragging = false;
      _activeNavigationTrigger = null;
      return;
    }
    final from = available[_settledIndex];
    final to = available[finalIndex];
    final trigger =
        _activeNavigationTrigger ?? (_userDragging ? 'swipe' : 'programmatic');
    _settledIndex = finalIndex;
    AppLog.info(
      'navigation',
      'primary_navigation_completed',
      fields: {
        'from': from.name,
        'to': to.name,
        'trigger': trigger,
        'transition': 'direct_manipulation',
      },
    );
    _userDragging = false;
    _activeNavigationTrigger = null;
    unawaited(HapticFeedback.selectionClick());
  }

  void _setSwipeLocked(bool value) {
    if (_swipeLocked == value) return;
    setState(() => _swipeLocked = value);
  }

  void _openSuggestedPark(String? parkId) {
    if (_preferredParkId != parkId) {
      setState(() => _preferredParkId = parkId);
    }
    unawaited(
      _selectFeature(PrimaryFeature.parkGuide, trigger: 'community_route'),
    );
  }

  void _openSoundscapeFocus(CommunitySoundscapeFocus focus) {
    _soundscapeSpeciesFilter.value = null;
    _soundscapeFocus.value = focus;
    unawaited(
      _selectFeature(PrimaryFeature.soundscape, trigger: 'habitat_soundscape'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = _availableFeatures;
    final rawPages = <Widget>[
      _KeepAlivePage(
        key: const ValueKey(PrimaryFeature.capture),
        child: CapturePage(
          key: const ValueKey('primary-capture-content'),
          analyzer: widget.analyzer,
          communityActivityGuide: _communityActivityGuide,
          store: _store,
          mode: widget.mode,
          onModeChanged: widget.onModeChanged,
          familySessionCoordinator: widget.familySessionCoordinator,
          primaryPagePosition: _pagePositionNotifier,
          onGenerateRouteForPark: _openSuggestedPark,
          onViewCommunityFocus: _openSoundscapeFocus,
          onPrimaryFeatureSelected: (feature) =>
              _selectFeature(feature, trigger: 'button'),
          onPrimarySwipeLockChanged: _setSwipeLocked,
        ),
      ),
      _KeepAlivePage(
        key: const ValueKey(PrimaryFeature.soundscape),
        child: SoundscapePage(
          key: const ValueKey('primary-soundscape-content'),
          explorationStore: _store,
          preloader: _soundscapePreloader,
          primaryPagePosition: _pagePositionNotifier,
          speciesFilter: _soundscapeSpeciesFilter,
          onClearSpeciesFilter: () => _soundscapeSpeciesFilter.value = null,
          soundscapeFocus: _soundscapeFocus,
          onClearSoundscapeFocus: () => _soundscapeFocus.value = null,
          onOpenParkGuide: widget.mode == ExplorationMode.parent
              ? () =>
                    _selectFeature(PrimaryFeature.parkGuide, trigger: 'button')
              : null,
        ),
      ),
      if (widget.mode == ExplorationMode.parent)
        _KeepAlivePage(
          key: const ValueKey(PrimaryFeature.parkGuide),
          child: ParkGuidePage(
            key: const ValueKey('primary-park-guide-content'),
            initialParkId: _preferredParkId,
            onStartRouteListening: () =>
                _selectFeature(PrimaryFeature.capture, trigger: 'route_stop'),
          ),
        ),
      _KeepAlivePage(
        key: const ValueKey(PrimaryFeature.natureBook),
        child: NatureBookPage(
          key: const ValueKey('primary-nature-book-content'),
          store: _store,
          onOpenSoundscape: () =>
              _selectFeature(PrimaryFeature.soundscape, trigger: 'button'),
          onOpenParkGuide: widget.mode == ExplorationMode.parent
              ? _openSuggestedPark
              : null,
        ),
      ),
    ];
    final pages = rawPages;

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedIndex != 0) {
          unawaited(
            _selectFeature(PrimaryFeature.capture, trigger: 'system_back'),
          );
        }
      },
      child: Scaffold(
        extendBody: true,
        bottomNavigationBar: _FloatingPrimaryNavigationBar(
          mode: widget.mode,
          features: available,
          selectedIndex: _selectedIndex,
          navigationLocked: _swipeLocked,
          onSelected: (index) =>
              _selectFeature(available[index], trigger: 'bottom_navigation'),
        ),
        body: Stack(
          children: [
            AnimatedBuilder(
              animation: _directTransitionController,
              builder: (context, child) {
                final progress = _directTransitionController.value;
                final opacity = progress <= .35
                    ? 1 - progress / .35
                    : (progress - .35) / .65;
                return ColoredBox(
                  color: const Color(0xFFE5EDE7),
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: Listener(
                onPointerUp: (_) => _scheduleNavigationSettle(),
                onPointerCancel: (_) => _scheduleNavigationSettle(),
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onPageScrollNotification,
                  child: PageView(
                    key: const Key('primary-feature-page-view'),
                    controller: _controller,
                    physics: _swipeLocked || _transitioning
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(
                            parent: ClampingScrollPhysics(),
                          ),
                    onPageChanged: _onPageChanged,
                    children: pages,
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: SizedBox.shrink(
                key: Key(
                  'current-primary-feature-${available[_selectedIndex].name}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingPrimaryNavigationBar extends StatelessWidget {
  const _FloatingPrimaryNavigationBar({
    required this.mode,
    required this.features,
    required this.selectedIndex,
    required this.navigationLocked,
    required this.onSelected,
  });

  final ExplorationMode mode;
  final List<PrimaryFeature> features;
  final int selectedIndex;
  final bool navigationLocked;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const radius = 28.0;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Semantics(
        label: '主功能导航',
        enabled: !navigationLocked,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF8FFFDF7),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0xFFD7DED4)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F183629),
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                height: 72,
                backgroundColor: Colors.transparent,
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                indicatorColor: const Color(0xFFDCEBDD),
                indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return IconThemeData(
                    size: selected ? 25 : 23,
                    color: selected
                        ? const Color(0xFF174936)
                        : const Color(0xFF69766F),
                  );
                }),
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return TextStyle(
                    color: selected
                        ? const Color(0xFF174936)
                        : const Color(0xFF69766F),
                    fontSize: 12.5,
                    height: 1.1,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  );
                }),
              ),
              child: NavigationBar(
                key: const Key('primary-feature-navigation-bar'),
                selectedIndex: selectedIndex,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                onDestinationSelected: onSelected,
                destinations: [
                  for (final feature in features)
                    NavigationDestination(
                      key: _destinationKey(feature),
                      icon: Icon(_destinationIcon(feature, selected: false)),
                      selectedIcon: Icon(
                        _destinationIcon(feature, selected: true),
                      ),
                      label: _destinationLabel(feature),
                      tooltip: _destinationTooltip(feature),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Key _destinationKey(PrimaryFeature feature) => switch (feature) {
    PrimaryFeature.capture => const Key('capture-button'),
    PrimaryFeature.soundscape => const Key('soundscape-button'),
    PrimaryFeature.parkGuide => const Key('park-guide-button'),
    PrimaryFeature.natureBook => const Key('works-button'),
  };

  IconData _destinationIcon(PrimaryFeature feature, {required bool selected}) {
    if (mode == ExplorationMode.parent && feature == PrimaryFeature.capture) {
      return selected ? Icons.favorite_rounded : Icons.favorite_outline_rounded;
    }
    return selected ? feature.selectedIcon : feature.icon;
  }

  String _destinationLabel(PrimaryFeature feature) {
    if (mode == ExplorationMode.parent && feature == PrimaryFeature.capture) {
      return '陪伴';
    }
    return feature.navigationLabel;
  }

  String _destinationTooltip(PrimaryFeature feature) {
    if (mode == ExplorationMode.parent && feature == PrimaryFeature.capture) {
      return '家长陪伴';
    }
    return feature.label;
  }
}

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({super.key, required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
