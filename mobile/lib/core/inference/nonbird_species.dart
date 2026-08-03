import 'dart:convert';

class NonBirdSpecies {
  const NonBirdSpecies({
    required this.outputIndex,
    required this.taxonId,
    required this.categoryId,
    required this.nameZh,
    required this.threshold,
    this.scientificName,
  });

  final int outputIndex;
  final String taxonId;
  final String categoryId;
  final String nameZh;
  final String? scientificName;
  final double threshold;
}

class NonBirdModelCatalog {
  const NonBirdModelCatalog({
    required this.modelId,
    required this.version,
    required this.available,
    required this.embeddingTensorIndex,
    required this.embeddingTensorName,
    required this.species,
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
    );
  }

  final String modelId;
  final String version;
  final bool available;
  final int embeddingTensorIndex;
  final String embeddingTensorName;
  final List<NonBirdSpecies> species;
}
