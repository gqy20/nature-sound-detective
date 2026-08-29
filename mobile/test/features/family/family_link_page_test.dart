import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/family/family_session_coordinator.dart';
import 'package:nature_sound_detective/core/family/family_session_models.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
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
    expect(find.text('现在可以说'), findsNothing);
    expect(find.text('肯定主动求证的行为。'), findsNothing);
    await tester.tap(find.byKey(const Key('open-companion-cue-reason')));
    await tester.pumpAndSettle();
    expect(find.text('为什么这样回应'), findsOneWidget);
    expect(find.text('肯定主动求证的行为。'), findsOneWidget);
    await tester.tap(find.byType(ModalBarrier).last);
    await tester.pumpAndSettle();
    expect(find.text('发送共同任务'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('family-mission-delivery-status')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('儿童已收到'), findsOneWidget);
    expect(find.text('探索时间线'), findsOneWidget);
  });

  testWidgets('child connection waits for a complete six digit code', (
    tester,
  ) async {
    final coordinator = _UnlinkedCoordinator();
    addTearDown(coordinator.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FamilyLinkPage(
          coordinator: coordinator,
          preferredRole: FamilyDeviceRole.child,
        ),
      ),
    );

    expect(find.text('连接家长陪伴端'), findsOneWidget);
    expect(find.text('这是家长陪伴设备'), findsNothing);
    expect(find.text('这是儿童探索设备'), findsOneWidget);
    expect(find.byKey(const Key('family-companion-settings')), findsNothing);
    final join = find.byKey(const Key('join-family-session'));
    expect(tester.widget<FilledButton>(join).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('family-pair-code-field')),
      '123456',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(join).onPressed, isNotNull);
  });

  testWidgets('parent role only shows the parent connection flow', (
    tester,
  ) async {
    final coordinator = _UnlinkedCoordinator();
    addTearDown(coordinator.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FamilyLinkPage(
          coordinator: coordinator,
          preferredRole: FamilyDeviceRole.parent,
        ),
      ),
    );

    expect(find.text('连接儿童探索端'), findsOneWidget);
    expect(find.text('这是家长陪伴设备'), findsOneWidget);
    expect(find.text('这是儿童探索设备'), findsNothing);
    expect(find.byKey(const Key('family-pair-code-field')), findsNothing);
    expect(find.byKey(const Key('family-companion-settings')), findsOneWidget);
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

  testWidgets(
    'AI companion exposes three selectable responses and its source',
    (tester) async {
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

      await tester.tap(
        find.byKey(const Key('generate-family-session-ai-guidance')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('AI根据本次探索生成'), findsOneWidget);
      expect(
        find.byKey(const Key('family-ai-response-option-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('family-ai-response-option-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('family-ai-response-option-2')),
        findsOneWidget,
      );
      expect(find.text('认真求证'), findsOneWidget);
      expect(find.text('比较证据'), findsOneWidget);
      expect(find.text('继续探索'), findsOneWidget);

      await tester.tap(find.byKey(const Key('family-ai-response-option-1')));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const Key('family-ai-response-option-1')),
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsOneWidget,
      );
    },
  );
}

class _FakeGuidanceService extends ParentGuidanceNetworkService {
  @override
  Future<ParentGuidanceQuota?> loadQuota() async =>
      const ParentGuidanceQuota(limit: 20, used: 7, remaining: 13);

  @override
  Future<GuidanceBundle> create({
    required SoundDetection? detection,
    required Map<String, List<String>> observations,
    required Set<ExplorationBehavior> behaviors,
    required bool weakSignal,
    List<FamilyExplorationEvent> events = const [],
  }) async => const GuidanceBundle(
    guides: [],
    praiseSuggestions: [
      PraiseSuggestion(
        behavior: ExplorationBehavior.replayedAudio,
        ability: '认真求证',
        text: '你愿意重新听一遍，让刚才的猜想有了更多声音证据。',
      ),
      PraiseSuggestion(
        behavior: ExplorationBehavior.replayedAudio,
        ability: '比较证据',
        text: '你把前后两次听见的声音放在一起比较，发现了新的线索。',
      ),
      PraiseSuggestion(
        behavior: ExplorationBehavior.replayedAudio,
        ability: '继续探索',
        text: '你没有急着下结论，而是为下一次倾听留下了问题。',
      ),
    ],
    provider: 'qwen3.7-flash',
    aiGenerated: true,
  );
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
  final _command = FamilyCommand(
    commandId: 'cmd-parent-1',
    templateId: 'listen_again_before_guessing',
    sequence: 1,
    createdAt: DateTime.utc(2026, 8, 26, 12),
  );

  @override
  FamilySessionConnection get connection => _connection;

  @override
  List<FamilyExplorationEvent> get events => [_event];

  @override
  List<FamilyCommand> get commands => [_command];

  @override
  bool missionReceived(String commandId) => commandId == _command.commandId;

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

class _UnlinkedCoordinator extends FamilySessionCoordinator {
  String? joinedCode;

  @override
  Future<void> joinAsChild(String pairCode) async {
    joinedCode = pairCode;
  }
}
