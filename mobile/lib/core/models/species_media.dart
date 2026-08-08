class SpeciesMedia {
  const SpeciesMedia({
    required this.assetPath,
    required this.author,
    required this.license,
    required this.sourceName,
    required this.sourceUrl,
    required this.referenceUrl,
    this.timeHint,
    this.locationHint,
    this.appearanceHint,
  });

  final String assetPath;
  final String author;
  final String license;
  final String sourceName;
  final String sourceUrl;
  final String referenceUrl;
  final String? timeHint;
  final String? locationHint;
  final String? appearanceHint;

  String get credit => '照片 · $author / $sourceName · $license';
}

abstract final class SpeciesMediaCatalog {
  static const Map<String, SpeciesMedia> _byScientificName = {
    'pycnonotus sinensis': SpeciesMedia(
      assetPath: 'assets/species/pycnonotus_sinensis.webp',
      author: 'CharlesLam',
      license: 'CC BY-SA 2.0',
      sourceName: 'Wikimedia Commons',
      sourceUrl:
          'https://commons.wikimedia.org/wiki/File:Light-vented_Bulbul2.jpg',
      referenceUrl:
          'https://ai.open.hhodata.com/species/bird/pycnonotus-sinensis/',
      timeHint: '清晨',
      locationHint: '树上',
      appearanceHint: '白头',
    ),
  };

  static SpeciesMedia? lookup(String? scientificName) {
    final key = scientificName?.trim().toLowerCase();
    if (key == null || key.isEmpty) return null;
    return _byScientificName[key];
  }
}
