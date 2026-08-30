import 'dart:convert';
import 'dart:io';

import 'package:nature_sound_detective/core/models/animal_story.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:path_provider/path_provider.dart';

abstract interface class AnimalStoryStore {
  Future<AnimalStory?> load(String key);

  Future<void> save(String key, AnimalStory story);
}

class FileAnimalStoryStore implements AnimalStoryStore {
  FileAnimalStoryStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;

  static String keyFor(
    SoundDetection detection,
    Map<String, List<String>> selections,
  ) {
    final species = detection.specificSpecies;
    final candidateId =
        species?.taxonomyId ??
        species?.scientificName ??
        species?.nameZh ??
        'category:${detection.categoryId}';
    final dimensions = selections.keys.toList()..sort();
    final normalized = <String, List<String>>{
      for (final dimension in dimensions)
        dimension: [...selections[dimension] ?? const <String>[]]..sort(),
    };
    return '$candidateId|${jsonEncode(normalized)}';
  }

  @override
  Future<AnimalStory?> load(String key) async {
    final entries = await _readEntries();
    final value = entries[key];
    if (value is Map<String, Object?>) return AnimalStory.fromJson(value);
    if (value is Map<Object?, Object?>) {
      return AnimalStory.fromJson(value.cast<String, Object?>());
    }
    return null;
  }

  @override
  Future<void> save(String key, AnimalStory story) async {
    final file = await _file();
    final entries = await _readEntries();
    entries[key] = story.toJson();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(entries), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<Map<String, Object?>> _readEntries() async {
    final file = await _file();
    if (!await file.exists()) return <String, Object?>{};
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is Map<String, Object?>) return {...value};
      if (value is Map<Object?, Object?>) {
        return value.cast<String, Object?>();
      }
    } on FormatException {
      // A damaged cache must not prevent the species detail page from opening.
    }
    return <String, Object?>{};
  }

  Future<File> _file() async {
    final directory = await _directoryProvider();
    final stories = Directory(
      '${directory.path}${Platform.pathSeparator}animal_stories',
    );
    await stories.create(recursive: true);
    return File('${stories.path}${Platform.pathSeparator}stories.json');
  }
}
