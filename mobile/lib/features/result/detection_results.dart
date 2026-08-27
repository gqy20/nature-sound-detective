import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/models/exploration_feedback.dart';

class DetectionResults extends StatelessWidget {
  const DetectionResults({
    super.key,
    required this.detections,
    this.onFeedback,
    this.onDetectionTap,
  });

  final List<SoundDetection> detections;
  final ValueChanged<ExplorationFeedback>? onFeedback;
  final void Function(SoundDetection detection, int? rank)? onDetectionTap;

  @override
  Widget build(BuildContext context) {
    final rankedSpecies =
        detections.where((item) => item.specificSpecies != null).toList()
          ..sort((left, right) => right.confidence.compareTo(left.confidence));
    final ambientClues = detections
        .where((item) => item.specificSpecies == null)
        .toList(growable: false);
    int? speciesRank(SoundDetection detection) {
      final index = rankedSpecies.indexOf(detection);
      return index < 0 ? null : index + 1;
    }

    return Semantics(
      container: true,
      label: '本地声音识别结果',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final detection in rankedSpecies) ...[
            _DetectionCard(
              detection: detection,
              rank: speciesRank(detection),
              onTap: onDetectionTap == null
                  ? null
                  : () => onDetectionTap!(detection, speciesRank(detection)),
            ),
            const SizedBox(height: 10),
          ],
          if (ambientClues.isNotEmpty) _AmbientClues(detections: ambientClues),
          if (onFeedback != null) ...[
            const SizedBox(height: 8),
            _DetectionFeedbackPanel(
              detections: detections,
              onSubmitted: onFeedback!,
            ),
          ],
        ],
      ),
    );
  }
}

class _DetectionFeedbackPanel extends StatefulWidget {
  const _DetectionFeedbackPanel({
    required this.detections,
    required this.onSubmitted,
  });

  final List<SoundDetection> detections;
  final ValueChanged<ExplorationFeedback> onSubmitted;

  @override
  State<_DetectionFeedbackPanel> createState() =>
      _DetectionFeedbackPanelState();
}

class _DetectionFeedbackPanelState extends State<_DetectionFeedbackPanel> {
  FeedbackDecision? _decision;
  String? _correctedTaxonId;
  bool _consent = false;
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    if (_submitted) return const Text('反馈已保存在本机，等待人工复核。');
    final taxa = widget.detections
        .map((item) => item.specificSpecies)
        .whereType<SpeciesCandidate>()
        .where((item) => item.taxonomyId != null)
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('这个结果像吗？'),
            Wrap(
              spacing: 8,
              children: [
                for (final decision in FeedbackDecision.values)
                  ChoiceChip(
                    label: Text(switch (decision) {
                      FeedbackDecision.correct => '像',
                      FeedbackDecision.wrong => '不像',
                      FeedbackDecision.uncertain => '不确定',
                    }),
                    selected: _decision == decision,
                    onSelected: (_) => setState(() => _decision = decision),
                  ),
              ],
            ),
            if (_decision == FeedbackDecision.wrong && taxa.isNotEmpty)
              DropdownButtonFormField<String>(
                isExpanded: true,
                hint: const Text('选择更接近的物种'),
                initialValue: _correctedTaxonId,
                borderRadius: BorderRadius.circular(20),
                dropdownColor: const Color(0xFFFFFDF7),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFFFFCF5),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFFE2DDCF)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFFE2DDCF)),
                  ),
                ),
                items: [
                  for (final taxon in taxa)
                    DropdownMenuItem(
                      value: taxon.taxonomyId,
                      child: Text(taxon.nameZh),
                    ),
                ],
                onChanged: (value) => setState(() => _correctedTaxonId = value),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _consent,
              title: const Text('允许将录音加入人工复核包'),
              onChanged: (value) => setState(() => _consent = value ?? false),
            ),
            FilledButton(
              onPressed: _decision == null
                  ? null
                  : () {
                      widget.onSubmitted(
                        ExplorationFeedback(
                          decision: _decision!,
                          correctedTaxonId: _correctedTaxonId,
                          consentToRetainAudio: _consent,
                        ),
                      );
                      setState(() => _submitted = true);
                    },
              child: const Text('保存反馈'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetectionCard extends StatelessWidget {
  const _DetectionCard({required this.detection, this.rank, this.onTap});

  final SoundDetection detection;
  final int? rank;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final species = detection.specificSpecies;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (rank case final value?) ...[
                    _RankMarker(rank: value),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          species?.nameZh ?? detection.nameZh,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (species?.scientificName case final name?)
                          Text(
                            name,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                  _StrengthBadge(
                    confidence: detection.confidence,
                    tentative: detection.tentative,
                    showConfidence: true,
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded, size: 20),
                  ],
                ],
              ),
              if (detection.intervals.isNotEmpty) ...[
                const SizedBox(height: 10),
                _MetaChip(
                  icon: Icons.graphic_eq_rounded,
                  label: _intervalLabel(detection.intervals.first),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _intervalLabel(DetectionInterval interval) {
    final start = interval.startSeconds.toStringAsFixed(1);
    final end = interval.endSeconds.toStringAsFixed(1);
    return '$start–$end 秒';
  }
}

class _StrengthBadge extends StatelessWidget {
  const _StrengthBadge({
    required this.confidence,
    required this.tentative,
    required this.showConfidence,
  });

  final double confidence;
  final bool tentative;
  final bool showConfidence;

  @override
  Widget build(BuildContext context) {
    final label = tentative
        ? '较弱猜想'
        : switch (confidence) {
            >= 0.65 => '线索较强',
            >= 0.35 => '线索中等',
            _ => '线索较弱',
          };
    if (showConfidence) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${(confidence * 100).round()}%',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
            ),
          ),
          if (tentative)
            Text('较弱猜想', style: Theme.of(context).textTheme.labelSmall),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tentative) ...[
            const Icon(Icons.help_outline_rounded, size: 15),
            const SizedBox(width: 4),
          ],
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _AmbientClues extends StatelessWidget {
  const _AmbientClues({required this.detections});

  final List<SoundDetection> detections;

  @override
  Widget build(BuildContext context) {
    final labels = detections.map((item) => item.nameZh).toSet().join(' · ');
    return Semantics(
      label: '同时听到 $labels',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.waves_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '同时听到：$labels',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankMarker extends StatelessWidget {
  const _RankMarker({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '候选第 $rank 名',
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$rank',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
