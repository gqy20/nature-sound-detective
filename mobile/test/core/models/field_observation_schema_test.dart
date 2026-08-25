import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/models/field_observation_schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the shared field observation schema', () async {
    final schema = await FieldObservationSchema.load();

    expect(schema.version, 1);
    expect(schema.minimumMeaningfulDimensions, 2);
    expect(schema.dimensions.map((item) => item.id), containsAll([
      'time',
      'habitat',
      'behavior',
      'sound_pattern',
      'appearance',
    ]));
    expect(
      schema.isComplete({
        'time': ['early_morning'],
        'habitat': ['tree_canopy'],
      }),
      isTrue,
    );
    expect(schema.isComplete({'time': ['unknown']}), isFalse);
  });
}
