import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/audio/audio_playback.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/models/species_media.dart';

class SpeciesDetailPage extends StatefulWidget {
  const SpeciesDetailPage({
    super.key,
    required this.detection,
    this.rank,
    this.audioPath,
    this.playback,
    this.initialChecks = const [],
    this.onChecksChanged,
  });

  final SoundDetection detection;
  final int? rank;
  final String? audioPath;
  final AudioPlayback? playback;
  final List<String> initialChecks;
  final ValueChanged<List<String>>? onChecksChanged;

  @override
  State<SpeciesDetailPage> createState() => _SpeciesDetailPageState();
}

class _SpeciesDetailPageState extends State<SpeciesDetailPage> {
  final Set<_FieldCheck> _checkedItems = <_FieldCheck>{};
  late final AudioPlayback _playback;
  late final bool _ownsPlayback;
  StreamSubscription<bool>? _playingSubscription;
  bool _playing = false;
  int _segmentIndex = 0;

  @override
  void initState() {
    super.initState();
    _checkedItems.addAll(
      _FieldCheck.values.where(
        (item) => widget.initialChecks.contains(item.name),
      ),
    );
    _ownsPlayback = widget.playback == null;
    _playback = widget.playback ?? DeviceFileAudioPlayback();
    _playingSubscription = _playback.playing.listen((playing) {
      if (!mounted) return;
      final finishedSegment = _playing && !playing;
      setState(() {
        _playing = playing;
        if (finishedSegment && widget.detection.intervals.length > 1) {
          _segmentIndex =
              (_segmentIndex + 1) % widget.detection.intervals.length;
        }
      });
    });
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    unawaited(_releasePlayback());
    super.dispose();
  }

  Future<void> _releasePlayback() async {
    await _playback.stop();
    if (_ownsPlayback) await _playback.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detection = widget.detection;
    final species = detection.specificSpecies;
    final name = species?.nameZh ?? detection.nameZh;
    final scientificName = species?.scientificName;
    final media = SpeciesMediaCatalog.lookup(scientificName);
    return Scaffold(
      appBar: AppBar(title: const Text('物种线索')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _SpeciesHero(
            categoryIcon: _categoryIcon(detection.categoryId),
            name: name,
            scientificName: scientificName,
            confidence: detection.confidence,
            tentative: detection.tentative,
            media: media,
            onSourceTap: media == null ? null : () => _showSourceInfo(media),
          ),
          const SizedBox(height: 20),
          _CompactInfoRow(
            icon: Icons.graphic_eq_rounded,
            title: '主要声段',
            value: _evidenceText(),
            onTap: _hasAudio ? _toggleSegment : null,
            playing: _playing,
          ),
          _Section(
            icon: Icons.visibility_outlined,
            title: '现场核对',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (
                      var index = 0;
                      index < _FieldCheck.values.length;
                      index++
                    ) ...[
                      if (index > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _CheckChip(
                          icon: _FieldCheck.values[index].icon,
                          label: _checkLabel(_FieldCheck.values[index], media),
                          selected: _checkedItems.contains(
                            _FieldCheck.values[index],
                          ),
                          onTap: () => _toggleCheck(_FieldCheck.values[index]),
                        ),
                      ),
                    ],
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: _checkedItems.length == _FieldCheck.values.length
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '✓ 全部对上',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasAudio => widget.audioPath?.trim().isNotEmpty ?? false;

  void _toggleCheck(_FieldCheck item) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_checkedItems.add(item)) _checkedItems.remove(item);
    });
    widget.onChecksChanged?.call(
      _FieldCheck.values
          .where(_checkedItems.contains)
          .map((item) => item.name)
          .toList(growable: false),
    );
  }

  Future<void> _toggleSegment() async {
    if (_playing) {
      await _playback.stop();
      return;
    }
    final path = widget.audioPath;
    if (path == null || path.isEmpty) return;
    HapticFeedback.selectionClick();
    final intervals = widget.detection.intervals;
    if (intervals.isEmpty) {
      await _playback.play(path);
      return;
    }
    final interval = intervals[_segmentIndex.clamp(0, intervals.length - 1)];
    await _playback.playSegment(
      path,
      start: Duration(milliseconds: (interval.startSeconds * 1000).round()),
      end: Duration(milliseconds: (interval.endSeconds * 1000).round()),
    );
  }

