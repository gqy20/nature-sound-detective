import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/family/family_session_coordinator.dart';
import 'package:nature_sound_detective/core/family/family_session_models.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';
import 'package:nature_sound_detective/core/network/parent_guidance_service.dart';
import 'package:nature_sound_detective/features/family/family_link_page.dart';

void main() {
  testWidgets('parent sees the latest private companion cue', (tester) async {
    final coordinator = _FakeCoordinator();
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      MaterialApp(home: FamilyLinkPage(coordinator: coordinator)),
    );
    await tester.pump();

    expect(find.text('孩子主动回听了声音'), findsOneWidget);
    expect(find.textContaining('又认真听了一遍'), findsOneWidget);
    expect(find.text('发送共同任务'), findsOneWidget);
    expect(find.text('探索时间线'), findsOneWidget);
  });

  testWidgets('companion settings keeps AI usage away from praise', (
    tester,
  ) async {
    final coordinator = _FakeCoordinator();
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: FamilyLinkPage(
          coordinator: coordinator,
          guidanceService: _FakeGuidanceService(),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('family-companion-settings')));
    await tester.pumpAndSettle();

    expect(find.text('AI个性化回应'), findsWidgets);
    expect(find.textContaining('已使用 7 / 20，剩余 13 次'), findsOneWidget);
    expect(find.textContaining('本地陪伴提示不消耗次数'), findsOneWidget);
  });
}

class _FakeGuidanceService extends ParentGuidanceNetworkService {
  @override
  Future<ParentGuidanceQuota?> loadQuota() async =>
      const ParentGuidanceQuota(limit: 20, used: 7, remaining: 13);
}

class _FakeCoordinator extends FamilySessionCoordinator {
  final _connection = FamilySessionConnection(
    sessionId: 'family-session-1',
    role: FamilyDeviceRole.parent,
    status: FamilySessionStatus.active,
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );
  final _event = FamilyExplorationEvent(
    eventId: 'evt_parent_replay_00000001',
    sequence: 1,
    type: 'replayed_audio',
    occurredAt: DateTime.utc(2026, 8, 26, 12),
  );

  @override
  FamilySessionConnection get connection => _connection;

  @override
  List<FamilyExplorationEvent> get events => [_event];

  @override
  CompanionCue get latestCue => CompanionCue(
    eventId: _event.eventId,
    behavior: ExplorationBehavior.replayedAudio,
    title: '孩子主动回听了声音',
    say: '你没有急着选答案，而是又认真听了一遍。',
    explanation: '肯定主动求证的行为。',
    priority: 55,
  );
}
