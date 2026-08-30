import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/audio/audio_playback.dart';
import 'package:nature_sound_detective/core/models/animal_story.dart';
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/models/field_observation_schema.dart';
import 'package:nature_sound_detective/core/network/animal_story_service.dart';
import 'package:nature_sound_detective/core/storage/animal_story_store.dart';
import 'package:nature_sound_detective/features/species/species_detail_page.dart';

void main() {
  testWidgets('field checks, source and audio segment are interactive', (
    tester,
  ) async {
    final playback = _FakePlayback();
    var changedObservations = <String, List<String>>{};
    await tester.pumpWidget(
      MaterialApp(
        home: SpeciesDetailPage(
          audioPath: '/recordings/bird.wav',
          playback: playback,
          onObservationsChanged: (values) => changedObservations = values,
          detection: const SoundDetection(
            categoryId: 'bird',
            nameZh: '鸟类',
            confidence: 0.72,
            model: 'test',
            intervals: [DetectionInterval(startSeconds: 3, endSeconds: 12)],
            specificSpecies: SpeciesCandidate(
              nameZh: '白头鹎',
              scientificName: 'Pycnonotus sinensis',
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('白头鹎的参考照片'), findsOneWidget);
    expect(find.text('声音像 72%'), findsOneWidget);
    expect(find.text('科普卡'), findsOneWidget);

    await tester.tap(find.text('© CharlesLam · CC BY-SA 2.0'));
    await tester.pumpAndSettle();
    expect(find.text('照片来源'), findsOneWidget);
    expect(find.text('Wikimedia Commons'), findsOneWidget);
    await tester.tap(find.text('复制来源链接'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('3.0–12.0s'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_circle_outline_rounded));
    await tester.pump();
    expect(playback.segmentStart, const Duration(seconds: 3));
    expect(playback.segmentEnd, const Duration(seconds: 12));

    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('什么时候发现的？'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清晨'));
    await tester.tap(find.text('高处树冠'));
    await tester.tap(find.text('重复鸣叫'));
    await tester.pumpAndSettle();
    expect(find.text('观察线索已保存'), findsOneWidget);
    expect(find.text('完成现场观察'), findsNothing);
    expect(changedObservations, {
      'time': ['early_morning'],
      'habitat': ['tree_canopy'],
      'sound_pattern': ['repeated'],
    });
  });

  testWidgets('multiple intervals show a clear position', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SpeciesDetailPage(
          detection: SoundDetection(
            categoryId: 'bird',
            nameZh: '鸟类',
            confidence: 0.4,
            model: 'test',
            intervals: [
              DetectionInterval(startSeconds: 1, endSeconds: 2),
              DetectionInterval(startSeconds: 5, endSeconds: 7),
            ],
          ),
        ),
      ),
    );

    expect(find.text('1/2 · 1–2s'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline_rounded), findsNothing);
  });

  testWidgets('species without curated media keeps a visual fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SpeciesDetailPage(
          detection: SoundDetection(
            categoryId: 'bird',
            nameZh: '鸟类',
            confidence: 0.08,
            model: 'test',
            tentative: true,
            specificSpecies: SpeciesCandidate(
              nameZh: '暂未收录的鸟',
              scientificName: 'Unknown species',
            ),
          ),
        ),
      ),
    );

    expect(find.text('暂未收录的鸟'), findsOneWidget);
    expect(find.text('声音像 8% · 再听听'), findsOneWidget);
    expect(find.byIcon(Icons.flight_rounded), findsWidgets);
    expect(find.textContaining('Wikimedia'), findsNothing);
  });

  testWidgets('generated story has clear hierarchy and is restored locally', (
    tester,
  ) async {
    final generator = _FakeStoryGenerator();
    final store = _MemoryStoryStore();
    const detection = SoundDetection(
      categoryId: 'bird',
      nameZh: '鸟类鸣叫',
      confidence: 0.72,
      model: 'test',
      specificSpecies: SpeciesCandidate(
        nameZh: '白头鹎',
        scientificName: 'Pycnonotus sinensis',
      ),
    );
    const observations = {
      'time': ['early_morning'],
      'habitat': ['tree_canopy'],
      'sound_pattern': ['repeated'],
    };

    await tester.pumpWidget(
      MaterialApp(
        home: SpeciesDetailPage(
          detection: detection,
          initialObservations: observations,
          storyGenerator: generator,
          storyStore: store,
          observationSchema: _testObservationSchema,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('生成动物故事'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成动物故事'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('树冠上的线索'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('树冠上的线索'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(find.text('下一次探索任务'), findsOneWidget);
    expect(find.text('已保存到本机'), findsOneWidget);
    expect(find.text('换一个故事'), findsOneWidget);
    expect(generator.calls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: SpeciesDetailPage(
          detection: detection,
          initialObservations: observations,
          storyGenerator: generator,
          storyStore: store,
          observationSchema: _testObservationSchema,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('树冠上的线索'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('树冠上的线索'), findsOneWidget);
    expect(generator.calls, 1);
  });

  testWidgets('story failure stays visible beside the action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SpeciesDetailPage(
          detection: const SoundDetection(
            categoryId: 'frog',
            nameZh: '蛙类鸣叫',
            confidence: 0.5,
            model: 'test',
          ),
          initialObservations: const {
            'time': ['night'],
            'habitat': ['waterside'],
          },
          storyGenerator: _FailingStoryGenerator(),
          storyStore: _MemoryStoryStore(),
          observationSchema: _testObservationSchema,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('生成动物故事'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成动物故事'));
    await tester.pumpAndSettle();
    expect(find.text('故事还没有准备好，可以稍后再试。'), findsOneWidget);
  });
}

const _testObservationSchema = FieldObservationSchema(
  version: 1,
  minimumMeaningfulDimensions: 2,
  dimensions: [
    FieldObservationDimension(
      id: 'time',
      label: '什么时候发现的？',
      multiple: false,
      options: [
        FieldObservationOption(value: 'early_morning', label: '清晨'),
        FieldObservationOption(value: 'night', label: '夜间'),
      ],
    ),
    FieldObservationDimension(
      id: 'habitat',
      label: '它在哪里活动？',
      multiple: false,
      options: [
        FieldObservationOption(value: 'tree_canopy', label: '高处树冠'),
        FieldObservationOption(value: 'waterside', label: '水边'),
      ],
    ),
    FieldObservationDimension(
      id: 'sound_pattern',
      label: '声音有什么特点？',
      multiple: true,
      options: [FieldObservationOption(value: 'repeated', label: '重复鸣叫')],
    ),
  ],
);

class _FakePlayback implements AudioPlayback {
  final _controller = StreamController<bool>.broadcast();
  Duration? segmentStart;
  Duration? segmentEnd;

  @override
  Stream<bool> get playing => _controller.stream;

  @override
  Stream<Duration> get position => const Stream.empty();

  @override
  Future<void> play(String path) async {
    _controller.add(true);
  }

  @override
  Future<void> playSegment(
    String path, {
    required Duration start,
    required Duration end,
  }) async {
    segmentStart = start;
    segmentEnd = end;
    _controller.add(true);
  }

  @override
  Future<void> stop() async {
    if (!_controller.isClosed) _controller.add(false);
  }

  @override
  Future<void> dispose() => _controller.close();
}

class _FakeStoryGenerator implements AnimalStoryGenerator {
  int calls = 0;

  @override
  Future<AnimalStory> create({
    required SoundDetection detection,
    required Map<String, List<String>> selections,
    required FieldObservationSchema schema,
    String location = '杭州',
  }) async {
    calls += 1;
    return const AnimalStory(
      title: '树冠上的线索',
      story: '清晨，白头鹎候选者在高处树冠留下了重复鸣叫的线索。',
      observationPrompt: '下一次在远处记录声音的方向。',
      notice: '这是关于候选动物白头鹎的AI故事，不代表物种确认。',
    );
  }
}

class _FailingStoryGenerator implements AnimalStoryGenerator {
  @override
  Future<AnimalStory> create({
    required SoundDetection detection,
    required Map<String, List<String>> selections,
    required FieldObservationSchema schema,
    String location = '杭州',
  }) => Future.error(StateError('offline'));
}

class _MemoryStoryStore implements AnimalStoryStore {
  final values = <String, AnimalStory>{};

  @override
  Future<AnimalStory?> load(String key) async => values[key];

  @override
  Future<void> save(String key, AnimalStory story) async {
    values[key] = story;
  }
}
