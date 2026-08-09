import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/audio/audio_playback.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/storage/exploration_record.dart';
import 'package:nature_sound_detective/core/storage/exploration_store.dart';
import 'package:nature_sound_detective/features/creation/works_page.dart';
import 'package:nature_sound_detective/features/community/soundscape_page.dart';
import 'package:nature_sound_detective/features/species/species_detail_page.dart';

String _speciesKey(SoundDetection detection) {
  final scientificName = detection.specificSpecies?.scientificName?.trim();
  if (scientificName != null && scientificName.isNotEmpty) {
    return scientificName.toLowerCase();
  }
  return '${detection.categoryId}:${detection.specificSpecies?.nameZh ?? detection.nameZh}';
}

class NatureBookPage extends StatefulWidget {
  const NatureBookPage({super.key, this.store, this.playback});

  final ExplorationStore? store;
  final AudioPlayback? playback;

  @override
  State<NatureBookPage> createState() => _NatureBookPageState();
}

class _NatureBookPageState extends State<NatureBookPage> {
  late final ExplorationStore _store;
  late final AudioPlayback _playback;
  late final bool _ownsPlayback;
  StreamSubscription<bool>? _subscription;
  List<ExplorationRecord> _records = const [];
  bool _loading = true;
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? FileExplorationStore();
    _ownsPlayback = widget.playback == null;
    _playback = widget.playback ?? DeviceFileAudioPlayback();
    _subscription = _playback.playing.listen((playing) {
      if (mounted && !playing) {
        setState(() => _playingId = null);
      }
    });
    _load();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    if (_ownsPlayback) unawaited(_playback.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final records = await _store.list();
    if (mounted) {
      setState(() {
        _records = records;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(ExplorationRecord record) async {
    if (_playingId == record.id) {
      await _playback.stop();
      if (mounted) setState(() => _playingId = null);
    } else {
      await _playback.play(record.audioPath);
      if (mounted) setState(() => _playingId = record.id);
    }
  }

  Future<void> _delete(ExplorationRecord record) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条声音？'),
        content: const Text('录音和识别结果将从本机删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (agreed != true) return;
    if (_playingId == record.id) await _playback.stop();
    await _store.delete(record.id);
    await _load();
  }

  Future<void> _openSpecies(
    ExplorationRecord record,
    SoundDetection detection,
  ) async {
    if (_playingId != null) await _playback.stop();
    if (!mounted) return;
    final key = _speciesKey(detection);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpeciesDetailPage(
          detection: detection,
          audioPath: record.audioPath,
          playback: _playback,
          initialChecks: record.fieldChecks[key] ?? const [],
          onChecksChanged: (checks) {
            unawaited(_persistFieldChecks(record.id, key, checks));
          },
        ),
      ),
    );
  }

  Future<void> _persistFieldChecks(
    String recordId,
    String speciesKey,
    List<String> checks,
  ) async {
    try {
      await _store.setFieldChecks(recordId, speciesKey, checks);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('核对结果暂时没有保存')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('自然册'),
      actions: [
        IconButton(
          tooltip: '共听杭州',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SoundscapePage(explorationStore: _store),
            ),
          ),
          icon: const Icon(Icons.radar_rounded),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _WorksEntry(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const WorksPage()),
                  ),
                ),
                const SizedBox(height: 24),
                Text('声音记录', style: Theme.of(context).textTheme.headlineSmall),
                if (_records.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_records.length} 条',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 14),
                if (_records.isEmpty) const _EmptySounds(),
                for (final record in _records) ...[
                  _SoundRecordCard(
                    record: record,
                    playing: _playingId == record.id,
                    onPlay: () => _toggle(record),
                    onDelete: () => _delete(record),
                    onOpenDetection: (detection) =>
                        _openSpecies(record, detection),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
  );
}

class _WorksEntry extends StatelessWidget {
  const _WorksEntry({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: const Icon(Icons.auto_awesome_rounded),
      title: const Text('作品'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class _EmptySounds extends StatelessWidget {
  const _EmptySounds();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 24),
    alignment: Alignment.center,
    child: const Column(
      children: [
        Icon(Icons.graphic_eq_rounded, size: 36),
        SizedBox(height: 12),
        Text('保存的自然声音会出现在这里'),
      ],
    ),
  );
}

class _SoundRecordCard extends StatelessWidget {
  const _SoundRecordCard({
    required this.record,
    required this.playing,
    required this.onPlay,
    required this.onDelete,
    required this.onOpenDetection,
  });
  final ExplorationRecord record;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final ValueChanged<SoundDetection> onOpenDetection;

  @override
  Widget build(BuildContext context) {
    final detection = record.detections.firstOrNull;
    final title =
        detection?.specificSpecies?.nameZh ?? detection?.nameZh ?? '未知声音';
    final date = record.createdAt.toLocal();
    final dateText =
        '${date.month}月${date.day}日  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: detection == null ? null : () => onOpenDetection(detection),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 6, 12),
          child: Row(
            children: [
              IconButton.filledTonal(
                key: Key('play-${record.id}'),
                tooltip: playing ? '停止回放' : '回放原声',
                onPressed: onPlay,
                icon: Icon(
                  playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '$dateText · ${record.duration.inSeconds}s · ${record.location}',
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
