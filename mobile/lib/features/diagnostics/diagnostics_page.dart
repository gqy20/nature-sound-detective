import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/diagnostics/debug_export_service.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/storage/exploration_store.dart';
import 'package:share_plus/share_plus.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({
    super.key,
    this.session,
    this.explorationStore,
    this.exportService,
  });

  final DebugSessionSnapshot? session;
  final ExplorationStore? explorationStore;
  final DebugExportService? exportService;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  late final DebugExportService _exportService;
  bool _exporting = false;
  bool _includeAudio = true;

  @override
  void initState() {
    super.initState();
    _exportService =
        widget.exportService ??
        DebugExportService(explorationStore: widget.explorationStore);
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final result = await _exportService.export(
        session: widget.session,
        includeAudio: _includeAudio,
      );
      final size = await result.byteLength;
      await SharePlus.instance.share(
        ShareParams(
          text:
              '自然声探员内测诊断包${result.sessionId == null ? '' : ' · ${result.sessionId}'}',
          files: [XFile(result.file.path, mimeType: 'application/zip')],
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('诊断包已生成 · ${_formatBytes(size)}')));
    } catch (error, stackTrace) {
      AppLog.error(
        'diagnostics',
        'share_failed',
        traceId: widget.session?.id,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('诊断包导出失败，请查看下方日志。')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = AppLog.logger.recent;
    final session = widget.session;
    return Scaffold(
      appBar: AppBar(title: const Text('运行诊断')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      session == null ? '最近一次声音' : '本次录音',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session == null
                          ? '如果当前没有录音，将从声音册选取最近一条。'
                          : '${session.duration.inSeconds}s · ${session.detections.length} 条识别结果',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('包含原始录音'),
                      subtitle: const Text('录音可能包含谈话和环境信息，请只分享给可信人员。'),
                      value: _includeAudio,
                      onChanged: _exporting
                          ? null
                          : (value) => setState(() => _includeAudio = value),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const Key('export-debug-bundle-button'),
                      onPressed: _exporting ? null : _export,
                      icon: _exporting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.ios_share_rounded),
                      label: Text(_exporting ? '正在整理…' : '导出并分享'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: Text('包含识别结果、音质指标、设备与构建信息和脱敏日志；不包含 API 密钥或完整云端响应。'),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text('最近日志', style: Theme.of(context).textTheme.titleSmall),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('本次运行暂时没有日志。'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 20),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return SelectableText(
                        '${entry.timestamp.toLocal()}  ${entry.level.name.toUpperCase()}\n'
                        '${entry.component}.${entry.event}'
                        '${entry.traceId == null ? '' : '\ntrace ${entry.traceId}'}'
                        '${entry.error == null ? '' : '\n${entry.error}'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kib = bytes / 1024;
    if (kib < 1024) return '${kib.toStringAsFixed(1)} KB';
    return '${(kib / 1024).toStringAsFixed(1)} MB';
  }
}
