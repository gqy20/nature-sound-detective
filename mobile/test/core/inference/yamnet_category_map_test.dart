import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/inference/yamnet_category_map.dart';

void main() {
  test('parses quoted AudioSet labels without splitting embedded commas', () {
    const csv =
        'index,mid,display_name\n'
        '106,/m/015p6,Bird\n'
        '107,/m/020bb7,"Bird vocalization, bird call, bird song"\n'
        '127,/m/09ld4,Frog\n';

    final indices = YamnetLabelMap.fromCsv(csv).indicesByCategory();

    expect(indices['bird'], [106, 107]);
    expect(indices['frog'], [127]);
  });
}
