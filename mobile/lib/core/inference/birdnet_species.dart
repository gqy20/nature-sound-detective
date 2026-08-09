import 'dart:convert';

import 'package:nature_sound_detective/core/models/detection.dart';

class BirdnetSpecies {
  const BirdnetSpecies({
    required this.outputIndex,
    required this.scientificName,
    required this.nameZh,
    this.sourceNameZh,
    required this.nameEn,
    required this.geoScore,
  });

  final int outputIndex;
  final String scientificName;
  final String nameZh;
  final String? sourceNameZh;
  final String nameEn;
  final double geoScore;
}

class BirdnetSpeciesCatalog {
  const BirdnetSpeciesCatalog(this.species);

  factory BirdnetSpeciesCatalog.fromJson(String source) {
    final document = jsonDecode(source);
    if (document is! Map<String, dynamic>) {
      throw const FormatException('BirdNET catalog must be a JSON object');
    }
    final rows = document['species'];
    if (rows is! List) {
      throw const FormatException('BirdNET catalog is missing species');
    }
    final declaredCount = document['species_count'];
    if (declaredCount is int && declaredCount != rows.length) {
      throw const FormatException('BirdNET catalog count does not match rows');
    }

    final species = rows
        .map((row) {
          if (row is! Map<String, dynamic>) {
            throw const FormatException('Invalid BirdNET species row');
          }
          final outputIndex = row['output_index'];
          final scientificName = row['scientific_name'];
          final nameZh = row['name_zh'];
          final sourceNameZh = row['source_name_zh'];
          final nameEn = row['name_en'];
          final geoScore = row['geo_score'];
          if (outputIndex is! int ||
              outputIndex < 0 ||
              outputIndex >= 6522 ||
              scientificName is! String ||
              nameZh is! String ||
              (sourceNameZh != null && sourceNameZh is! String) ||
              nameEn is! String ||
              geoScore is! num) {
            throw const FormatException('Invalid BirdNET species fields');
          }
          return BirdnetSpecies(
            outputIndex: outputIndex,
            scientificName: scientificName,
            nameZh: nameZh,
            sourceNameZh: sourceNameZh as String?,
            nameEn: nameEn,
            geoScore: geoScore.toDouble(),
          );
        })
        .toList(growable: false);

    if (species.isEmpty ||
        species.map((item) => item.outputIndex).toSet().length !=
            species.length) {
      throw const FormatException(
        'BirdNET catalog must contain unique species',
      );
    }
    return BirdnetSpeciesCatalog(species);
  }

  final List<BirdnetSpecies> species;

  Map<String, BirdnetSpecies> get byScientificName => {
    for (final item in species) item.scientificName.toLowerCase(): item,
  };

  SoundDetection normalizeDetection(SoundDetection detection) {
    final candidate = detection.specificSpecies;
    final scientificName = candidate?.scientificName?.trim();
    if (candidate == null || scientificName == null || scientificName.isEmpty) {
      return detection;
    }
    final current = byScientificName[scientificName.toLowerCase()];
    if (current == null || current.nameZh == candidate.nameZh) return detection;
    return SoundDetection(
      categoryId: detection.categoryId,
      nameZh: detection.nameZh,
      confidence: detection.confidence,
      model: detection.model,
      supportingModels: detection.supportingModels,
      intervals: detection.intervals,
      specificSpecies: SpeciesCandidate(
        nameZh: current.nameZh,
        scientificName: candidate.scientificName,
        taxonomyId: candidate.taxonomyId,
      ),
      tentative: detection.tentative,
    );
  }
}
