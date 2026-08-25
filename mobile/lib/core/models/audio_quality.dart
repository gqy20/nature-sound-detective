class AudioQuality {
  const AudioQuality({
    required this.usable,
    this.warnings = const [],
    this.rms,
    this.peak,
    this.silentRatio,
    this.clippedRatio,
    this.bestWindowRms,
    this.activeWindowCount,
    this.totalWindowCount,
    this.weakSignal = false,
  });

  factory AudioQuality.fromJson(Map<String, Object?> json) {
    return AudioQuality(
      usable: json['usable'] as bool? ?? false,
      warnings: _stringList(json['warnings']),
      rms: _number(json['rms']),
      peak: _number(json['peak']),
      silentRatio: _number(json['silent_ratio']),
      clippedRatio: _number(json['clipped_ratio']),
      bestWindowRms: _number(json['best_window_rms']),
      activeWindowCount: (json['active_window_count'] as num?)?.round(),
      totalWindowCount: (json['total_window_count'] as num?)?.round(),
      weakSignal: json['weak_signal'] as bool? ?? false,
    );
  }

  final bool usable;
  final List<String> warnings;
  final double? rms;
  final double? peak;
  final double? silentRatio;
  final double? clippedRatio;
  final double? bestWindowRms;
  final int? activeWindowCount;
  final int? totalWindowCount;
  final bool weakSignal;

  bool get ecologyUsable => usable && !weakSignal;

  Map<String, Object?> toJson() => {
    'usable': usable,
    'warnings': warnings,
    if (rms != null) 'rms': rms,
    if (peak != null) 'peak': peak,
    if (silentRatio != null) 'silent_ratio': silentRatio,
    if (clippedRatio != null) 'clipped_ratio': clippedRatio,
    if (bestWindowRms != null) 'best_window_rms': bestWindowRms,
    if (activeWindowCount != null) 'active_window_count': activeWindowCount,
    if (totalWindowCount != null) 'total_window_count': totalWindowCount,
    if (weakSignal) 'weak_signal': true,
    'ecology_usable': ecologyUsable,
  };
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

List<String> _stringList(Object? value) => switch (value) {
  List<Object?> items => items.whereType<String>().toList(growable: false),
  _ => const [],
};
