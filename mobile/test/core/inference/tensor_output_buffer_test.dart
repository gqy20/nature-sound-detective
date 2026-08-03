import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/inference/tensor_output_buffer.dart';

void main() {
  group('createTensorOutputBuffer', () {
    test('creates an ordinary rank-one list', () {
      final output = createTensorOutputBuffer([3]);

      expect(output, isA<List<double>>());
      expect(output, [0.0, 0.0, 0.0]);
    });

    test('creates ordinary nested rows for isolate output replacement', () {
      final output = createTensorOutputBuffer([1, 3]) as List<Object>;

      expect(output.single, isA<List<double>>());
      output[0] = <double>[0.1, 0.2, 0.3];

      expect(flattenTensorOutput(output), [0.1, 0.2, 0.3]);
    });

    test('preserves row-major order for higher-rank tensors', () {
      final output = createTensorOutputBuffer([2, 2, 2]);

      expect(flattenTensorOutput(output), List<double>.filled(8, 0));
    });

    test('rejects invalid shapes', () {
      expect(() => createTensorOutputBuffer([]), throwsArgumentError);
      expect(() => createTensorOutputBuffer([1, 0]), throwsArgumentError);
    });
  });
}
