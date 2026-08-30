import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/family/family_session_coordinator.dart';
import 'package:nature_sound_detective/core/family/family_session_models.dart';
import 'package:nature_sound_detective/core/inference/recording_analyzer.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode_store.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/storage/creation_store.dart';
import 'package:nature_sound_detective/core/storage/creation_settings_store.dart';
import 'package:nature_sound_detective/features/creation/creation_page.dart';
import 'package:nature_sound_detective/features/navigation/primary_feature_shell.dart';
import 'package:nature_sound_detective/features/navigation/primary_feature_store.dart';

class NatureSoundApp extends StatefulWidget {
  const NatureSoundApp({
    super.key,
    this.analyzer,
    this.modeStore,
    this.familySessionCoordinator,
    this.creationStore,
    this.activeCreationStore,
    this.creationSettingsStore,
    this.primaryFeatureStore,
    this.preloadSoundscape = true,
  });

  final RecordingAnalyzer? analyzer;
  final ExplorationModeStore? modeStore;
  final FamilySessionCoordinator? familySessionCoordinator;
  final CreationStore? creationStore;
  final ActiveCreationStore? activeCreationStore;
  final CreationSettingsStore? creationSettingsStore;
  final PrimaryFeatureStore? primaryFeatureStore;
  final bool preloadSoundscape;

  @override
  State<NatureSoundApp> createState() => _NatureSoundAppState();
}

class _NatureSoundAppState extends State<NatureSoundApp>
    with WidgetsBindingObserver {
  late final ExplorationModeStore _modeStore;
  late final FamilySessionCoordinator _familySessionCoordinator;
  late final bool _ownsFamilySessionCoordinator;
  late final CreationStore _creationStore;
  late final ActiveCreationStore _activeCreationStore;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  ExplorationMode _mode = ExplorationMode.child;
  bool _resumeRouteScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _modeStore = widget.modeStore ?? ExplorationModeStore();
    _ownsFamilySessionCoordinator = widget.familySessionCoordinator == null;
    _familySessionCoordinator =
        widget.familySessionCoordinator ?? FamilySessionCoordinator();
    _creationStore = widget.creationStore ?? CreationStore();
    _activeCreationStore = widget.activeCreationStore ?? ActiveCreationStore();
    _familySessionCoordinator.addListener(_syncModeToFamilyRole);
    unawaited(
      _familySessionCoordinator.initialize().then(
        (_) => _syncModeToFamilyRole(),
      ),
    );
    _loadMode();
    unawaited(_restoreActiveCreationRoute());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _familySessionCoordinator.removeListener(_syncModeToFamilyRole);
    if (_ownsFamilySessionCoordinator) _familySessionCoordinator.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_familySessionCoordinator.resumePolling());
    } else if ({
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    }.contains(state)) {
      _familySessionCoordinator.pausePolling();
    }
  }

  Future<void> _loadMode() async {
    final value = await _modeStore.load();
    if (mounted) {
      setState(() => _mode = value);
      _syncModeToFamilyRole();
    }
  }

  Future<void> _restoreActiveCreationRoute() async {
    final recordId = await _activeCreationStore.load();
    if (!mounted || recordId == null || _resumeRouteScheduled) return;
    final record = await _creationStore.load(recordId);
    if (!mounted ||
        record == null ||
        {CreationStage.idle, CreationStage.completed}.contains(record.stage)) {
      await _activeCreationStore.clear();
      return;
    }
    final activelyRunning = {
      CreationStage.generatingMusic,
      CreationStage.generatingNarration,
      CreationStage.submittingVideo,
      CreationStage.waitingForVideo,
      CreationStage.downloadingVideo,
      CreationStage.composing,
    }.contains(record.stage);
    if (!activelyRunning) await _activeCreationStore.clear();
    _resumeRouteScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigatorKey.currentState
          ?.push<void>(
            MaterialPageRoute(
              builder: (_) => CreationPage(
                subject: record.subject,
                location: record.location,
                existingRecord: record,
                activeCreationStore: _activeCreationStore,
                settingsStore: widget.creationSettingsStore,
              ),
            ),
          )
          .whenComplete(() => _resumeRouteScheduled = false);
    });
  }

  void _setMode(ExplorationMode value) {
    final family = _familySessionCoordinator.connection;
    if (family?.active == true) {
      final requiredMode = family!.role == FamilyDeviceRole.parent
          ? ExplorationMode.parent
          : ExplorationMode.child;
      if (value != requiredMode) return;
    }
    if (_mode == value) return;
    setState(() => _mode = value);
    unawaited(_modeStore.save(value).catchError((_) {}));
  }

  void _syncModeToFamilyRole() {
    final connection = _familySessionCoordinator.connection;
    if (!mounted || connection?.active != true) return;
    final value = connection!.role == FamilyDeviceRole.parent
        ? ExplorationMode.parent
        : ExplorationMode.child;
    if (_mode == value) return;
    setState(() => _mode = value);
    unawaited(_modeStore.save(value).catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    const forest = Color(0xFF174936);
    const ink = Color(0xFF17251F);
    const ivory = Color(0xFFF8F5EC);

    return MaterialApp(
      restorationScopeId: 'nature_sound_app',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: '自然声探员',
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: forest,
              brightness: Brightness.light,
              surface: ivory,
            ).copyWith(
              primary: forest,
              onPrimary: Colors.white,
              onSurface: ink,
              outline: const Color(0xFFB9B7AB),
            ),
        scaffoldBackgroundColor: ivory,
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: ink,
            fontSize: 31,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
          ),
          titleLarge: TextStyle(
            color: ink,
            fontSize: 20,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(
            color: Color(0xFF66716B),
            fontSize: 16,
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            color: Color(0xFF66716B),
            fontSize: 14,
            height: 1.45,
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Color(0xEFFFFFFA),
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
        ),
        dialogTheme: const DialogThemeData(
          elevation: 10,
          backgroundColor: Color(0xFFFFFDF7),
          surfaceTintColor: Colors.transparent,
          shadowColor: Color(0x331A352B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(28)),
            side: BorderSide(color: Color(0xFFE2DDCF)),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          elevation: 8,
          modalElevation: 12,
          backgroundColor: Color(0xFFFFFDF7),
          modalBackgroundColor: Color(0xFFFFFDF7),
          surfaceTintColor: Colors.transparent,
          shadowColor: Color(0x331A352B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          showDragHandle: true,
          dragHandleColor: Color(0xFFB8B5AA),
          dragHandleSize: Size(38, 4),
        ),
        popupMenuTheme: PopupMenuThemeData(
          elevation: 10,
          color: const Color(0xFFFFFDF7),
          surfaceTintColor: Colors.transparent,
          shadowColor: const Color(0x331A352B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE2DDCF)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            side: const BorderSide(color: Color(0xFFD5D2C6)),
          ),
        ),
        useMaterial3: true,
      ),
      home: PrimaryFeatureShell(
        analyzer: widget.analyzer,
        mode: _mode,
        onModeChanged: _setMode,
        familySessionCoordinator: _familySessionCoordinator,
        preloadSoundscape: widget.preloadSoundscape,
        featureStore: widget.primaryFeatureStore,
      ),
    );
  }
}
