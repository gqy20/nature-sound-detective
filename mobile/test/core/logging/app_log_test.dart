import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';

class _MemorySink implements LogSink {
  final entries = <LogEntry>[];

  @override
  Future<void> write(LogEntry entry) async => entries.add(entry);

  @override
  Future<void> flush() async {}
}

void main() {
  test('redacts credentials and sensitive fields', () async {
    final sink = _MemorySink();
    final logger = AppLogger(sinks: [sink]);

    logger.emit(
      LogLevel.error,
      'cloud',
      'failed',
      fields: {
        'authorization': 'Bearer secret-value',
        'note': 'key sk-1234567890abcdef',
      },
      error: r'Bearer another-secret at D:\private\recordings\child.wav',
    );
    await logger.flush();

    expect(sink.entries.single.fields['authorization'], '[REDACTED]');
    expect(sink.entries.single.fields['note'], contains('[REDACTED_KEY]'));
    expect(sink.entries.single.error, 'Bearer [REDACTED] at [REDACTED_PATH]');
  });

  test('rolls files and exports a bounded diagnostic log', () async {
    final root = await Directory.systemTemp.createTemp('xykw-log-test-');
    addTearDown(() => root.delete(recursive: true));
    final fileSink = RollingFileLogSink(root, maxBytes: 180, backupCount: 2);
    final logger = AppLogger(sinks: [fileSink])..fileSink = fileSink;

    for (var index = 0; index < 8; index++) {
      logger.emit(
        LogLevel.info,
        'test',
        'event',
        traceId: 'rec_12345678',
        fields: {'index': index, 'padding': 'x' * 50},
      );
    }
    await logger.flush();
    final exported = await fileSink.export();

    expect(await exported.exists(), isTrue);
    expect(await exported.readAsString(), contains('rec_12345678'));
    expect(
      await root.list().where((file) => file.path.endsWith('.jsonl')).length,
      lessThanOrEqualTo(4),
    );
  });
}
