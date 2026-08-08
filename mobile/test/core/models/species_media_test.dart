import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/models/species_media.dart';

void main() {
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
}
