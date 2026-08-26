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
    );
    await coordinator.initialize();

    await coordinator.recordBehavior(ExplorationBehavior.acceptedUncertainty);

    expect(service.uploaded.single.type, 'accepted_uncertainty');
    expect(await queue.pending(), isEmpty);
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
  _FakeFamilyService({required this.connection})
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  final FamilySessionConnection connection;
  final List<FamilyExplorationEvent> uploaded = [];

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
  Future<List<FamilyCommand>> loadCommands(
    String sessionId,
    int afterSequence,
  ) async => const [];
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
