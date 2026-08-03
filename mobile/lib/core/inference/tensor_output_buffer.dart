/// Creates a Dart list tree that matches a TensorFlow Lite output shape.
///
/// [IsolateInterpreter] transfers tensor values between isolates as ordinary
/// Dart lists. Using typed lists for nested output rows makes Tensor.copyTo
/// attempt to replace a typed row with a `List<double>`, which fails at
/// runtime. Keeping every level as an ordinary list makes the copy type-safe.
Object createTensorOutputBuffer(List<int> shape) {
  if (shape.isEmpty) {
    throw ArgumentError.value(shape, 'shape', 'must contain at least one axis');
  }
  if (shape.any((dimension) => dimension <= 0)) {
    throw ArgumentError.value(shape, 'shape', 'dimensions must be positive');
  }
  return _createAxis(shape, 0);
}

Object _createAxis(List<int> shape, int axis) {
  final length = shape[axis];
  if (axis == shape.length - 1) {
    return List<double>.filled(length, 0, growable: false);
  }
  return List<Object>.generate(
    length,
    (_) => _createAxis(shape, axis + 1),
    growable: false,
  );
}

List<double> flattenTensorOutput(Object output) {
  final flattened = <double>[];
  _appendValues(output, flattened);
  return List<double>.unmodifiable(flattened);
}

void _appendValues(Object value, List<double> target) {
  if (value is num) {
    target.add(value.toDouble());
    return;
  }
  if (value is List) {
    for (final item in value) {
      if (item == null) {
        throw StateError('Tensor output contains a null value');
      }
      _appendValues(item, target);
    }
    return;
  }
  throw StateError('Unsupported tensor output value: ${value.runtimeType}');
}
