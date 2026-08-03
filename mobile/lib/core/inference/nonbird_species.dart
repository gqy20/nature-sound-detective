import 'dart:convert';

class NonBirdSpecies {
  const NonBirdSpecies({
    required this.outputIndex,
    required this.taxonId,
    required this.categoryId,
    required this.nameZh,
    required this.threshold,
    required this.centroid,
    required this.minCosineSimilarity,
    this.scientificName,
  });

  final int outputIndex;
  final String taxonId;
  final String categoryId;
  final String nameZh;
  final String? scientificName;
  final double threshold;
  final List<double> centroid;
  final double minCosineSimilarity;
}

class NonBirdRejectionPolicy {
  const NonBirdRejectionPolicy({
    this.backgroundMargin = 0.05,
    this.minTopMargin = 0,
    this.minSupportingWindows = 2,
    this.shortClipThresholdExcess = 0.1,
    this.maxWindowGapSeconds = 0.15,
  });

  factory NonBirdRejectionPolicy.fromJson(Object? source) {
    final value = source is Map<String, dynamic>
        ? source
        : const <String, dynamic>{};
    return NonBirdRejectionPolicy(
      backgroundMargin:
          (value['background_margin'] as num?)?.toDouble() ?? 0.05,
      minTopMargin: (value['min_top_margin'] as num?)?.toDouble() ?? 0,
      minSupportingWindows: value['min_supporting_windows'] as int? ?? 2,
      shortClipThresholdExcess:
          (value['short_clip_threshold_excess'] as num?)?.toDouble() ?? 0.1,
      maxWindowGapSeconds:
          (value['max_window_gap_seconds'] as num?)?.toDouble() ?? 0.15,
    );
  }

  final double backgroundMargin;
  final double minTopMargin;
  final int minSupportingWindows;
  final double shortClipThresholdExcess;
  final double maxWindowGapSeconds;
}

class NonBirdModelCatalog {
  const NonBirdModelCatalog({
    required this.modelId,
    required this.version,
    required this.available,
    required this.embeddingTensorIndex,
    required this.embeddingTensorName,
    required this.species,
    required this.rejection,
  });

  factory NonBirdModelCatalog.fromJson(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Non-bird metadata must be an object');
    }
    final available = value['available'] == true;
    final input = value['input'];
    final shape = input is Map<String, dynamic> ? input['shape'] : null;
    if (shape is! List || shape.length != 2 || shape.last != 1024) {
      throw const FormatException('Non-bird model must use 1024-D embeddings');
    }
    final rows = value['classes'];
    if (rows is! List) {
      throw const FormatException('Non-bird metadata is missing classes');
    }
    final species = rows
        .map((row) {
          if (row is! Map<String, dynamic>) {
            throw const FormatException('Invalid non-bird class');
          }
          final threshold = row['threshold'];
          if (row['output_index'] is! int ||
              row['taxon_id'] is! String ||
              row['category_id'] is! String ||
              row['name_zh'] is! String ||
              threshold is! num ||
              threshold <= 0 ||
              threshold >= 1) {
            throw const FormatException('Invalid non-bird class fields');
          }
          return NonBirdSpecies(
            outputIndex: row['output_index'] as int,
            taxonId: row['taxon_id'] as String,
            categoryId: row['category_id'] as String,
            nameZh: row['name_zh'] as String,
            scientificName: row['scientific_name'] as String?,
            threshold: threshold.toDouble(),
            centroid: switch (row['centroid']) {
              final List values =>
                values
                    .whereType<num>()
                    .map((item) => item.toDouble())
                    .toList(growable: false),
              _ => const [],
            },
            minCosineSimilarity:
                (row['min_cosine_similarity'] as num?)?.toDouble() ?? -1,
          );
        })
        .toList(growable: false);
    if (available && species.isEmpty) {
      throw const FormatException('Available non-bird model needs classes');
    }
    return NonBirdModelCatalog(
      modelId: value['id'] as String? ?? 'hangzhou-nonbird',
      version: value['version'] as String? ?? 'unknown',
      available: available,
      embeddingTensorIndex:
          value['birdnet_embedding_tensor_index'] as int? ?? 545,
      embeddingTensorName:
          value['birdnet_embedding_tensor_name'] as String? ?? '',
      species: species,
      rejection: NonBirdRejectionPolicy.fromJson(value['rejection']),
    );
  }

  final String modelId;
  final String version;
  final bool available;
  final int embeddingTensorIndex;
  final String embeddingTensorName;
  final List<NonBirdSpecies> species;
  final NonBirdRejectionPolicy rejection;
}
