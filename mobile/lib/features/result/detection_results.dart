import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

class DetectionResults extends StatelessWidget {
  const DetectionResults({super.key, required this.detections});

  final List<SoundDetection> detections;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '本地声音识别结果',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('这次听见了', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            '以下是声音线索，需要结合现场观察确认。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (final detection in detections) ...[
            _DetectionCard(detection: detection),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _DetectionCard extends StatelessWidget {
  const _DetectionCard({required this.detection});

  final SoundDetection detection;

  @override
  Widget build(BuildContext context) {
    final species = detection.specificSpecies;
    final source = detection.model.startsWith('birdnet') ? 'BirdNET' : 'YAMNet';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                _StrengthBadge(confidence: detection.confidence),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _MetaChip(icon: Icons.memory_rounded, label: source),
                if (detection.intervals.isNotEmpty)
                  _MetaChip(
                    icon: Icons.schedule_rounded,
                    label: _intervalLabel(detection.intervals.first),
                  ),
              ],
            ),
          ],
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
  const _StrengthBadge({required this.confidence});

  final double confidence;

  @override
  Widget build(BuildContext context) {
    final label = switch (confidence) {
      >= 0.65 => '线索较强',
      >= 0.35 => '线索中等',
      _ => '线索较弱',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
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
