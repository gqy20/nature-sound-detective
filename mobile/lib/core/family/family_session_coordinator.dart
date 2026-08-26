import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nature_sound_detective/core/family/family_session_models.dart';
import 'package:nature_sound_detective/core/family/family_session_service.dart';
import 'package:nature_sound_detective/core/family/family_session_store.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';

class FamilySessionCoordinator extends ChangeNotifier {
  FamilySessionCoordinator({
    FamilySessionService? service,
    FamilySessionStore? store,
    FamilyEventQueue? eventQueue,
  }) : _service = service ?? FamilySessionService(),
       _store = store ?? FamilySessionStore(),
       _eventQueue = eventQueue ?? FamilyEventQueue();

  final FamilySessionService _service;
  final FamilySessionStore _store;
  final FamilyEventQueue _eventQueue;
  final List<FamilyExplorationEvent> _events = [];
  final List<FamilyCommand> _commands = [];
  Timer? _pollTimer;
  FamilySessionConnection? _connection;
  CompanionCue? _latestCue;
  String? _error;
  bool _busy = false;
  bool _refreshing = false;
  bool _syncing = false;
  bool _disposed = false;

  FamilySessionConnection? get connection => _connection;
  List<FamilyExplorationEvent> get events => List.unmodifiable(_events);
  List<FamilyCommand> get commands => List.unmodifiable(_commands);
  CompanionCue? get latestCue => _latestCue;
  String? get error => _error;
  bool get busy => _busy;
  bool get hasUnseenCue => _latestCue != null;

  Future<void> initialize() async {
    _connection = await _store.load();
    if (_connection != null) {
      await refresh();
      _schedulePolling();
    }
    _notify();
  }

  Future<void> createParentSession() async {
    await _run(() async {
      await _eventQueue.clear();
      _connection = await _service.createParentSession();
      _events.clear();
      _commands.clear();
      _latestCue = null;
      await _store.save(_connection!);
      _schedulePolling();
    });
  }

  Future<void> joinAsChild(String pairCode) async {
    await _run(() async {
      await _eventQueue.clear();
      _connection = await _service.joinAsChild(pairCode);
      _events.clear();
      _commands.clear();
      _latestCue = null;
      await _store.save(_connection!);
      _schedulePolling();
    });
  }

  Future<void> approveChild() async {
    final value = _connection;
    if (value == null || value.role != FamilyDeviceRole.parent) return;
    await _run(() async {
      _connection = (await _service.approve(
        value.sessionId,
      )).copyWith(pairCode: value.pairCode, pairExpiresAt: value.pairExpiresAt);
      await _store.save(_connection!);
      _schedulePolling();
    });
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    final value = _connection;
    if (value == null) return;
    _refreshing = true;
    try {
      final status = await _service.loadSession(value.sessionId);
      _connection = status.copyWith(
        pairCode: value.pairCode,
        pairExpiresAt: value.pairExpiresAt,
        lastEventSequence: value.lastEventSequence,
        lastCommandSequence: value.lastCommandSequence,
      );
      if (_connection!.active) {
        if (_connection!.role == FamilyDeviceRole.parent) {
          await _pollParentEvents();
        } else {
          await _syncPendingEvents();
          await _pollChildCommands();
        }
      }
      await _store.save(_connection!);
      _error = null;
    } catch (error) {
      _error = error.toString();
    } finally {
      _refreshing = false;
    }
    _notify();
  }

  Future<void> recordBehavior(
    ExplorationBehavior behavior, {
    Map<String, Object?> payload = const {},
  }) async {
    final value = _connection;
    if (value == null ||
        value.role != FamilyDeviceRole.child ||
        !value.active) {
      return;
    }
    final type = switch (behavior) {
      ExplorationBehavior.capturedSound => 'captured_sound',
      ExplorationBehavior.importedSound => 'imported_sound',
      ExplorationBehavior.recordedSound => 'captured_sound',
      ExplorationBehavior.replayedAudio => 'replayed_audio',
      ExplorationBehavior.completedObservation => 'completed_observation',
      ExplorationBehavior.comparedEvidence => 'compared_evidence',
      ExplorationBehavior.acceptedUncertainty => 'accepted_uncertainty',
      ExplorationBehavior.retriedRecording => 'retried_recording',
      ExplorationBehavior.observedSafely => 'completed_safe_route_stop',
    };
    final event = await _eventQueue.append(type, payload);
    _events.add(event);
    await _syncPendingEvents();
    _notify();
  }

  Future<void> sendMission(String templateId) async {
    final value = _connection;
    if (value == null ||
        value.role != FamilyDeviceRole.parent ||
        !value.active) {
      return;
    }
    await _run(() async {
      await _service.sendCommand(value.sessionId, templateId);
    });
  }

  void markCueSeen() {
    if (_latestCue == null) return;
    _latestCue = null;
    _notify();
  }

  Future<void> endSession() async {
    final value = _connection;
    if (value == null) return;
    await _run(() async {
      if (value.role == FamilyDeviceRole.parent) {
        await _service.end(value.sessionId);
      }
      await _clearLocal();
    });
  }

  Future<void> leaveLocalSession() => _run(_clearLocal);

  Future<void> _clearLocal() async {
    _pollTimer?.cancel();
    _connection = null;
    _events.clear();
    _commands.clear();
    _latestCue = null;
    await _store.clear();
    await _eventQueue.clear();
  }

  Future<void> _syncPendingEvents() async {
    if (_syncing) return;
    final value = _connection;
    if (value == null ||
        value.role != FamilyDeviceRole.child ||
        !value.active) {
      return;
    }
    _syncing = true;
    try {
      final events = await _eventQueue.pending();
      if (events.isEmpty) return;
      await _service.sendEvents(value.sessionId, events);
      await _eventQueue.remove(events.map((event) => event.eventId));
    } finally {
      _syncing = false;
    }
  }

  Future<void> _pollParentEvents() async {
    final value = _connection;
    if (value == null ||
        value.role != FamilyDeviceRole.parent ||
        !value.active) {
      return;
    }
    final fresh = await _service.loadEvents(
      value.sessionId,
      value.lastEventSequence,
    );
    if (fresh.isEmpty) return;
    _events.addAll(fresh);
    final lastSequence = fresh.last.sequence;
    _connection = value.copyWith(lastEventSequence: lastSequence);
    _latestCue = const CompanionCueEngine().build(fresh);
    await _store.save(_connection!);
  }

  Future<void> _pollChildCommands() async {
    final value = _connection;
    if (value == null ||
        value.role != FamilyDeviceRole.child ||
        !value.active) {
      return;
    }
    final fresh = await _service.loadCommands(
      value.sessionId,
      value.lastCommandSequence,
    );
    if (fresh.isEmpty) return;
    _commands.addAll(fresh);
    _connection = value.copyWith(lastCommandSequence: fresh.last.sequence);
    await _store.save(_connection!);
  }

  void _schedulePolling() {
    _pollTimer?.cancel();
    if (_connection == null ||
        _connection!.status == FamilySessionStatus.ended ||
        _connection!.status == FamilySessionStatus.expired) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_busy) unawaited(refresh());
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      await action();
    } catch (error) {
      _error = error.toString();
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _service.close();
    super.dispose();
  }
}