  String _checkLabel(_FieldCheck item, SpeciesMedia? media) => switch (item) {
    _FieldCheck.time => media?.timeHint ?? item.label,
    _FieldCheck.location => media?.locationHint ?? item.label,
    _FieldCheck.appearance => media?.appearanceHint ?? item.label,
  };

  String _evidenceText() {
    final intervals = widget.detection.intervals;
    if (intervals.isEmpty) return '整段录音';
    final interval = intervals[_segmentIndex.clamp(0, intervals.length - 1)];
    if (intervals.length == 1) {
      return '${interval.startSeconds.toStringAsFixed(1)}–${interval.endSeconds.toStringAsFixed(1)}s';
    }
    return '${_segmentIndex + 1}/${intervals.length} · '
        '${_shortSeconds(interval.startSeconds)}–${_shortSeconds(interval.endSeconds)}s';
  }

  String _shortSeconds(double value) {
    final rounded = value.round();
    return (value - rounded).abs() < 0.05
        ? rounded.toString()
        : value.toStringAsFixed(1);
  }

  Future<void> _showSourceInfo(SpeciesMedia media) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('照片来源', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _SourceLine(label: '作者', value: media.author),
              _SourceLine(label: '来源', value: media.sourceName),
              _SourceLine(label: '许可', value: media.license),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () {
                  unawaited(
                    Clipboard.setData(ClipboardData(text: media.sourceUrl)),
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(
                    this.context,
                  ).showSnackBar(const SnackBar(content: Text('来源链接已复制')));
                },
                icon: const Icon(Icons.link_rounded),
                label: const Text('复制来源链接'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) => switch (category) {
    'bird' => Icons.flight_rounded,
    'frog' => Icons.water_rounded,
    'insect' => Icons.bug_report_outlined,
    _ => Icons.eco_outlined,
  };
}

class _SpeciesHero extends StatelessWidget {
  const _SpeciesHero({
    required this.categoryIcon,
    required this.name,
    required this.scientificName,
    required this.confidence,
    required this.tentative,
    required this.media,
    required this.onSourceTap,
  });

  final IconData categoryIcon;
  final String name;
  final String? scientificName;
  final double confidence;
  final bool tentative;
  final SpeciesMedia? media;
  final VoidCallback? onSourceTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: ColoredBox(
        color: const Color(0xFFE4EEE7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (media case final media?)
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      media.assetPath,
                      fit: BoxFit.cover,
                      semanticLabel: '$name的参考照片',
                      errorBuilder: (context, error, stackTrace) =>
                          _ImageFallback(icon: categoryIcon),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Semantics(
                        button: true,
                        label: '查看图片来源：${media.credit}',
                        child: Material(
                          color: const Color(0xCC14251D),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: onSourceTap,
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                child: Text(
                                  '© ${media.author} · ${media.license}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 132,
                width: double.infinity,
                child: _ImageFallback(icon: categoryIcon),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stack =
                          constraints.maxWidth < 300 || name.runes.length > 7;
                      final nameText = Text(
                        name,
                        style: theme.textTheme.headlineMedium,
                      );
                      final confidenceText = Text(
                        _confidenceText,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                      if (stack) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            nameText,
                            const SizedBox(height: 6),
                            confidenceText,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(child: nameText),
                          const SizedBox(width: 12),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: confidenceText,
                          ),
                        ],
                      );
                    },
                  ),
                  if (scientificName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      scientificName!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _confidenceText {
    final percent = (confidence * 100).round();
    return tentative ? '声音像 $percent% · 再听听' : '声音像 $percent%';
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFDDEAE2), Color(0xFFEDF3EA)],
      ),
    ),
    child: Center(
      child: Icon(icon, size: 38, color: Theme.of(context).colorScheme.primary),
    ),
  );
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
              mainAxisAlignment: MainAxisAlignment.center,
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
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? colors.primary : null,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
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

class _CompactInfoRow extends StatelessWidget {
  const _CompactInfoRow({
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
    this.playing = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(
              playing
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline_rounded,
              size: 22,
            ),
          ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Semantics(
        button: onTap != null,
        label: onTap == null ? null : '${playing ? '停止' : '播放'}主要声段 $value',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: row,
          ),
        ),
      ),
    );
  }
}

class _SourceLine extends StatelessWidget {
  const _SourceLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
