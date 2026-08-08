import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/models/species_media.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('looks up media by normalized scientific name', () {
    final media = SpeciesMediaCatalog.lookup('  Pycnonotus sinensis  ');

    expect(media, isNotNull);
    expect(media!.assetPath, 'assets/species/pycnonotus_sinensis.webp');
    expect(media.license, 'CC BY-SA 2.0');
    expect(media.referenceUrl, contains('hho'));
  });

  test('returns null when a species has no curated image', () {
    expect(SpeciesMediaCatalog.lookup('Unknown species'), isNull);
    expect(SpeciesMediaCatalog.lookup(null), isNull);
  });

  test('bundles images for all 20 unambiguous official species', () async {
    const officialScientificNames = [
      'Pycnonotus sinensis',
      'Cuculus canorus',
      'Urocissa erythroryncha',
      'Passer montanus',
      'Horornis fortipes',
      'Copsychus saularis',
      'Turdus mandarinus',
      'Pica serica',
      'Spilopelia chinensis',
      'Lanius schach',
      'Abroscopus albogularis',
      'Mecopoda elongata',
      'Cryptotympana atrata',
      'Teleogryllus emma',
      'Streeyola mongolica',
      'Velarifictorus micado',
      'Pelophylax nigromaculatus',
      'Nidirana mangveni',
      'Microhyla fissipes',
      'Fejervarya multistriata',
    ];

    final assetPaths = <String>{};
    for (final scientificName in officialScientificNames) {
      final media = SpeciesMediaCatalog.lookup(scientificName);
      expect(media, isNotNull, reason: scientificName);
      assetPaths.add(media!.assetPath);
      final bytes = await rootBundle.load(media.assetPath);
      expect(bytes.lengthInBytes, greaterThan(0), reason: scientificName);
    }
    expect(assetPaths, hasLength(20));
  });

  test('supports the BirdNET synonym for spotted dove', () {
    final currentName = SpeciesMediaCatalog.lookup('Spilopelia chinensis');
    final birdNetName = SpeciesMediaCatalog.lookup('Streptopelia chinensis');

    expect(birdNetName?.assetPath, currentName?.assetPath);
  });
}
