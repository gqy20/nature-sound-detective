class DetectionInterval {
  const DetectionInterval({
    required this.startSeconds,
    required this.endSeconds,
  }) : assert(startSeconds >= 0),
       assert(endSeconds >= startSeconds);

  factory DetectionInterval.fromJson(Map<String, Object?> json) {
    final start = (json['start'] as num?)?.toDouble() ?? 0;
    final end = (json['end'] as num?)?.toDouble() ?? start;
    return DetectionInterval(startSeconds: start, endSeconds: end);
  }

  final double startSeconds;
  final double endSeconds;

  Map<String, Object?> toJson() => {'start': startSeconds, 'end': endSeconds};
}

class SpeciesCandidate {
  const SpeciesCandidate({
    required this.nameZh,
    this.scientificName,
    this.taxonomyId,
  });

  factory SpeciesCandidate.fromJson(Map<String, Object?> json) {
    return SpeciesCandidate(
      nameZh: json['name_zh'] as String? ?? '',
      scientificName: json['scientific_name'] as String?,
      taxonomyId: json['taxonomy_id'] as String?,
    );
  }

  final String nameZh;
  final String? scientificName;
  final String? taxonomyId;

  Map<String, Object?> toJson() => {
    'name_zh': nameZh,
    if (scientificName != null) 'scientific_name': scientificName,
    if (taxonomyId != null) 'taxonomy_id': taxonomyId,
  };
}

class SoundDetection {
  const SoundDetection({
    required this.categoryId,
    required this.nameZh,
    required this.confidence,
    required this.model,
    this.supportingModels = const [],
    this.intervals = const [],
    this.specificSpecies,
    this.tentative = false,
  }) : assert(confidence >= 0 && confidence <= 1);

  factory SoundDetection.fromJson(Map<String, Object?> json) {
    final intervalValues = json['intervals'];
    return SoundDetection(
      categoryId: json['category_id'] as String? ?? 'unknown',
      nameZh: json['name_zh'] as String? ?? '无法判断',
      confidence: ((json['confidence'] as num?)?.toDouble() ?? 0).clamp(0, 1),
      model: json['model'] as String? ?? 'unknown',
      supportingModels: switch (json['supporting_models']) {
        final List<Object?> values => values.whereType<String>().toList(),
        _ => const [],
      },
      intervals: intervalValues is List<Object?>
          ? intervalValues
                .whereType<Map<Object?, Object?>>()
                .map(
                  (value) =>
                      DetectionInterval.fromJson(value.cast<String, Object?>()),
                )
                .toList(growable: false)
          : const [],
      specificSpecies: switch (json['specific_species']) {
        Map<Object?, Object?> value => SpeciesCandidate.fromJson(
          value.cast<String, Object?>(),
        ),
        _ => null,
      },
      tentative: json['tentative'] as bool? ?? false,
    );
  }

  final String categoryId;
  final String nameZh;
  final double confidence;
  final String model;
  final List<String> supportingModels;
  final List<DetectionInterval> intervals;
  final SpeciesCandidate? specificSpecies;
  final bool tentative;

  List<String> get evidenceModels =>
      supportingModels.isEmpty ? <String>[model] : supportingModels;

  Map<String, Object?> toJson() => {
    'category_id': categoryId,
    'name_zh': nameZh,
    'confidence': confidence,
    'model': model,
    if (supportingModels.isNotEmpty) 'supporting_models': supportingModels,
    'intervals': intervals.map((item) => item.toJson()).toList(),
    'specific_species': specificSpecies?.toJson(),
    if (tentative) 'tentative': true,
  };
}
