import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/storage/creation_store.dart';
import 'package:nature_sound_detective/features/creation/creation_page.dart';
import 'package:nature_sound_detective/shared/widgets/app_popover_menu.dart';
import 'package:share_plus/share_plus.dart';

class WorksPage extends StatefulWidget {
  const WorksPage({super.key, this.store});

  final CreationStore? store;

  @override
  State<WorksPage> createState() => _WorksPageState();
}

class _WorksPageState extends State<WorksPage> {
  late final CreationStore _store;
  List<CreationRecord> _records = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? CreationStore();
    _load();
  }

  Future<void> _load() async {
    try {
      final records = await _store.list();
      if (!mounted) return;
      setState(() => _records = records);
    } catch (error, stackTrace) {
      AppLog.error(
        'works',
        'list_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _showMessage('作品册读取失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(CreationRecord record) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CreationPage(
          subject: record.subject,
          location: record.location,
          existingRecord: record,
        ),
      ),
    );
    await _load();
  }

  Future<void> _share(CreationRecord record) async {
    final path = record.finalVideoPath.isNotEmpty
        ? record.finalVideoPath
        : (record.videoPath.isNotEmpty ? record.videoPath : record.musicPath);
    if (path.isEmpty || !File(path).existsSync()) {
      AppLog.warning('works', 'share_file_missing', traceId: record.id);
      if (mounted) _showMessage('作品文件已经不存在。');
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: '我在${record.location}听见了${record.subject}，这是我的自然声音作品。',
          files: [XFile(path)],
        ),
      );
      AppLog.info('works', 'share_opened', traceId: record.id);
    } catch (error, stackTrace) {
      AppLog.warning(
        'works',
        'share_failed',
        traceId: record.id,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _showMessage('暂时无法分享这件作品。');
    }
  }

  Future<void> _delete(CreationRecord record) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这件作品？'),
        content: const Text('音乐、视频、旁白和复制的原声都会从本机删除，无法恢复。'),
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
    try {
      await _store.delete(record);
      await _load();
    } catch (error, stackTrace) {
      AppLog.error(
        'works',
        'delete_failed',
        traceId: record.id,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _showMessage('作品删除失败，请稍后重试。');
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('作品')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
          ? const Center(
              child: Text('完成的音乐与短片会保存在这里', textAlign: TextAlign.center),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                itemCount: _records.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final record = _records[index];
                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => _open(record),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE4EEE7),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Icon(_statusIcon(record.stage)),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    record.subject,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(_statusText(record)),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${record.createdAt.month}月${record.createdAt.day}日 · ${record.location}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (record.finalVideoPath.isNotEmpty ||
                                record.videoPath.isNotEmpty ||
                                record.musicPath.isNotEmpty)
                              IconButton(
                                tooltip: '分享作品',
                                onPressed: () => _share(record),
                                icon: const Icon(Icons.ios_share_rounded),
                              ),
                            AppPopoverMenu<String>(
                              tooltip: '作品操作',
                              minWidth: 170,
                              onSelected: (value) {
                                if (value == 'delete') _delete(record);
                              },
                              actions: const [
                                AppPopoverAction(
                                  value: 'delete',
                                  label: '删除作品',
                                  icon: Icons.delete_outline_rounded,
                                  destructive: true,
                                ),
                              ],
                              child: const SizedBox.square(
                                dimension: 44,
                                child: Icon(Icons.more_horiz_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  IconData _statusIcon(CreationStage stage) => switch (stage) {
    CreationStage.completed => Icons.movie_rounded,
    CreationStage.partial => Icons.pending_actions_rounded,
    CreationStage.failed => Icons.error_outline_rounded,
    _ => Icons.auto_awesome_rounded,
  };

  String _statusText(CreationRecord record) => switch (record.stage) {
    CreationStage.completed => '音乐、原声与旁白已合成',
    CreationStage.partial => '部分完成，点按继续',
    CreationStage.failed => '生成失败，点按查看',
    _ => record.message,
  };
}
