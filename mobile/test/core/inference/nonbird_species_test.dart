import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/inference/nonbird_species.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses installed non-bird model metadata', () {
    final catalog = NonBirdModelCatalog.fromJson('''
      {
        "id":"hangzhou-nonbird",
        "version":"0.1.0",
        "available":true,
        "input":{"type":"birdnet_embedding","shape":[1,1024]},
        "birdnet_embedding_tensor_index":545,
        "birdnet_embedding_tensor_name":"model/GLOBAL_AVG_POOL/Mean",
        "classes":[{
          "output_index":0,
          "taxon_id":"cryptotympana_atrata",
          "category_id":"insect",
          "name_zh":"黑蚱蝉",
          "scientific_name":"Cryptotympana atrata",
          "threshold":0.62,
          "centroid":[1,0],
          "min_cosine_similarity":0.2
        }]
      }
    ''');
    expect(catalog.available, isTrue);
    expect(catalog.embeddingTensorIndex, 545);
    expect(catalog.rejection.minSupportingWindows, 2);
    expect(catalog.species.single.centroid, [1, 0]);
    expect(catalog.species.single.nameZh, '黑蚱蝉');
  });

  test('accepts the checked-in unavailable model descriptor', () {
    final catalog = NonBirdModelCatalog.fromJson('''
      {
        "id":"hangzhou-nonbird",
        "version":"0.1.0",
        "available":false,
        "input":{"type":"birdnet_embedding","shape":[1,1024]},
        "classes":[]
      }
    ''');
    expect(catalog.available, isFalse);
    expect(catalog.species, isEmpty);
  });

  test('requires an extra runner-up margin for exact species', () {
    const exact = NonBirdSpecies(
      outputIndex: 0,
      taxonId: 'nidirana_mangveni',
      categoryId: 'frog',
      nameZh: '孟闻琴蛙',
      scientificName: 'Nidirana mangveni',
      threshold: 0.2,
      centroid: [],
      minCosineSimilarity: -1,
    );
    const generic = NonBirdSpecies(
      outputIndex: 1,
      taxonId: 'other_frog',
      categoryId: 'frog',
      nameZh: '其他蛙类',
      threshold: 0.3,
      centroid: [],
      minCosineSimilarity: -1,
    );
    const policy = NonBirdRejectionPolicy(minTopMargin: 0.02);

    expect(requiredNonBirdTopMargin(exact, policy), 0.08);
    expect(requiredNonBirdTopMargin(generic, policy), 0.02);
  });

  test('ships the challenge demo twelve-class model', () async {
    final catalog = NonBirdModelCatalog.fromJson(
      await rootBundle.loadString('assets/models/nonbird.json'),
    );
    expect(catalog.available, isTrue);
    expect(catalog.version, '0.1.0-reference');
    expect(catalog.species, hasLength(12));
    expect(
      catalog.species.map((item) => item.taxonId),
      containsAll([
        'cryptotympana_atrata',
        'mecopoda_elongata',
        'teleogryllus_emma',
        'pelophylax_nigromaculatus',
        'nidirana_mangveni',
        'microhyla_fissipes',
        'fejervarya_multistriata',
        'streeyola_mongolica',
        'velarifictorus_micado',
        'other_insect',
        'other_frog',
        'background',
      ]),
    );
    expect(
      catalog.species
          .firstWhere((item) => item.taxonId == 'microhyla_fissipes')
          .nameZh,
      '饰纹姬蛙',
    );
  });
}
