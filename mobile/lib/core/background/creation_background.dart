import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';

class CreationBackgroundScheduler {
  const CreationBackgroundScheduler();

  static const _channel = MethodChannel(
    'com.xykw.nature_sound/creation_background',
  );

  Future<void> schedule(String recordId, String directoryPath) async {
    if (recordId.isEmpty || directoryPath.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('schedule', {
        'record_id': recordId,
        'task_path': '$directoryPath/task.json',
      });
      AppLog.info('creation_background', 'scheduled', traceId: recordId);
    } on PlatformException catch (error, stackTrace) {
      AppLog.warning(
        'creation_background',
        'schedule_failed',
        traceId: recordId,
        fields: {'platform_code': error.code},
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> cancel(String recordId) async {
    if (recordId.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('cancel', {'record_id': recordId});
      AppLog.info('creation_background', 'cancelled', traceId: recordId);
    } on PlatformException catch (error, stackTrace) {
      AppLog.warning(
        'creation_background',
        'cancel_failed',
        traceId: recordId,
        fields: {'platform_code': error.code},
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
