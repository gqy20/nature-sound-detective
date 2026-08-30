import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/audio/audio_playback.dart';
import 'package:nature_sound_detective/core/models/animal_story.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/models/field_observation_schema.dart';
import 'package:nature_sound_detective/core/mode/exploration_mode.dart';
import 'package:nature_sound_detective/core/network/animal_story_service.dart';
import 'package:nature_sound_detective/core/models/species_media.dart';
import 'package:nature_sound_detective/core/storage/animal_story_store.dart';

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
    this.storyGenerator,
    this.storyStore,
    this.observationSchema,
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
  final AnimalStoryGenerator? storyGenerator;
  final AnimalStoryStore? storyStore;
  final FieldObservationSchema? observationSchema;

  @override
  State<SpeciesDetailPage> createState() => _SpeciesDetailPageState();
}

class _SpeciesDetailPageState extends State<SpeciesDetailPage> {
  final Map<String, Set<String>> _selectedObservations = {};
  late final Future<FieldObservationSchema> _schemaFuture;
  late final AudioPlayback _playback;
  late final bool _ownsPlayback;
  late final AnimalStoryGenerator _storyGenerator;
  late final AnimalStoryStore _storyStore;
  StreamSubscription<bool>? _playingSubscription;
  bool _playing = false;
  int _segmentIndex = 0;
  bool _storyLoading = false;
  AnimalStory? _story;
  String? _storyError;
  bool _storySaved = false;

