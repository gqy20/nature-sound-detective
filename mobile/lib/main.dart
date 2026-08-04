import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nature_sound_detective/app.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/inference/recording_analyzer.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await AppLog.bootstrap();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        AppLog.error(
          'flutter',
          'framework_error',
          error: details.exception,
          stackTrace: details.stack,
        );
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        AppLog.error(
          'flutter',
          'platform_error',
          error: error,
          stackTrace: stackTrace,
        );
        return true;
      };
      final deviceFields = <String, Object?>{
        'platform': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'app_version': '0.2.0+2003',
        'build_mode': kReleaseMode ? 'release' : 'debug',
      };
      if (Platform.isAndroid) {
        try {
          final native = await const MethodChannel(
            'com.xykw.nature_sound/audio_recorder',
          ).invokeMapMethod<Object?, Object?>('getDiagnostics');
          if (native != null) {
            for (final item in native.entries) {
              if (item.key is String) {
                deviceFields[item.key! as String] = item.value;
              }
            }
          }
        } catch (error, stackTrace) {
          AppLog.warning(
            'app',
            'device_diagnostics_unavailable',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      AppLog.info('app', 'started', fields: deviceFields);
      final analyzer = LocalRecordingAnalyzer();
      runApp(NatureSoundApp(analyzer: analyzer));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(analyzer.preload());
      });
    },
    (error, stackTrace) {
      AppLog.error(
        'dart',
        'uncaught_error',
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}
