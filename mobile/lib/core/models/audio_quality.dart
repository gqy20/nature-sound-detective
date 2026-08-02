class AudioQuality {
  const AudioQuality({
    required this.usable,
    this.warnings = const [],
    this.rms,
    this.peak,
    this.silentRatio,
  });

  factory AudioQuality.fromJson(Map<String, Object?> json) {
    return AudioQuality(
      usable: json['usable'] as bool? ?? false,
      warnings: _stringList(json['warnings']),
      rms: _number(json['rms']),
      peak: _number(json['peak']),
      silentRatio: _number(json['silent_ratio']),
    );
  }

  final bool usable;
  final List<String> warnings;
  final double? rms;
  final double? peak;
  final double? silentRatio;

  Map<String, Object?> toJson() => {
    'usable': usable,
    'warnings': warnings,
    if (rms != null) 'rms': rms,
    if (peak != null) 'peak': peak,
    if (silentRatio != null) 'silent_ratio': silentRatio,
  };
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

List<String> _stringList(Object? value) => switch (value) {
  List<Object?> items => items.whereType<String>().toList(growable: false),
  _ => const [],
};
