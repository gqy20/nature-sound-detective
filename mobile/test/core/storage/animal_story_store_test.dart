import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/models/animal_story.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/storage/animal_story_store.dart';

void main() {
  test('saves and restores a story for normalized observations', () async {
    final directory = await Directory.systemTemp.createTemp('animal-story-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileAnimalStoryStore(
      directoryProvider: () async => directory,
    );
    const detection = SoundDetection(
      categoryId: 'bird',
      nameZh: '鸟类鸣叫',
      confidence: 0.7,
      model: 'test',
      specificSpecies: SpeciesCandidate(
        nameZh: '白头鹎',
        scientificName: 'Pycnonotus sinensis',
      ),
    );
    final firstKey = FileAnimalStoryStore.keyFor(detection, const {
      'sound_pattern': ['repeated', 'single_direction'],
      'time': ['early_morning'],
    });
    final reorderedKey = FileAnimalStoryStore.keyFor(detection, const {
      'time': ['early_morning'],
      'sound_pattern': ['single_direction', 'repeated'],
    });
    const story = AnimalStory(
      title: '树冠上的线索',
      story: '清晨的声音故事',
      observationPrompt: '下次记录方向',
      notice: '候选动物提示',
    );

    expect(firstKey, reorderedKey);
    await store.save(firstKey, story);
    final restored = await store.load(reorderedKey);
    expect(restored?.title, story.title);
    expect(restored?.story, story.story);
  });

  test('damaged cache behaves as empty', () async {
    final directory = await Directory.systemTemp.createTemp('animal-story-');
    addTearDown(() => directory.delete(recursive: true));
    final cacheDirectory = Directory('${directory.path}/animal_stories');
    await cacheDirectory.create(recursive: true);
    await File('${cacheDirectory.path}/stories.json').writeAsString('{broken');
    final store = FileAnimalStoryStore(
      directoryProvider: () async => directory,
    );

    expect(await store.load('missing'), isNull);
  });
}
