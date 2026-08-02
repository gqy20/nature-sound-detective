import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final path = await AppLog.exportDiagnostics();
      if (!mounted) return;
      if (path == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前环境没有可导出的日志文件。')));
        return;
      }
      await Clipboard.setData(ClipboardData(text: path));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('诊断文件路径已复制。')));
    } catch (error, stackTrace) {
      AppLog.error(
        'logging',
        'diagnostic_export_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时无法导出诊断日志。')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = AppLog.logger.recent;
    return Scaffold(
      appBar: AppBar(title: const Text('运行诊断')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Text(
              '仅记录运行阶段、耗时和错误，不包含录音内容、密钥或完整模型响应。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FilledButton.icon(
              onPressed: _exporting ? null : _export,
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(_exporting ? '正在整理…' : '导出诊断日志'),
            ),
          ),
          const SizedBox(height: 8),
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
}
