import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/inference/recording_analyzer.dart';

void main() {
  test('cached model coalesces concurrent preload calls', () async {
    var calls = 0;
    final completer = Completer<int>();
    final model = CachedModel<int>(() {
      calls++;
      return completer.future;
    });

    final first = model.load();
    final second = model.load();
    expect(calls, 1);
    completer.complete(42);
    expect(await first, 42);
    expect(await second, 42);
    expect(await model.loadedValue(), 42);
  });

  test('cached model retries after a failed preload', () async {
    var calls = 0;
    final model = CachedModel<int>(() async {
      calls++;
      if (calls == 1) throw StateError('first load failed');
      return 7;
    });

    await expectLater(model.load(), throwsStateError);
    expect(await model.load(), 7);
    expect(calls, 2);
  });

  test(
    'local analyzer disposal is idempotent before models are loaded',
    () async {
      final analyzer = LocalRecordingAnalyzer();

      await analyzer.dispose();
      await analyzer.dispose();
    },
  );
}
