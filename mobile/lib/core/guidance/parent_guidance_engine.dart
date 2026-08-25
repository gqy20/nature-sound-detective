import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

class ParentGuidanceEngine {
  const ParentGuidanceEngine();

  GuidanceBundle build({
    required SoundDetection? detection,
    required Map<String, List<String>> observations,
    required Set<ExplorationBehavior> behaviors,
  }) {
    final guides = <ParentGuide>[
      const ParentGuide(
        goal: '让孩子先描述声音',
        say: '先不看候选，你觉得它是连续的，还是叫几声会停下来？',
        action: '一起回听关键声段，请孩子用手轻轻打出节奏。',
        avoid: '不要先说物种名称，也不要提示“正确答案”。',
      ),
    ];
    final habitatKnown = _hasMeaningful(observations['habitat']);
    if (!habitatKnown) {
      guides.add(
        const ParentGuide(
          goal: '寻找环境证据',
          say: '你看高处，我看低处，等一会儿我们交换各自发现。',
          action: '站在公开步道上观察树冠、灌木、水边和地面。',
          avoid: '不要追逐声源、拨开灌木或靠近巢穴和水边。',
        ),
      );
    } else {
      guides.add(
        const ParentGuide(
          goal: '比较不同证据',
          say: '刚才看到的环境，哪一点支持你的猜想？哪一点还对不上？',
          action: '把环境观察和声音节奏各说一条，再查看候选。',
          avoid: '不要因为看见一种动物，就认定声音一定由它发出。',
        ),
      );
    }
    guides.add(
      ParentGuide(
        goal: '保留合理的不确定',
        say: detection == null
            ? '这次没有清楚答案，我们已经知道下次要怎样录得更好了。'
            : '你现在是比较确定、有一个猜想，还是还需要更多证据？',
        action: '允许孩子选择“暂时不知道”，并说出下一次想验证什么。',
        avoid: '不要要求孩子必须从候选中选出一个。',
      ),
    );

    final praise = <PraiseSuggestion>[];
    for (final behavior in behaviors) {
      final suggestion = _praise[behavior];
      if (suggestion != null) praise.add(suggestion);
    }
    if (praise.isEmpty) {
      praise.add(
        const PraiseSuggestion(
          behavior: ExplorationBehavior.observedSafely,
          ability: '主动发现',
          text: '刚才这个声音是你先注意到的，谢谢你邀请我一起听。',
        ),
      );
    }
    return GuidanceBundle(
      guides: guides.take(3).toList(growable: false),
      praiseSuggestions: praise.take(5).toList(growable: false),
    );
  }

  static bool _hasMeaningful(List<String>? values) =>
      values != null && values.any((value) => value != 'unknown');

  static const _praise = <ExplorationBehavior, PraiseSuggestion>{
    ExplorationBehavior.replayedAudio: PraiseSuggestion(
      behavior: ExplorationBehavior.replayedAudio,
      ability: '认真求证',
      text: '你没有急着选答案，而是重新听了一遍，这是一种很认真的调查方法。',
    ),
    ExplorationBehavior.completedObservation: PraiseSuggestion(
      behavior: ExplorationBehavior.completedObservation,
      ability: '现场观察',
      text: '你不只看了候选，还回到现场寻找线索，观察得很完整。',
    ),
    ExplorationBehavior.comparedEvidence: PraiseSuggestion(
      behavior: ExplorationBehavior.comparedEvidence,
      ability: '比较证据',
      text: '你能把声音和周围环境放在一起比较，已经在用证据作判断了。',
    ),
    ExplorationBehavior.acceptedUncertainty: PraiseSuggestion(
      behavior: ExplorationBehavior.acceptedUncertainty,
      ability: '诚实判断',
      text: '你愿意说暂时不知道，说明你很认真地对待证据。',
    ),
    ExplorationBehavior.retriedRecording: PraiseSuggestion(
      behavior: ExplorationBehavior.retriedRecording,
      ability: '从失败中调整',
      text: '这次没有录清楚，但你愿意换个方法再试，调查正在进步。',
    ),
    ExplorationBehavior.observedSafely: PraiseSuggestion(
      behavior: ExplorationBehavior.observedSafely,
      ability: '尊重自然',
      text: '你留在步道上安静观察，没有追过去，这是尊重自然的方式。',
    ),
  };
}
