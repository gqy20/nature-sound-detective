import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/audio/audio_playback.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/models/field_observation_schema.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode.dart';
import 'package:nature_sound_detective/core/network/animal_story_service.dart';
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
    this.initialObservations = const {},
    this.onObservationsChanged,
    this.mode = ExplorationMode.child,
  });

  final SoundDetection detection;
  final int? rank;
  final String? audioPath;
  final AudioPlayback? playback;
  final List<String> initialChecks;
  final ValueChanged<List<String>>? onChecksChanged;
  final Map<String, List<String>> initialObservations;
  final ValueChanged<Map<String, List<String>>>? onObservationsChanged;
  final ExplorationMode mode;

  @override
  State<SpeciesDetailPage> createState() => _SpeciesDetailPageState();
}

class _SpeciesDetailPageState extends State<SpeciesDetailPage> {
  final Map<String, Set<String>> _selectedObservations = {};
  late final Future<FieldObservationSchema> _schemaFuture;
  late final AudioPlayback _playback;
  late final bool _ownsPlayback;
  StreamSubscription<bool>? _playingSubscription;
  bool _playing = false;
  int _segmentIndex = 0;
  bool _storyLoading = false;
  AnimalStory? _story;

  @override
  void initState() {
    super.initState();
    _schemaFuture = FieldObservationSchema.load();
    for (final entry in widget.initialObservations.entries) {
      _selectedObservations[entry.key] = entry.value.toSet();
    }
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
      appBar: AppBar(title: const Text('科普卡')),
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
          if (media != null &&
              (media.habitatDescription != null ||
                  media.voiceDescription != null))
            _Section(
              icon: Icons.eco_outlined,
              title: '认识它',
              child: Column(
                children: [
                  if (media.habitatDescription case final habitat?)
                    _FactLine(icon: Icons.park_outlined, text: habitat),
                  if (media.voiceDescription case final voice?)
                    _FactLine(icon: Icons.hearing_rounded, text: voice),
                ],
              ),
            ),
          _Section(
            icon: Icons.visibility_outlined,
            title: '现场核对',
            child: FutureBuilder<FieldObservationSchema>(
              future: _schemaFuture,
              builder: (context, snapshot) {
                final schema = snapshot.data;
                if (schema == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _StructuredObservationForm(
                  schema: schema,
                  mode: widget.mode,
                  selections: _selectedObservations,
                  hasLegacyChecks:
                      widget.initialChecks.isNotEmpty &&
                      widget.initialObservations.isEmpty,
                  onToggle: _toggleObservation,
                  onComplete: () => _completeObservations(schema),
                  onStory: () => _generateStory(schema),
                  storyLoading: _storyLoading,
                );
              },
            ),
          ),
          if (_story case final story?)
            _Section(
              icon: Icons.auto_stories_rounded,
              title: '听它的故事',
              child: _AnimalStoryCard(story: story),
            ),
          if (media?.observationTip case final tip?) _ObservationTip(text: tip),
        ],
      ),
    );
  }

  bool get _hasAudio => widget.audioPath?.trim().isNotEmpty ?? false;

  void _toggleObservation(FieldObservationDimension dimension, String value) {
    HapticFeedback.selectionClick();
    setState(() {
      final selected = {...?_selectedObservations[dimension.id]};
      if (!dimension.multiple || value == 'unknown') {
        if (selected.contains(value)) {
          selected.clear();
        } else {
          selected
            ..clear()
            ..add(value);
        }
      } else {
        selected.remove('unknown');
        if (!selected.add(value)) selected.remove(value);
      }
      if (selected.isEmpty) {
        _selectedObservations.remove(dimension.id);
      } else {
        _selectedObservations[dimension.id] = selected;
      }
    });
  }

  void _completeObservations(FieldObservationSchema schema) {
    final values = _selectedObservations.map(
      (key, value) => MapEntry(key, value.toList(growable: false)),
    );
    if (!schema.isComplete(values)) return;
    widget.onObservationsChanged?.call(values);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('现场观察已完成，可以生成动物故事了')));
  }

  Future<void> _generateStory(FieldObservationSchema schema) async {
    final values = _selectedObservations.map(
      (key, value) => MapEntry(key, value.toList(growable: false)),
    );
    if (!schema.isComplete(values) || _storyLoading) return;
    widget.onObservationsChanged?.call(values);
    setState(() => _storyLoading = true);
    try {
      final story = await AnimalStoryService().create(
        detection: widget.detection,
        selections: values,
        schema: schema,
      );
      if (mounted) setState(() => _story = story);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('动物故事暂时没有生成，请稍后再试')));
      }
    } finally {
      if (mounted) setState(() => _storyLoading = false);
    }
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

class _StructuredObservationForm extends StatelessWidget {
  const _StructuredObservationForm({
    required this.schema,
    required this.mode,
    required this.selections,
    required this.hasLegacyChecks,
    required this.onToggle,
    required this.onComplete,
    required this.onStory,
    required this.storyLoading,
  });

  final FieldObservationSchema schema;
  final ExplorationMode mode;
  final Map<String, Set<String>> selections;
  final bool hasLegacyChecks;
  final void Function(FieldObservationDimension, String) onToggle;
  final VoidCallback onComplete;
  final VoidCallback onStory;
  final bool storyLoading;

  @override
  Widget build(BuildContext context) {
    final values = selections.map(
      (key, value) => MapEntry(key, value.toList(growable: false)),
    );
    final complete = schema.isComplete(values);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasLegacyChecks) ...[
          Text(
            '这条记录使用旧版核对。为了生成动物故事，请重新选择具体观察内容。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
        ],
        for (final dimension in schema.dimensions.where(
          (item) =>
              mode == ExplorationMode.parent ||
              const {'time', 'habitat', 'sound_pattern'}.contains(item.id),
        )) ...[
          Text(dimension.label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in dimension.options)
                FilterChip(
                  label: Text(option.label),
                  selected:
                      selections[dimension.id]?.contains(option.value) ?? false,
                  onSelected: (_) => onToggle(dimension, option.value),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Text(
          complete ? '✓ 已满足故事生成条件' : '至少完成两个方面的现场观察',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: complete ? Theme.of(context).colorScheme.primary : null,
            fontWeight: complete ? FontWeight.w600 : null,
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: complete ? onComplete : null,
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: const Text('完成现场观察'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: complete && !storyLoading ? onStory : null,
          icon: storyLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_stories_rounded),
          label: Text(storyLoading ? '正在准备故事' : '听它的故事'),
        ),
      ],
    );
  }
}

class _AnimalStoryCard extends StatelessWidget {
  const _AnimalStoryCard({required this.story});
  final AnimalStory story;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFEDF4EE),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(story.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Text(story.story),
        const SizedBox(height: 14),
        Text('下次可以观察', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(story.observationPrompt),
        const SizedBox(height: 10),
        Text(story.notice, style: Theme.of(context).textTheme.bodySmall),
      ],
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

class _FactLine extends StatelessWidget {
  const _FactLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _ObservationTip extends StatelessWidget {
  const _ObservationTip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF1EEDB),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.lightbulb_outline_rounded, size: 19),
        const SizedBox(width: 9),
        Expanded(child: Text(text)),
      ],
    ),
  );
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
