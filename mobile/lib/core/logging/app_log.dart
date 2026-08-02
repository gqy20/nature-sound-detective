import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.component,
    required this.event,
    required this.fields,
    this.traceId,
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String component;
  final String event;
  final Map<String, Object?> fields;
  final String? traceId;
  final String? error;
  final String? stackTrace;

  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'level': level.name,
    'component': component,
    'event': event,
    if (traceId != null) 'trace_id': traceId,
    ...fields,
    if (error != null) 'error': error,
    if (stackTrace != null) 'stack_trace': stackTrace,
  };

  String get jsonLine => jsonEncode(toJson());
}

abstract interface class LogSink {
  Future<void> write(LogEntry entry);
  Future<void> flush();
}

class ConsoleLogSink implements LogSink {
  const ConsoleLogSink();

  @override
  Future<void> write(LogEntry entry) async {
    debugPrint(entry.jsonLine);
  }

  @override
  Future<void> flush() async {}
}

class RollingFileLogSink implements LogSink {
  RollingFileLogSink(
    this.directory, {
    this.maxBytes = 512 * 1024,
    this.backupCount = 2,
  });

  final Directory directory;
  final int maxBytes;
  final int backupCount;
  Future<void> _pending = Future.value();

  File get _active =>
      File('${directory.path}${Platform.pathSeparator}app.jsonl');

  @override
  Future<void> write(LogEntry entry) {
    _pending = _pending.catchError((_) {}).then((_) async {
      await directory.create(recursive: true);
      final bytes = utf8.encode('${entry.jsonLine}\n');
      if (await _active.exists() &&
          await _active.length() + bytes.length > maxBytes) {
        await _rotate();
      }
      await _active.writeAsBytes(bytes, mode: FileMode.append, flush: false);
    });
    return _pending;
  }

  Future<void> _rotate() async {
    for (var index = backupCount; index >= 1; index--) {
      final source = File(
        '${directory.path}${Platform.pathSeparator}app.${index == 1 ? '' : '${index - 1}.'}jsonl',
      );
      final target = File(
        '${directory.path}${Platform.pathSeparator}app.$index.jsonl',
      );
      if (!await source.exists()) continue;
      if (await target.exists()) await target.delete();
      await source.rename(target.path);
    }
  }

  Future<File> export() async {
    await flush();
    final output = File(
      '${directory.path}${Platform.pathSeparator}diagnostic-${DateTime.now().toUtc().millisecondsSinceEpoch}.jsonl',
    );
    final sink = output.openWrite();
    for (var index = backupCount; index >= 1; index--) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}app.$index.jsonl',
      );
      if (await file.exists()) await sink.addStream(file.openRead());
    }
    if (await _active.exists()) await sink.addStream(_active.openRead());
    await sink.flush();
    await sink.close();
    return output;
  }

  @override
  Future<void> flush() => _pending;
}

class AppLogger {
  AppLogger({required List<LogSink> sinks, this.memoryLimit = 200})
    : _sinks = List.of(sinks);

  final List<LogSink> _sinks;
  final int memoryLimit;
  final List<LogEntry> _recent = [];
  RollingFileLogSink? fileSink;

  List<LogEntry> get recent => List.unmodifiable(_recent.reversed);

  void emit(
    LogLevel level,
    String component,
    String event, {
    String? traceId,
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      component: component,
      event: event,
      traceId: traceId,
      fields: _sanitizeFields(fields),
      error: error == null ? null : _redact(error.toString()),
      stackTrace: stackTrace == null ? null : _redact(stackTrace.toString()),
    );
    _recent.add(entry);
    if (_recent.length > memoryLimit) _recent.removeAt(0);
    for (final sink in _sinks) {
      unawaited(sink.write(entry).catchError((_) {}));
    }
  }

  Future<void> flush() async {
    await Future.wait(_sinks.map((sink) => sink.flush()));
  }

  static Map<String, Object?> _sanitizeFields(Map<String, Object?> fields) {
    final output = <String, Object?>{};
    for (final item in fields.entries) {
      final key = item.key.toLowerCase();
      if (_sensitiveKeys.any(key.contains)) {
        output[item.key] = '[REDACTED]';
      } else {
        output[item.key] = _safeValue(item.value);
      }
    }
    return output;
  }

  static Object? _safeValue(Object? value) {
    if (value == null || value is num || value is bool) return value;
    if (value is String) {
      return _redact(value.length > 500 ? value.substring(0, 500) : value);
    }
    if (value is Iterable) return value.take(20).map(_safeValue).toList();
    return _redact(value.toString());
  }

  static String _redact(String value) => value
      .replaceAll(
        RegExp(r'bearer\s+[a-z0-9._-]+', caseSensitive: false),
        'Bearer [REDACTED]',
      )
      .replaceAll(
        RegExp(r'sk-[a-z0-9_-]{8,}', caseSensitive: false),
        '[REDACTED_KEY]',
      )
      .replaceAll(
        RegExp(
          r'(?:[a-z]:\\|/)[^\r\n"]+\.(?:wav|mp3|mp4|json|tmp)',
          caseSensitive: false,
        ),
        '[REDACTED_PATH]',
      );

  static const _sensitiveKeys = [
    'api_key',
    'apikey',
    'authorization',
    'token',
    'audio_data',
    'audio_path',
    'prompt',
    'response_body',
  ];
}

class AppLog {
  AppLog._();

  static AppLogger _logger = AppLogger(sinks: const [ConsoleLogSink()]);

  static AppLogger get logger => _logger;

  static Future<void> bootstrap() async {
    try {
      final support = await getApplicationSupportDirectory();
      final fileSink = RollingFileLogSink(
        Directory('${support.path}${Platform.pathSeparator}logs'),
      );
      final logger = AppLogger(sinks: [const ConsoleLogSink(), fileSink])
        ..fileSink = fileSink;
      _logger = logger;
    } catch (error, stackTrace) {
      _logger.emit(
        LogLevel.error,
        'logging',
        'bootstrap_failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @visibleForTesting
  static void useLogger(AppLogger logger) => _logger = logger;

  static void debug(
    String component,
    String event, {
    String? traceId,
    Map<String, Object?> fields = const {},
  }) => _logger.emit(
    LogLevel.debug,
    component,
    event,
    traceId: traceId,
    fields: fields,
  );

  static void info(
    String component,
    String event, {
    String? traceId,
    Map<String, Object?> fields = const {},
  }) => _logger.emit(
    LogLevel.info,
    component,
    event,
    traceId: traceId,
    fields: fields,
  );

  static void warning(
    String component,
    String event, {
    String? traceId,
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) => _logger.emit(
    LogLevel.warning,
    component,
    event,
    traceId: traceId,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );

  static void error(
    String component,
    String event, {
    String? traceId,
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) => _logger.emit(
    LogLevel.error,
    component,
    event,
    traceId: traceId,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );

  static Future<String?> exportDiagnostics() async {
    final sink = _logger.fileSink;
    if (sink == null) return null;
    return (await sink.export()).path;
  }
}