  @override
  void initState() {
    super.initState();
    _schemaFuture = widget.observationSchema == null
        ? FieldObservationSchema.load()
        : Future.value(widget.observationSchema);
    for (final entry in widget.initialObservations.entries) {
      _selectedObservations[entry.key] = entry.value.toSet();
    }
    _ownsPlayback = widget.playback == null;
    _playback = widget.playback ?? DeviceFileAudioPlayback();
    _storyGenerator = widget.storyGenerator ?? AnimalStoryService();
    _storyStore = widget.storyStore ?? FileAnimalStoryStore();
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
    unawaited(_restoreStory());
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
                  onStory: () => _generateStory(schema),
                  storyLoading: _storyLoading,
                  storyError: _storyError,
                );
              },
            ),
          ),
          if (_storyLoading && _story == null)
            const _Section(
              icon: Icons.auto_stories_rounded,
              title: '正在准备故事',
              child: _StoryLoadingCard(),
            ),
          if (_story case final story?)
            _Section(
              icon: Icons.auto_stories_rounded,
              title: '动物故事',
              child: _AnimalStoryCard(
                story: story,
                saved: _storySaved,
                regenerating: _storyLoading,
                onRegenerate: _generateStoryFromCurrentSelections,
              ),
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
      _story = null;
      _storyError = null;
      _storySaved = false;
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
    final values = _selectedObservations.map(
      (key, value) => MapEntry(key, value.toList(growable: false)),
    );
    widget.onObservationsChanged?.call(values);
  }

  Future<void> _generateStory(FieldObservationSchema schema) async {
    final values = _selectedObservations.map(
      (key, value) => MapEntry(key, value.toList(growable: false)),
    );
    if (!schema.isComplete(values) || _storyLoading) return;
    widget.onObservationsChanged?.call(values);
    await _generateStoryWith(schema, values);
  }

  Future<void> _generateStoryFromCurrentSelections() async {
    final schema = await _schemaFuture;
    final values = _selectedObservations.map(
      (key, value) => MapEntry(key, value.toList(growable: false)),
    );
    if (!schema.isComplete(values) || _storyLoading) return;
    await _generateStoryWith(schema, values);
  }

  Future<void> _generateStoryWith(
    FieldObservationSchema schema,
    Map<String, List<String>> values,
  ) async {
    setState(() {
      _storyLoading = true;
      _storyError = null;
    });
    try {
      final story = await _storyGenerator.create(
        detection: widget.detection,
        selections: values,
        schema: schema,
      );
      var saved = false;
      try {
        await _storyStore.save(
          FileAnimalStoryStore.keyFor(widget.detection, values),
          story,
        );
        saved = true;
      } catch (_) {
        // The story remains readable when local storage is unavailable.
      }
      if (mounted) {
        setState(() {
          _story = story;
          _storySaved = saved;
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _storyError = '连接等待时间较长，请检查网络后重试。');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _storyError = '故事还没有准备好，可以稍后再试。');
      }
    } finally {
      if (mounted) setState(() => _storyLoading = false);
    }
  }

  Future<void> _restoreStory() async {
    if (widget.initialObservations.isEmpty) return;
    final key = FileAnimalStoryStore.keyFor(
      widget.detection,
      widget.initialObservations,
    );
    try {
      final story = await _storyStore.load(key);
      final currentValues = _selectedObservations.map(
        (dimension, values) =>
            MapEntry(dimension, values.toList(growable: false)),
      );
      final selectionIsUnchanged =
          FileAnimalStoryStore.keyFor(widget.detection, currentValues) == key;
      if (mounted && story != null && _story == null && selectionIsUnchanged) {
        setState(() {
          _story = story;
          _storySaved = true;
        });
      }
    } catch (_) {
      // A missing or damaged cache behaves like an empty story state.
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
    required this.onStory,
    required this.storyLoading,
    required this.storyError,
  });

  final FieldObservationSchema schema;
  final ExplorationMode mode;
  final Map<String, Set<String>> selections;
  final bool hasLegacyChecks;
  final void Function(FieldObservationDimension, String) onToggle;
  final VoidCallback onStory;
  final bool storyLoading;
  final String? storyError;

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
                  showCheckmark: false,
                  selectedColor: const Color(0xFFDCEDE1),
                  backgroundColor: Colors.transparent,
                  side: BorderSide(
                    color:
                        selections[dimension.id]?.contains(option.value) ??
                            false
                        ? const Color(0xFF9CC7AA)
                        : const Color(0xFFD8D7CE),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 5,
                  ),
                  labelStyle: TextStyle(
                    color:
                        selections[dimension.id]?.contains(option.value) ??
                            false
                        ? const Color(0xFF234C3B)
                        : const Color(0xFF5F6B65),
                    fontWeight:
                        selections[dimension.id]?.contains(option.value) ??
                            false
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                  onSelected: (_) => onToggle(dimension, option.value),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
          decoration: BoxDecoration(
            color: complete ? const Color(0xFFE9F2EB) : const Color(0xFFF1EFE7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: complete
                      ? const Color(0xFF2F7657)
                      : const Color(0xFFAAA99F),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      complete ? '观察线索已保存' : '继续补充观察线索',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: complete
                            ? const Color(0xFF245440)
                            : const Color(0xFF65655D),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      complete ? '现在可以根据这些线索生成故事' : '至少完成两个方面',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF737870),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: complete && !storyLoading ? onStory : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: storyLoading
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text('正在准备故事'),
                    ],
                  )
                : const Text('生成动物故事'),
          ),
        ),
        if (storyError case final message?) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF2DF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Color(0xFF8A5A12),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF69440D),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AnimalStoryCard extends StatelessWidget {
  const _AnimalStoryCard({
    required this.story,
    required this.saved,
    required this.regenerating,
    required this.onRegenerate,
  });

  final AnimalStory story;
  final bool saved;
  final bool regenerating;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '动物故事：${story.title}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: const Color(0xFFEDF4EE),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFD9E6DC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFFD9E9DE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    size: 18,
                    color: Color(0xFF174936),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    story.usedSafetyTemplate ? '安全模板故事' : '候选动物 · AI故事',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF486157),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              story.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 22,
                height: 1.35,
                letterSpacing: -0.25,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              story.story,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF34473E),
                height: 1.75,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFDF7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE1E4D7)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.explore_outlined,
                      size: 21,
                      color: Color(0xFF174936),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '下一次探索任务',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF174936),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          story.observationPrompt,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF526159),
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (story.warning.isNotEmpty) ...[
              const SizedBox(height: 12),
              _StoryStatusLine(
                icon: Icons.shield_outlined,
                text: '模型内容未通过校验，已换用安全版本。',
                color: const Color(0xFF7C5515),
              ),
            ],
            const SizedBox(height: 14),
            _StoryStatusLine(
              icon: Icons.info_outline_rounded,
              text: story.notice,
              color: const Color(0xFF66716B),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  saved
                      ? Icons.bookmark_added_outlined
                      : Icons.bookmark_border_rounded,
                  size: 17,
                  color: const Color(0xFF66716B),
                ),
                const SizedBox(width: 6),
                Text(
                  saved ? '已保存到本机' : '本次暂未保存',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF66716B),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: regenerating ? null : onRegenerate,
                  icon: regenerating
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(regenerating ? '正在重写' : '换一个故事'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryStatusLine extends StatelessWidget {
  const _StoryStatusLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(icon, size: 16, color: color),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: color, height: 1.45),
        ),
      ),
    ],
  );
}

class _StoryLoadingCard extends StatelessWidget {
  const _StoryLoadingCard();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: '正在根据现场观察生成动物故事',
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF4EE),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD9E6DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '正在把你的观察串成故事',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF234437),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '会保留现场线索，也会避免把候选动物写成已确认物种。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            child: LinearProgressIndicator(minHeight: 5),
          ),
          const SizedBox(height: 8),
          Text('通常需要约 10 秒', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
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
