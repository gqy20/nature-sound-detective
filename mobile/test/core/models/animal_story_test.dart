import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/models/animal_story.dart';

void main() {
  test('removes model markdown and keeps generation metadata', () {
    final story = AnimalStory.fromJson({
      'title': '**树冠上的线索**',
      'story': '清晨，**白头鹎**留下了一段声音。',
      'observation_prompt': '记下__声音方向__。',
      'candidate_notice': 'AI创作，不代表物种确认。',
      'content_label': 'AI基于候选信息创作',
      'provider': 'qwen3.7-flash',
      'generated_at': '2026-08-29T10:00:00Z',
    });

    expect(story.title, '树冠上的线索');
    expect(story.story, '清晨，白头鹎留下了一段声音。');
    expect(story.observationPrompt, '记下声音方向。');
    expect(story.usedSafetyTemplate, isFalse);
    expect(story.generatedAt, DateTime.utc(2026, 8, 29, 10));
  });

  test('marks a reviewed fallback as a safety template', () {
    final story = AnimalStory.fromJson({
      'title': '安全故事',
      'story': '一段故事',
      'observation_prompt': '远处观察',
      'candidate_notice': '候选提示',
      'provider': 'reviewed-template',
      'warning': '已使用安全模板',
    });

    expect(story.usedSafetyTemplate, isTrue);
  });
}
