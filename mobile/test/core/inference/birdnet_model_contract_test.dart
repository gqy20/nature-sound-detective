import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled BirdNET declares species logits and 1024-d embedding',
    () async {
      final metadata =
          jsonDecode(await rootBundle.loadString('assets/models/birdnet.json'))
              as Map<String, dynamic>;
      final outputs = metadata['outputs'] as List<dynamic>;

      expect(metadata['candidate_count'], 200);
      expect(metadata['sample_rate'], 48000);
      expect(metadata['window_samples'], 144000);
      expect(outputs, hasLength(2));
      expect((outputs[0] as Map<String, dynamic>)['shape'], [1, 6522]);
      expect((outputs[1] as Map<String, dynamic>)['shape'], [1, 1024]);
    },
  );
}
