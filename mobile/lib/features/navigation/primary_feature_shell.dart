import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/family/family_session_coordinator.dart';
import 'package:nature_sound_detective/core/community/soundscape_preloader.dart';
import 'package:nature_sound_detective/core/inference/recording_analyzer.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode.dart';
import 'package:nature_sound_detective/core/storage/exploration_store.dart';
import 'package:nature_sound_detective/features/capture/capture_page.dart';
import 'package:nature_sound_detective/features/community/soundscape_page.dart';
import 'package:nature_sound_detective/features/library/nature_book_page.dart';
import 'package:nature_sound_detective/features/navigation/primary_feature.dart';
import 'package:nature_sound_detective/features/park_guide/park_guide_page.dart';

class PrimaryFeatureShell extends StatefulWidget {
  const PrimaryFeatureShell({
    super.key,
    this.analyzer,
    required this.mode,
    required this.onModeChanged,
    required this.familySessionCoordinator,
    this.preloadSoundscape = true,
  });

  final RecordingAnalyzer? analyzer;
  final ExplorationMode mode;
  final ValueChanged<ExplorationMode> onModeChanged;
  final FamilySessionCoordinator familySessionCoordinator;
  final bool preloadSoundscape;

  @override
  State<PrimaryFeatureShell> createState() => _PrimaryFeatureShellState();
}

class _PrimaryFeatureShellState extends State<PrimaryFeatureShell>
    with SingleTickerProviderStateMixin {
  final PageController _controller = PageController();
  final ValueNotifier<double> _pagePositionNotifier = ValueNotifier(0);
  final ExplorationStore _store = FileExplorationStore();
  late final AnimationController _directTransitionController;
  SoundscapePreloader? _soundscapePreloader;
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

  @override
  void initState() {
    super.initState();
    _directTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    if (widget.preloadSoundscape) {
      _soundscapePreloader = SoundscapePreloader();
      unawaited(_startSoundscapePreload());
    }
    _controller.addListener(_trackPagePosition);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_soundscapeMapPrecacheStarted) return;
    _soundscapeMapPrecacheStarted = true;
    unawaited(_precacheSoundscapeMap());
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
    _controller
      ..removeListener(_trackPagePosition)
      ..dispose();
    _pagePositionNotifier.dispose();
    _directTransitionController.dispose();
    _navigationSettleTimer?.cancel();
    _soundscapePreloader?.close();
    super.dispose();
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
    final fromIndex = _settledIndex;
    final from = PrimaryFeature.values[fromIndex];
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
    if (feature.index == fromIndex) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion ||
        trigger == 'system_back' ||
        (feature.index - fromIndex).abs() > 1) {
      await _fadeThroughTo(feature, trigger: trigger, animate: !reduceMotion);
      return;
    }
    setState(() => _transitioning = true);
    _activeNavigationTrigger = trigger;
    try {
      await _controller.animateToPage(
        feature.index,
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
      _controller.jumpToPage(feature.index);
      _pagePositionNotifier.value = feature.index.toDouble();
      if (_selectedIndex != feature.index && mounted) {
        setState(() => _selectedIndex = feature.index);
      }
      _settledIndex = feature.index;
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
          'from': PrimaryFeature.values[fromIndex].name,
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
        fields: {'from': PrimaryFeature.values[_gestureStartIndex].name},
      );
      AppLog.info(
        'navigation',
        'primary_navigation_requested',
        fields: {
          'from': PrimaryFeature.values[_gestureStartIndex].name,
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
    final finalIndex = (_controller.page ?? _selectedIndex.toDouble())
        .round()
        .clamp(0, PrimaryFeature.values.length - 1)
        .toInt();
    if (_selectedIndex != finalIndex && mounted) {
      setState(() => _selectedIndex = finalIndex);
    }
    if (finalIndex == _settledIndex) {
      if (_userDragging) {
        AppLog.debug(
          'navigation',
          'primary_swipe_cancelled',
          fields: {'current': PrimaryFeature.values[finalIndex].name},
        );
      }
      _userDragging = false;
      _activeNavigationTrigger = null;
      return;
    }
    final from = PrimaryFeature.values[_settledIndex];
    final to = PrimaryFeature.values[finalIndex];
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

  @override
  Widget build(BuildContext context) {
    final rawPages = <Widget>[
      _KeepAlivePage(
        key: const ValueKey(PrimaryFeature.capture),
        child: CapturePage(
          key: const ValueKey('primary-capture-content'),
          analyzer: widget.analyzer,
          store: _store,
          mode: widget.mode,
          onModeChanged: widget.onModeChanged,
          familySessionCoordinator: widget.familySessionCoordinator,
          primaryPagePosition: _pagePositionNotifier,
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
          onOpenParkGuide: () =>
              _selectFeature(PrimaryFeature.parkGuide, trigger: 'button'),
        ),
      ),
      const _KeepAlivePage(
        key: ValueKey(PrimaryFeature.parkGuide),
        child: ParkGuidePage(key: ValueKey('primary-park-guide-content')),
      ),
      _KeepAlivePage(
        key: const ValueKey(PrimaryFeature.natureBook),
        child: NatureBookPage(
          key: const ValueKey('primary-nature-book-content'),
          store: _store,
          onOpenSoundscape: () =>
              _selectFeature(PrimaryFeature.soundscape, trigger: 'button'),
        ),
      ),
    ];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pages = <Widget>[
      for (var index = 0; index < rawPages.length; index++)
        _PrimaryPageMotion(
          index: index,
          pagePosition: _pagePositionNotifier,
          enabled: !reduceMotion,
          child: rawPages[index],
        ),
    ];

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
        body: Stack(
          children: [
            AnimatedBuilder(
              animation: _directTransitionController,
              builder: (context, child) {
                final progress = _directTransitionController.value;
                final opacity = progress <= .35
                    ? 1 - progress / .35
                    : (progress - .35) / .65;
                final scale = progress <= .35
                    ? 1 - progress / .35 * .015
                    : .985 + (progress - .35) / .65 * .015;
                return ColoredBox(
                  color: const Color(0xFFE5EDE7),
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.scale(scale: scale, child: child),
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
                  'current-primary-feature-${PrimaryFeature.values[_selectedIndex].name}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryPageMotion extends StatelessWidget {
  const _PrimaryPageMotion({
    required this.index,
    required this.pagePosition,
    required this.enabled,
    required this.child,
  });

  final int index;
  final ValueListenable<double> pagePosition;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return AnimatedBuilder(
      animation: pagePosition,
      child: child,
      builder: (context, child) {
        final distance = (pagePosition.value - index).abs().clamp(0.0, 1.0);
        final scale = 1 - distance * .014;
        final radius = distance * 18;
        return Transform.scale(
          scale: scale,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: child,
          ),
        );
      },
    );
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
