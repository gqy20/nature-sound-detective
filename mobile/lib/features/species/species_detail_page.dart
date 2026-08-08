import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/models/detection.dart';

class SpeciesDetailPage extends StatefulWidget {
  const SpeciesDetailPage({super.key, required this.detection, this.rank});

  final SoundDetection detection;
  final int? rank;

  @override
  State<SpeciesDetailPage> createState() => _SpeciesDetailPageState();
}

class _SpeciesDetailPageState extends State<SpeciesDetailPage> {
  final Set<_FieldCheck> _checkedItems = <_FieldCheck>{};

  @override
  Widget build(BuildContext context) {
    final detection = widget.detection;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _FieldCheck.values
                      .map(
                        (item) => _CheckChip(
                          icon: item.icon,
                          label: item.label,
                          selected: _checkedItems.contains(item),
                          onTap: () => _toggleCheck(item),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    _checkHint,
                    key: ValueKey(_checkedItems.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _checkedItems.length == _FieldCheck.values.length
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
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

  void _toggleCheck(_FieldCheck item) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_checkedItems.add(item)) {
        _checkedItems.remove(item);
      }
    });
  }

  String get _checkHint => switch (_checkedItems.length) {
    0 => '看到相符的线索，就点一下',
    3 => '全都对上啦！',
    final count => '已核对 $count 项',
  };

  String _evidenceText() {
    final detection = widget.detection;
    if (detection.intervals.isEmpty) {
      return '整段录音';
    }
    final interval = detection.intervals.first;
    return '${interval.startSeconds.toStringAsFixed(1)}–${interval.endSeconds.toStringAsFixed(1)} 秒';
  }

  String get name =>
      widget.detection.specificSpecies?.nameZh ?? widget.detection.nameZh;

  IconData _categoryIcon(String category) => switch (category) {
    'bird' => Icons.flight_rounded,
    'frog' => Icons.water_rounded,
    'insect' => Icons.bug_report_outlined,
    _ => Icons.eco_outlined,
  };
}

enum _FieldCheck {
  time(Icons.schedule_outlined, '时间'),
  location(Icons.location_on_outlined, '位置'),
  appearance(Icons.visibility_outlined, '外形');

  const _FieldCheck(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _CheckChip extends StatelessWidget {
  const _CheckChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label核对',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? colors.primary : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    selected ? Icons.check_rounded : icon,
                    key: ValueKey(selected),
                    size: 19,
                    color: selected ? colors.primary : null,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? colors.primary : null,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
