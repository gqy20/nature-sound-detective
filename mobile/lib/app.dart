import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/family/family_session_coordinator.dart';
import 'package:nature_sound_detective/core/family/family_session_models.dart';
import 'package:nature_sound_detective/core/inference/recording_analyzer.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode_store.dart';
import 'package:nature_sound_detective/features/navigation/primary_feature_shell.dart';

class NatureSoundApp extends StatefulWidget {
  const NatureSoundApp({
    super.key,
    this.analyzer,
    this.modeStore,
    this.familySessionCoordinator,
    this.preloadSoundscape = true,
  });

  final RecordingAnalyzer? analyzer;
  final ExplorationModeStore? modeStore;
  final FamilySessionCoordinator? familySessionCoordinator;
  final bool preloadSoundscape;

  @override
  State<NatureSoundApp> createState() => _NatureSoundAppState();
}

class _NatureSoundAppState extends State<NatureSoundApp> {
  late final ExplorationModeStore _modeStore;
  late final FamilySessionCoordinator _familySessionCoordinator;
  late final bool _ownsFamilySessionCoordinator;
  ExplorationMode _mode = ExplorationMode.child;

  @override
  void initState() {
    super.initState();
    _modeStore = widget.modeStore ?? ExplorationModeStore();
    _ownsFamilySessionCoordinator = widget.familySessionCoordinator == null;
    _familySessionCoordinator =
        widget.familySessionCoordinator ?? FamilySessionCoordinator();
    _familySessionCoordinator.addListener(_syncModeToFamilyRole);
    unawaited(
      _familySessionCoordinator.initialize().then(
        (_) => _syncModeToFamilyRole(),
      ),
    );
    _loadMode();
  }

  @override
  void dispose() {
    _familySessionCoordinator.removeListener(_syncModeToFamilyRole);
    if (_ownsFamilySessionCoordinator) _familySessionCoordinator.dispose();
    super.dispose();
  }

  Future<void> _loadMode() async {
    final value = await _modeStore.load();
    if (mounted) {
      setState(() => _mode = value);
      _syncModeToFamilyRole();
    }
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
      ),
    );
  }
}
