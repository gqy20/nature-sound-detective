import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/family/family_session_coordinator.dart';
import 'package:nature_sound_detective/core/family/family_session_models.dart';
import 'package:nature_sound_detective/core/family/family_session_service.dart';
import 'package:nature_sound_detective/core/family/family_session_store.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';

void main() {
  test('debug builds default family sessions to the production API', () {
    final service = FamilySessionService();
    addTearDown(service.close);

    expect(service.baseUri.toString(), 'https://listen-api.gqy20.top');
  });

  test('event queue serializes concurrent events and keeps sequence', () async {
    final directory = await Directory.systemTemp.createTemp('family-events-');
    addTearDown(() => directory.delete(recursive: true));
    final queue = FamilyEventQueue(directoryProvider: () async => directory);

    await Future.wait([
      queue.append('replayed_audio', const {}),
      queue.append('compared_evidence', const {}),
      queue.append('accepted_uncertainty', const {}),
    ]);
    final events = await queue.pending();

    expect(events.map((event) => event.sequence), [1, 2, 3]);
    expect(events.map((event) => event.eventId).toSet(), hasLength(3));
  });

  test('mission responses use the backward compatible event protocol', () {
    final help = FamilyExplorationEvent(
      eventId: 'evt-help-response',
      sequence: 2,
      type: 'mission_help_requested',
      occurredAt: DateTime.utc(2026, 9, 2),
      payload: const {'command_id': 'cmd-1'},
    );
    final transported = help.toTransportJson();

    expect(transported['event_type'], 'accepted_uncertainty');
    expect(
      (transported['payload'] as Map<String, Object?>)['mission_response'],
      'help',
    );
    expect(
      FamilyExplorationEvent.fromJson(transported).type,
      'mission_help_requested',
    );
  });

  test('service creates parent session with shared anonymous token', () async {
    final directory = await Directory.systemTemp.createTemp('family-service-');
    addTearDown(() => directory.delete(recursive: true));
    var sessionRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/community/session') {
        sessionRequests++;
        return http.Response(
          jsonEncode({
            'token': 'family-token',
            'expires_at':
                DateTime.now()
                    .add(const Duration(days: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
          200,
        );
      }
      expect(request.headers['Authorization'], 'Bearer family-token');
      return http.Response(
        jsonEncode({
          'session_id': 'session-1',
          'pair_code': '472918',
          'status': 'waiting_for_child',
          'pair_expires_at': '2026-08-26T12:05:00Z',
          'expires_at': '2026-08-26T14:00:00Z',
        }),
        201,
      );
    });
    final service = FamilySessionService(
      baseUri: Uri.parse('https://api.example.test'),
      client: client,
      identityStore: CommunityIdentityStore(
        directoryProvider: () async => directory,
      ),
    );

    final connection = await service.createParentSession();

    expect(connection.role, FamilyDeviceRole.parent);
    expect(connection.pairCode, '472918');
    expect(sessionRequests, 1);
  });

  test('child records structured behavior and syncs it', () async {
    final directory = await Directory.systemTemp.createTemp('family-child-');
    addTearDown(() => directory.delete(recursive: true));
    final store = _MemoryFamilySessionStore();
    final queue = FamilyEventQueue(directoryProvider: () async => directory);
    final connection = _connection(FamilyDeviceRole.child);
    await store.save(connection);
    final service = _FakeFamilyService(connection: connection);
    final coordinator = FamilySessionCoordinator(
      service: service,
      store: store,
      eventQueue: queue,
      timelineStore: FamilyTimelineStore(
        directoryProvider: () async => directory,
      ),
    );
    await coordinator.initialize();

    await coordinator.recordBehavior(ExplorationBehavior.acceptedUncertainty);

    expect(service.uploaded.single.type, 'accepted_uncertainty');
    expect(await queue.pending(), isEmpty);
    coordinator.dispose();
  });

  test('child acknowledges and completes a shared mission', () async {
    final directory = await Directory.systemTemp.createTemp('family-mission-');
    addTearDown(() => directory.delete(recursive: true));
    final connection = _connection(FamilyDeviceRole.child);
    final store = _MemoryFamilySessionStore()..value = connection;
    final command = FamilyCommand(
      commandId: 'cmd-1',
      templateId: 'listen_again_before_guessing',
      sequence: 1,
      createdAt: DateTime.utc(2026, 8, 27, 8),
    );
    final service = _FakeFamilyService(
      connection: connection,
      commands: [command],
    );
    final coordinator = FamilySessionCoordinator(
      service: service,
      store: store,
      eventQueue: FamilyEventQueue(directoryProvider: () async => directory),
      timelineStore: FamilyTimelineStore(
        directoryProvider: () async => directory,
      ),
    );

    await coordinator.initialize();
    expect(
      service.uploaded.any((event) => event.type == 'mission_received'),
      isTrue,
    );
    expect(coordinator.activeMission?.commandId, 'cmd-1');
    expect(coordinator.hasPendingMission, isTrue);

    await coordinator.requestMissionHelp();
    await coordinator.deferLatestMission();
    expect(
      service.uploaded.any((event) => event.type == 'mission_help_requested'),
      isTrue,
    );
    expect(
      service.uploaded.any((event) => event.type == 'mission_deferred'),
      isTrue,
    );
    expect(coordinator.missionHelpRequested('cmd-1'), isTrue);
    expect(coordinator.missionDeferred('cmd-1'), isTrue);
    expect(coordinator.activeMission?.commandId, 'cmd-1');

    await coordinator.completeLatestMission();
    expect(
      service.uploaded.any((event) => event.type == 'mission_completed'),
      isTrue,
    );
    expect(coordinator.missionCompleted('cmd-1'), isTrue);
    expect(coordinator.activeMission, isNull);
    expect(coordinator.hasPendingMission, isFalse);
    coordinator.dispose();
  });

  test('parent keeps the latest sent mission for delivery feedback', () async {
    final directory = await Directory.systemTemp.createTemp('family-parent-');
    addTearDown(() => directory.delete(recursive: true));
    final connection = _connection(FamilyDeviceRole.parent);
    final store = _MemoryFamilySessionStore()..value = connection;
    final service = _FakeFamilyService(connection: connection);
    final coordinator = FamilySessionCoordinator(
      service: service,
      store: store,
      eventQueue: FamilyEventQueue(directoryProvider: () async => directory),
      timelineStore: FamilyTimelineStore(
        directoryProvider: () async => directory,
      ),
    );

    await coordinator.initialize();
    await coordinator.sendMission('compare_high_low_sound');
    await coordinator.sendMission('listen_again_before_guessing');

    expect(coordinator.commands.single.templateId, 'compare_high_low_sound');
    expect(service.sentTemplates, ['compare_high_low_sound']);
    coordinator.dispose();
  });

  test('parent restores local timeline without repeating seen cues', () async {
    final directory = await Directory.systemTemp.createTemp('family-timeline-');
    addTearDown(() => directory.delete(recursive: true));
    final connection = _connection(
      FamilyDeviceRole.parent,
    ).copyWith(lastEventSequence: 1);
    final store = _MemoryFamilySessionStore()..value = connection;
    final timelineStore = FamilyTimelineStore(
      directoryProvider: () async => directory,
    );
    final event = FamilyExplorationEvent(
      eventId: 'evt_replay_000001',
      sequence: 1,
      type: 'replayed_audio',
      occurredAt: DateTime.utc(2026, 8, 29, 9),
    );
    await timelineStore.save(
      FamilyTimelineSnapshot(sessionId: connection.sessionId, events: [event]),
    );

    final first = FamilySessionCoordinator(
      service: _FakeFamilyService(connection: connection),
      store: store,
      eventQueue: FamilyEventQueue(directoryProvider: () async => directory),
      timelineStore: timelineStore,
    );
    await first.initialize();

    expect(first.events.single.eventId, event.eventId);
    expect(first.latestCue?.title, '孩子主动回听了声音');
    await first.markCueSeen();
    first.dispose();

    final restored = FamilySessionCoordinator(
      service: _FakeFamilyService(connection: connection),
      store: store,
      eventQueue: FamilyEventQueue(directoryProvider: () async => directory),
      timelineStore: timelineStore,
    );
    await restored.initialize();

    expect(restored.events.single.eventId, event.eventId);
    expect(restored.latestCue, isNull);
    restored.dispose();
  });

  test('marking a cue seen reveals the next unread family event', () async {
    final directory = await Directory.systemTemp.createTemp('family-cues-');
    addTearDown(() => directory.delete(recursive: true));
    final connection = _connection(
      FamilyDeviceRole.parent,
    ).copyWith(lastEventSequence: 2);
    final store = _MemoryFamilySessionStore()..value = connection;
    final timelineStore = FamilyTimelineStore(
      directoryProvider: () async => directory,
    );
    await timelineStore.save(
      FamilyTimelineSnapshot(
        sessionId: connection.sessionId,
        events: [
          FamilyExplorationEvent(
            eventId: 'evt-recorded',
            sequence: 1,
            type: 'captured_sound',
            occurredAt: DateTime.utc(2026, 9, 1, 8),
          ),
          FamilyExplorationEvent(
            eventId: 'evt-uncertain',
            sequence: 2,
            type: 'accepted_uncertainty',
            occurredAt: DateTime.utc(2026, 9, 1, 8, 1),
          ),
        ],
      ),
    );
    final coordinator = FamilySessionCoordinator(
      service: _FakeFamilyService(connection: connection),
      store: store,
      eventQueue: FamilyEventQueue(directoryProvider: () async => directory),
      timelineStore: timelineStore,
    );

    await coordinator.initialize();
    expect(coordinator.latestCue?.eventId, 'evt-uncertain');
    expect(coordinator.unseenCueCount, 2);

    await coordinator.markCueSeen();
    expect(coordinator.latestCue?.eventId, 'evt-recorded');
    expect(coordinator.unseenCueCount, 1);

    await coordinator.markCueSeen();
    expect(coordinator.latestCue, isNull);
    expect(coordinator.unseenCueCount, 0);
    coordinator.dispose();
  });
}

FamilySessionConnection _connection(FamilyDeviceRole role) =>
    FamilySessionConnection(
      sessionId: 'family-session-1',
      role: role,
      status: FamilySessionStatus.active,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

class _FakeFamilyService extends FamilySessionService {
  _FakeFamilyService({required this.connection, this.commands = const []})
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  final FamilySessionConnection connection;
  final List<FamilyCommand> commands;
  final List<FamilyExplorationEvent> uploaded = [];
  final List<String> sentTemplates = [];
  bool _commandsReturned = false;

  @override
  Future<FamilySessionConnection> loadSession(String sessionId) async {
    return connection;
  }

  @override
  Future<int> sendEvents(
    String sessionId,
    List<FamilyExplorationEvent> events,
  ) async {
    uploaded.addAll(events);
    return events.length;
  }

  @override
  Future<List<FamilyExplorationEvent>> loadEvents(
    String sessionId,
    int afterSequence,
  ) async => const [];

  @override
  Future<FamilyCommand> sendCommand(String sessionId, String templateId) async {
    sentTemplates.add(templateId);
    return FamilyCommand(
      commandId: 'cmd-sent',
      templateId: templateId,
      sequence: 1,
      createdAt: DateTime.utc(2026, 8, 27, 9),
    );
  }

  @override
  Future<List<FamilyCommand>> loadCommands(
    String sessionId,
    int afterSequence,
  ) async {
    if (_commandsReturned) return const [];
    _commandsReturned = true;
    return commands;
  }
}

class _MemoryFamilySessionStore extends FamilySessionStore {
  FamilySessionConnection? value;

  @override
  Future<FamilySessionConnection?> load() async => value;

  @override
  Future<void> save(FamilySessionConnection connection) async {
    value = connection;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
