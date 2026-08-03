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
          "threshold":0.62
        }]
      }
    ''');
    expect(catalog.available, isTrue);
    expect(catalog.embeddingTensorIndex, 545);
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

  test('ships the source-curated five-class model', () async {
    final catalog = NonBirdModelCatalog.fromJson(
      await rootBundle.loadString('assets/models/nonbird.json'),
    );
    expect(catalog.available, isTrue);
    expect(catalog.species, hasLength(5));
    expect(
      catalog.species.map((item) => item.taxonId),
      containsAll([
        'cryptotympana_atrata',
        'polypedates_braueri',
        'other_insect',
        'other_frog',
        'background',
      ]),
    );
  });
}
