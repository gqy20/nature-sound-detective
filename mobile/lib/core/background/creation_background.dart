import 'package:flutter/services.dart';

class CreationBackgroundScheduler {
  const CreationBackgroundScheduler();

  static const _channel = MethodChannel(
    'com.xykw.nature_sound/creation_background',
  );

  Future<void> schedule(String recordId, String directoryPath) async {
    if (recordId.isEmpty || directoryPath.isEmpty) return;
    await _channel.invokeMethod<void>('schedule', {
      'record_id': recordId,
      'task_path': '$directoryPath/task.json',
    });
  }

  Future<void> cancel(String recordId) async {
    if (recordId.isEmpty) return;
    await _channel.invokeMethod<void>('cancel', {'record_id': recordId});
  }
}
