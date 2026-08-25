import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';
import 'package:nature_sound_detective/core/guidance/parent_guidance_engine.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

class ParentCompanionSheet extends StatelessWidget {
  const ParentCompanionSheet({
    super.key,
    required this.detection,
    required this.observations,
    required this.behaviors,
  });

  final SoundDetection? detection;
  final Map<String, List<String>> observations;
  final Set<ExplorationBehavior> behaviors;

  @override
  Widget build(BuildContext context) {
    final bundle = const ParentGuidanceEngine().build(
      detection: detection,
      observations: observations,
      behaviors: behaviors,
    );
    final candidate = detection;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .88,
      minChildSize: .55,
      maxChildSize: .96,
      builder: (context, controller) => SafeArea(
        top: false,
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
          children: [
            Text('家长陪伴', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            const Text('专业信息帮助你提问和守住边界，不是让家长替孩子判断。'),
            if (candidate != null) ...[
              const SizedBox(height: 18),
              _EvidenceCard(detection: candidate),
            ],
            const SizedBox(height: 22),
            Text('可以这样引导', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            for (final (index, guide) in bundle.guides.indexed)
              _GuideCard(index: index + 1, guide: guide),
            const SizedBox(height: 18),
            Text('可以这样回应孩子', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('下面的话只根据本次已经发生的探索行为提供。'),
            const SizedBox(height: 10),
            for (final praise in bundle.praiseSuggestions)
              _PraiseCard(suggestion: praise),
          ],
        ),
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.detection});
  final SoundDetection detection;

  @override
  Widget build(BuildContext context) {
    final name = detection.specificSpecies?.nameZh ?? detection.nameZh;
    final strength = detection.confidence >= .65
        ? '线索较强'
        : detection.confidence >= .35
        ? '线索中等'
        : '仍待确认';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F0E9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('本次候选依据', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('$name · $strength'),
          Text('模型：${detection.evidenceModels.join('、')}'),
          if (detection.intervals.isNotEmpty)
            Text(
              '关键声段：${detection.intervals.first.startSeconds.toStringAsFixed(1)}–${detection.intervals.first.endSeconds.toStringAsFixed(1)} 秒',
            ),
          const SizedBox(height: 8),
          const Text(
            '这是机器候选，不是物种确认。请把声音、环境和孩子的观察分开看待。',
            style: TextStyle(fontSize: 12, color: Color(0xFF52615A)),
          ),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.index, required this.guide});
  final int index;
  final ParentGuide guide;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$index. ${guide.goal}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text('可以说：“${guide.say}”'),
          const SizedBox(height: 6),
          Text('一起做：${guide.action}'),
          const SizedBox(height: 6),
          Text(
            '避免：${guide.avoid}',
            style: const TextStyle(color: Color(0xFF8A4D3A), fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class _PraiseCard extends StatelessWidget {
  const _PraiseCard({required this.suggestion});
  final PraiseSuggestion suggestion;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF2CE),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.favorite_outline_rounded, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                suggestion.ability,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(suggestion.text),
            ],
          ),
        ),
      ],
    ),
  );
}
