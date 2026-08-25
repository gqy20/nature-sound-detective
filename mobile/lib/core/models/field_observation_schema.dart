import 'dart:convert';

import 'package:flutter/services.dart';

class FieldObservationOption {
  const FieldObservationOption({required this.value, required this.label});
  final String value;
  final String label;
}

class FieldObservationDimension {
  const FieldObservationDimension({
    required this.id,
    required this.label,
    required this.multiple,
    required this.options,
  });
  final String id;
  final String label;
  final bool multiple;
  final List<FieldObservationOption> options;
}

class FieldObservationSchema {
  const FieldObservationSchema({
    required this.version,
    required this.minimumMeaningfulDimensions,
    required this.dimensions,
  });

  final int version;
  final int minimumMeaningfulDimensions;
  final List<FieldObservationDimension> dimensions;

  factory FieldObservationSchema.fromJson(Map<String, Object?> json) {
    final rawDimensions = json['dimensions'];
    if (rawDimensions is! List<Object?>) {
      throw const FormatException('现场观察Schema缺少dimensions');
    }
    return FieldObservationSchema(
      version: json['schema_version'] as int? ?? 1,
      minimumMeaningfulDimensions:
          json['minimum_meaningful_dimensions'] as int? ?? 2,
      dimensions: rawDimensions.map((raw) {
        final value = (raw as Map<Object?, Object?>).cast<String, Object?>();
        final options = value['options'] as List<Object?>? ?? const [];
        return FieldObservationDimension(
          id: value['id'] as String,
          label: value['label'] as String,
          multiple: value['multiple'] as bool? ?? false,
          options: options.map((rawOption) {
            final option = (rawOption as Map<Object?, Object?>)
                .cast<String, Object?>();
            return FieldObservationOption(
              value: option['value'] as String,
              label: option['label'] as String,
            );
          }).toList(growable: false),
        );
      }).toList(growable: false),
    );
  }

  static Future<FieldObservationSchema> load() async {
    final source = await rootBundle.loadString(
      'assets/config/field_observations.json',
    );
    return FieldObservationSchema.fromJson(
      (jsonDecode(source) as Map<Object?, Object?>).cast<String, Object?>(),
    );
  }

  bool isComplete(Map<String, List<String>> selections) {
    final meaningful = selections.entries
        .where((entry) => entry.value.any((value) => value != 'unknown'))
        .map((entry) => entry.key)
        .toSet();
    return meaningful.length >= minimumMeaningfulDimensions;
  }
}
