import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/ai/generated_prompts.dart';

void main() {
  test('renders the mobile creation prompt from the generated catalog', () {
    final prompt = AiPromptCatalog.render('creation.mobile_video_bird', const {
      'location': '杭州',
      'subject': '树麻雀',
    });

    expect(prompt, contains('树麻雀'));
    expect(prompt, contains('生成一支5秒'));
    expect(prompt, contains('单镜头'));
    expect(prompt, contains('杭州'));
    expect(prompt, isNot(contains('{{')));
    expect(AiPromptCatalog.version('creation'), 'creation-v3');
  });

  test('rejects missing or extra prompt variables', () {
    expect(
      () => AiPromptCatalog.render('creation.mobile_video_bird', const {
        'location': '杭州',
      }),
      throwsArgumentError,
    );
  });

  test('provides frog, environment and anatomy safety templates', () {
    final frog = AiPromptCatalog.render('creation.mobile_video_frog', const {
      'location': '杭州',
      'subject': '黑斑侧褶蛙',
    });
    final referencedFrog = AiPromptCatalog.render(
      'creation.mobile_video_frog_reference',
      const {'location': '杭州', 'subject': '黑斑侧褶蛙'},
    );
    final environment = AiPromptCatalog.render(
      'creation.mobile_video_environment',
      const {'location': '杭州'},
    );
    final negative = AiPromptCatalog.render(
      'creation.mobile_video_negative',
      const {},
    );

    expect(frog, contains('黑斑侧褶蛙'));
    expect(frog, contains('浅水边'));
    expect(frog, contains('无跳跃'));
    expect(referencedFrog, contains('图片1'));
    expect(referencedFrog, contains('黑斑侧褶蛙'));
    expect(environment, contains('没有可见动物'));
    expect(negative, contains('额外肢体'));
    expect(negative, contains('身体闪烁'));
  });
}
