import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/inference/birdnet_species.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses a species catalog', () {
    final catalog = BirdnetSpeciesCatalog.fromJson('''
      {"species":[{
        "output_index":5746,
        "scientific_name":"Streptopelia chinensis",
        "name_zh":"珠颈斑鸠",
        "name_en":"Spotted Dove",
        "geo_score":0.99
      }]}
    ''');

    expect(catalog.species, hasLength(1));
    expect(catalog.species.single.outputIndex, 5746);
    expect(catalog.species.single.nameZh, '珠颈斑鸠');
    expect(catalog.species.single.geoScore, 0.99);
  });

  test('rejects duplicate output indices', () {
    expect(
      () => BirdnetSpeciesCatalog.fromJson('''
        {"species":[
          {"output_index":1,"scientific_name":"A","name_zh":"A","name_en":"A","geo_score":0.9},
          {"output_index":1,"scientific_name":"B","name_zh":"B","name_en":"B","geo_score":0.8}
        ]}
      '''),
      throwsFormatException,
    );
  });

  test(
    'ships 200 unique Hangzhou candidates including the verified six',
    () async {
      final source = await rootBundle.loadString(
        'assets/labels/birdnet_hz.json',
      );
      final species = BirdnetSpeciesCatalog.fromJson(source).species;

      expect(species, hasLength(200));
      expect(species.map((item) => item.outputIndex).toSet(), hasLength(200));
      expect(
        species
            .where(
              (item) => const {
                1550,
                2420,
                5149,
                5746,
                6250,
                6329,
              }.contains(item.outputIndex),
            )
            .map((item) => item.outputIndex)
            .toSet(),
        {1550, 2420, 5149, 5746, 6250, 6329},
      );
    },
  );
}
