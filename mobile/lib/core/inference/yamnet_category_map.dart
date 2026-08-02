class YamnetCategory {
  const YamnetCategory({
    required this.id,
    required this.nameZh,
    required this.labels,
    required this.threshold,
  });

  final String id;
  final String nameZh;
  final Set<String> labels;
  final double threshold;
}

const yamnetNatureCategories = <YamnetCategory>[
  YamnetCategory(
    id: 'bird',
    nameZh: '鸟类鸣叫',
    threshold: 0.20,
    labels: {
      'Bird',
      'Bird vocalization, bird call, bird song',
      'Chirp, tweet',
      'Squawk',
      'Pigeon, dove',
      'Crow',
      'Owl',
      'Gull, seagull',
    },
  ),
  YamnetCategory(id: 'frog', nameZh: '蛙类鸣叫', threshold: 0.15, labels: {'Frog'}),
  YamnetCategory(
    id: 'insect',
    nameZh: '昆虫鸣叫',
    threshold: 0.18,
    labels: {
      'Insect',
      'Cricket',
      'Mosquito',
      'Fly, housefly',
      'Bee, wasp, etc.',
    },
  ),
  YamnetCategory(
    id: 'rain',
    nameZh: '雨水',
    threshold: 0.18,
    labels: {'Rain', 'Raindrop', 'Rain on surface'},
  ),
  YamnetCategory(
    id: 'running_water',
    nameZh: '流水',
    threshold: 0.18,
    labels: {'Water', 'Stream', 'Waterfall', 'Gurgling'},
  ),
  YamnetCategory(
    id: 'wind',
    nameZh: '风和树叶',
    threshold: 0.18,
    labels: {'Wind', 'Rustling leaves', 'Wind noise (microphone)', 'Rustle'},
  ),
  YamnetCategory(
    id: 'speech',
    nameZh: '人声',
    threshold: 0.25,
    labels: {
      'Speech',
      'Child speech, kid speaking',
      'Conversation',
      'Narration, monologue',
      'Hubbub, speech noise, speech babble',
    },
  ),
  YamnetCategory(
    id: 'footsteps',
    nameZh: '脚步',
    threshold: 0.20,
    labels: {'Walk, footsteps', 'Run'},
  ),
  YamnetCategory(
    id: 'traffic_machine',
    nameZh: '交通或机械噪声',
    threshold: 0.22,
    labels: {
      'Vehicle',
      'Motor vehicle (road)',
      'Car',
      'Bus',
      'Truck',
      'Motorcycle',
      'Traffic noise, roadway noise',
      'Train',
      'Aircraft',
      'Engine',
      'Tools',
      'Power tool',
    },
  ),
];

class YamnetLabelMap {
  const YamnetLabelMap(this.labelsByIndex);

  factory YamnetLabelMap.fromCsv(String csv) {
    final labels = <int, String>{};
    for (final line in csv.split(RegExp(r'\r?\n')).skip(1)) {
      if (line.trim().isEmpty) continue;
      final fields = _parseCsvLine(line);
      if (fields.length >= 3) {
        final index = int.tryParse(fields[0]);
        if (index != null) labels[index] = fields[2];
      }
    }
    return YamnetLabelMap(labels);
  }

  final Map<int, String> labelsByIndex;

  Map<String, List<int>> indicesByCategory() {
    return {
      for (final category in yamnetNatureCategories)
        category.id: labelsByIndex.entries
            .where((entry) => category.labels.contains(entry.value))
            .map((entry) => entry.key)
            .toList(growable: false),
    };
  }
}

List<String> _parseCsvLine(String line) {
  final fields = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (var index = 0; index < line.length; index++) {
    final character = line[index];
    if (character == '"') {
      if (quoted && index + 1 < line.length && line[index + 1] == '"') {
        buffer.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (character == ',' && !quoted) {
      fields.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(character);
    }
  }
  fields.add(buffer.toString());
  return fields;
}
