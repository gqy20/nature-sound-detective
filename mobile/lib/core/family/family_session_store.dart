import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nature_sound_detective/core/family/family_session_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FamilySessionStore {
  FamilySessionStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<FamilySessionConnection?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<Object?, Object?>) return null;
      return FamilySessionConnection.fromJson(value.cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  Future<void> save(FamilySessionConnection connection) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(connection.toJson()), flush: true);
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<File> _file() async {
    final directory = await _directoryProvider();
    return File(p.join(directory.path, 'config', 'family_session.json'));
  }
}

class FamilyEventQueue {
  FamilyEventQueue({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<FamilyExplorationEvent> append(
    String type,
    Map<String, Object?> payload,
  ) => _serial(() async {
    final state = await _read();
    final sequence = state.nextSequence;
    final event = FamilyExplorationEvent(
      eventId:
          'evt_${DateTime.now().microsecondsSinceEpoch}_${sequence.toString().padLeft(6, '0')}',
      sequence: sequence,
      type: type,
      occurredAt: DateTime.now().toUtc(),
      payload: payload,
    );
    await _write(
      _EventQueueState(
        nextSequence: sequence + 1,
        events: [...state.events, event],
      ),
    );
    return event;
  });

  Future<List<FamilyExplorationEvent>> pending() =>
      _serial(() async => (await _read()).events);

  Future<void> remove(Iterable<String> eventIds) => _serial(() async {
    final ids = eventIds.toSet();
    if (ids.isEmpty) return;
    final state = await _read();
    await _write(
      _EventQueueState(
        nextSequence: state.nextSequence,
        events: state.events
            .where((event) => !ids.contains(event.eventId))
            .toList(growable: false),
      ),
    );
  });

  Future<void> clear() => _serial(() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  });

  Future<_EventQueueState> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const _EventQueueState();
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<Object?, Object?>) return const _EventQueueState();
      final json = value.cast<String, Object?>();
      return _EventQueueState(
        nextSequence: (json['next_sequence'] as num?)?.toInt() ?? 1,
        events: (json['events'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map(
              (event) => FamilyExplorationEvent.fromJson(
                event.cast<String, Object?>(),
              ),
            )
            .toList(growable: false),
      );
    } catch (_) {
      return const _EventQueueState();
    }
  }

  Future<void> _write(_EventQueueState state) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'next_sequence': state.nextSequence,
        'events': state.events.map((event) => event.toJson()).toList(),
      }),
      flush: true,
    );
  }

  Future<File> _file() async {
    final directory = await _directoryProvider();
    return File(p.join(directory.path, 'config', 'family_event_queue.json'));
  }
}

class FamilyTimelineSnapshot {
  const FamilyTimelineSnapshot({
    required this.sessionId,
    this.events = const [],
    this.commands = const [],
    this.seenCueEventIds = const [],
  });

  final String sessionId;
  final List<FamilyExplorationEvent> events;
  final List<FamilyCommand> commands;
  final List<String> seenCueEventIds;
}

class FamilyTimelineStore {
  FamilyTimelineStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<FamilyTimelineSnapshot?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<Object?, Object?>) return null;
      final json = value.cast<String, Object?>();
      final sessionId = json['session_id'] as String? ?? '';
      if (sessionId.isEmpty) return null;
      return FamilyTimelineSnapshot(
        sessionId: sessionId,
        events: (json['events'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map(
              (event) => FamilyExplorationEvent.fromJson(
                event.cast<String, Object?>(),
              ),
            )
            .toList(growable: false),
        commands: (json['commands'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map(
              (command) =>
                  FamilyCommand.fromJson(command.cast<String, Object?>()),
            )
            .toList(growable: false),
        seenCueEventIds:
            (json['seen_cue_event_ids'] as List<Object?>? ?? const [])
                .whereType<String>()
                .toList(growable: false),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(FamilyTimelineSnapshot snapshot) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'session_id': snapshot.sessionId,
        'events': snapshot.events.map((event) => event.toJson()).toList(),
        'commands': snapshot.commands
            .map((command) => command.toJson())
            .toList(),
        'seen_cue_event_ids': snapshot.seenCueEventIds,
      }),
      flush: true,
    );
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<File> _file() async {
    final directory = await _directoryProvider();
    return File(p.join(directory.path, 'config', 'family_timeline.json'));
  }
}

class _EventQueueState {
  const _EventQueueState({this.nextSequence = 1, this.events = const []});
  final int nextSequence;
  final List<FamilyExplorationEvent> events;
}
