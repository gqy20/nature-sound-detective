import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

class SpeciesDetailPage extends StatelessWidget {
  const SpeciesDetailPage({super.key, required this.detection, this.rank});

  final SoundDetection detection;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final species = detection.specificSpecies;
    final name = species?.nameZh ?? detection.nameZh;
    final scientificName = species?.scientificName;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('物种线索')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFFE4EEE7),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_categoryIcon(detection.categoryId), size: 26),
                const SizedBox(height: 22),
                Text(name, style: theme.textTheme.headlineMedium),
                if (scientificName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    scientificName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  '${(detection.confidence * 100).round()}%',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _Section(
            icon: Icons.graphic_eq_rounded,
            title: '主要声段',
            child: Text(_evidenceText()),
          ),
          _Section(
            icon: Icons.visibility_outlined,
            title: '现场核对',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: const [
                _CheckChip(icon: Icons.schedule_outlined, label: '时间'),
                _CheckChip(icon: Icons.location_on_outlined, label: '位置'),
                _CheckChip(icon: Icons.visibility_outlined, label: '外形'),
              ],
            ),
          ),
          Text(
            detection.tentative ? 'ⓘ 较弱猜想，建议靠近后再录一次' : 'ⓘ 结果仅供现场判断参考',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _evidenceText() {
    if (detection.intervals.isEmpty) {
      return '整段录音';
    }
    final interval = detection.intervals.first;
    return '${interval.startSeconds.toStringAsFixed(1)}–${interval.endSeconds.toStringAsFixed(1)} 秒';
  }

  String get name => detection.specificSpecies?.nameZh ?? detection.nameZh;

  IconData _categoryIcon(String category) => switch (category) {
    'bird' => Icons.flight_rounded,
    'frog' => Icons.water_rounded,
    'insect' => Icons.bug_report_outlined,
    _ => Icons.eco_outlined,
  };
}

class _CheckChip extends StatelessWidget {
  const _CheckChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 17), const SizedBox(width: 6), Text(label)],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 19),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 10),
        DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
          child: child,
        ),
      ],
    ),
  );
}
