import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nature_sound_detective/core/family/family_session_models.dart';
import 'package:nature_sound_detective/core/family/family_session_service.dart';
import 'package:nature_sound_detective/core/family/family_session_store.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';

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
  DateTime? _lastSyncedAt;

  FamilySessionConnection? get connection => _connection;
  List<FamilyExplorationEvent> get events => List.unmodifiable(_events);
  List<FamilyCommand> get commands => List.unmodifiable(_commands);
  CompanionCue? get latestCue => _latestCue;
  String? get error => _error;
  bool get busy => _busy;
  bool get hasUnseenCue => _latestCue != null;
  bool get syncing => _syncing || _refreshing;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  Future<void> initialize() async {
    AppLog.info(
      'family',
      'family_service_configured',
      fields: {
        'api_scheme': _service.baseUri.scheme,
        'api_host': _service.baseUri.host,
      },
    );
    try {
      _connection = await _store.load();
      if (_connection != null) {
        await refresh();
        _schedulePolling();
      }
      AppLog.info(
        'family',
        'family_session_initialized',
        fields: {
          'restored': _connection != null,
          'role': _connection?.role.name,
          'status': _connection?.status.name,
        },
      );
    } catch (error, stackTrace) {
      _error = error.toString();
      AppLog.warning(
        'family',
        'family_session_initialize_failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _notify();
  }

  Future<void> createParentSession() async {
    await _run('create_parent_session', () async {
      await _eventQueue.clear();
      _connection = await _service.createParentSession();
      _events.clear();
      _commands.clear();
      _latestCue = null;
      _lastSyncedAt = DateTime.now();
      await _store.save(_connection!);
      _schedulePolling();
    });
  }

  Future<void> joinAsChild(String pairCode) async {
    await _run('join_as_child', () async {
      await _eventQueue.clear();
      _connection = await _service.joinAsChild(pairCode);
      _events.clear();
      _commands.clear();
      _latestCue = null;
      _lastSyncedAt = DateTime.now();
      await _store.save(_connection!);
      _schedulePolling();
    });
  }

  Future<void> approveChild() async {
    final value = _connection;
    if (value == null || value.role != FamilyDeviceRole.parent) return;
    await _run('approve_child', () async {
      _connection = (await _service.approve(
        value.sessionId,
      )).copyWith(pairCode: value.pairCode, pairExpiresAt: value.pairExpiresAt);
      _lastSyncedAt = DateTime.now();
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
      _lastSyncedAt = DateTime.now();
    } catch (error, stackTrace) {
      _error = error.toString();
      AppLog.warning(
        'family',
        'family_session_refresh_failed',
        fields: {'role': value.role.name, 'status': value.status.name},
        error: error,
        stackTrace: stackTrace,
      );
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
    await _run('send_mission', () async {
      final command = await _service.sendCommand(value.sessionId, templateId);
      _commands.add(command);
      _lastSyncedAt = DateTime.now();
    });
  }

  Future<void> completeLatestMission() async {
    final value = _connection;
    final command = _commands.lastOrNull;
    if (value == null ||
        command == null ||
        value.role != FamilyDeviceRole.child ||
        !value.active ||
        missionCompleted(command.commandId)) {
      return;
    }
    final event = await _eventQueue.append('mission_completed', {
      'command_id': command.commandId,
      'template_id': command.templateId,
    });
    _events.add(event);
    await _syncPendingEvents();
    _notify();
  }

  bool missionReceived(String commandId) => _events.any(
    (event) =>
        event.type == 'mission_received' &&
        event.payload['command_id'] == commandId,
  );

  bool missionCompleted(String commandId) => _events.any(
    (event) =>
        event.type == 'mission_completed' &&
        event.payload['command_id'] == commandId,
  );

  void markCueSeen() {
    if (_latestCue == null) return;
    _latestCue = null;
    _notify();
  }

  Future<void> endSession() async {
    final value = _connection;
    if (value == null) return;
    await _run('end_session', () async {
      if (value.role == FamilyDeviceRole.parent) {
        await _service.end(value.sessionId);
      }
      await _clearLocal();
    });
  }

  Future<void> leaveLocalSession() => _run('leave_local_session', _clearLocal);

  Future<void> _clearLocal() async {
    _pollTimer?.cancel();
    _connection = null;
    _events.clear();
    _commands.clear();
    _latestCue = null;
    _lastSyncedAt = null;
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
      AppLog.debug(
        'family',
        'family_event_sync_started',
        fields: {'event_count': events.length},
      );
      await _service.sendEvents(value.sessionId, events);
      await _eventQueue.remove(events.map((event) => event.eventId));
      _lastSyncedAt = DateTime.now();
      AppLog.info(
        'family',
        'family_event_sync_completed',
        fields: {'event_count': events.length},
      );
    } catch (error, stackTrace) {
      AppLog.warning(
        'family',
        'family_event_sync_failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
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
    _lastSyncedAt = DateTime.now();
    await _store.save(_connection!);
    AppLog.info(
      'family',
      'family_parent_events_received',
      fields: {'event_count': fresh.length, 'last_sequence': lastSequence},
    );
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
    for (final command in fresh) {
      final event = await _eventQueue.append('mission_received', {
        'command_id': command.commandId,
        'template_id': command.templateId,
      });
      _events.add(event);
    }
    await _syncPendingEvents();
    _lastSyncedAt = DateTime.now();
    await _store.save(_connection!);
    AppLog.info(
      'family',
      'family_child_commands_received',
      fields: {
        'command_count': fresh.length,
        'last_sequence': fresh.last.sequence,
      },
    );
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

  Future<void> _run(String operation, Future<void> Function() action) async {
    if (_busy) {
      AppLog.warning(
        'family',
        'family_operation_blocked',
        fields: {'operation': operation, 'reason': 'another_operation_active'},
      );
      return;
    }
    _busy = true;
    _error = null;
    AppLog.info(
      'family',
      'family_operation_started',
      fields: {'operation': operation},
    );
    _notify();
    try {
      await action();
      AppLog.info(
        'family',
        'family_operation_completed',
        fields: {
          'operation': operation,
          'role': _connection?.role.name,
          'status': _connection?.status.name,
        },
      );
    } catch (error, stackTrace) {
      _error = error.toString();
      AppLog.warning(
        'family',
        'family_operation_failed',
        fields: {'operation': operation},
        error: error,
        stackTrace: stackTrace,
      );
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
