import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/family/family_session_models.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';
import 'package:nature_sound_detective/core/network/parent_guidance_service.dart';
import 'package:nature_sound_detective/features/parent/parent_companion_sheet.dart';

void main() {
  testWidgets('opening local guidance does not consume AI generation', (
    tester,
  ) async {
    final service = _FakeGuidanceService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ParentCompanionSheet(
            detection: null,
            observations: const {},
            behaviors: const {ExplorationBehavior.replayedAudio},
            weakSignal: false,
            service: service,
            quota: const ParentGuidanceQuota(limit: 20, used: 1, remaining: 19),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(service.calls, 0);
    expect(find.textContaining('本地审核模板'), findsOneWidget);
    expect(find.textContaining('剩余 19 / 20'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('generate-personalized-parent-guidance')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('将使用1次AI个性化生成'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('generate-personalized-parent-guidance')),
    );
    await tester.pumpAndSettle();

    expect(service.calls, 1);
    expect(find.text('AI根据本次探索直接生成'), findsOneWidget);
  });

  testWidgets('exhausted AI quota keeps local guidance available', (
    tester,
  ) async {
    final service = _FakeGuidanceService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ParentCompanionSheet(
            detection: null,
            observations: const {},
            behaviors: const {ExplorationBehavior.acceptedUncertainty},
            weakSignal: false,
            service: service,
            quota: const ParentGuidanceQuota(limit: 20, used: 20, remaining: 0),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('generate-personalized-parent-guidance')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('本地陪伴建议仍然可以正常使用'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('generate-personalized-parent-guidance')),
    );
    expect(button.onPressed, isNull);
    expect(service.calls, 0);
  });
}

class _FakeGuidanceService extends ParentGuidanceNetworkService {
  int calls = 0;

  @override
  Future<GuidanceBundle> create({
    required dynamic detection,
    required Map<String, List<String>> observations,
    required Set<ExplorationBehavior> behaviors,
    required bool weakSignal,
    List<FamilyExplorationEvent> events = const [],
  }) async {
    calls++;
    return const GuidanceBundle(
      guides: [
        ParentGuide(goal: '先描述', say: '你听到了什么？', action: '一起回听', avoid: '不说答案'),
        ParentGuide(goal: '找证据', say: '什么支持猜想？', action: '观察环境', avoid: '不追逐'),
      ],
      praiseSuggestions: [
        PraiseSuggestion(
          behavior: ExplorationBehavior.replayedAudio,
          ability: '认真求证',
          text: '你又认真听了一次。',
        ),
        PraiseSuggestion(
          behavior: ExplorationBehavior.comparedEvidence,
          ability: '比较证据',
          text: '你比较了不同线索。',
        ),
        PraiseSuggestion(
          behavior: ExplorationBehavior.acceptedUncertainty,
          ability: '诚实判断',
          text: '你愿意保留不知道。',
        ),
      ],
      provider: 'test-ai',
      aiGenerated: true,
    );
  }
}
