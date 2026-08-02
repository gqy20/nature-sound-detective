import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/network/cloud_content_service.dart';

void main() {
  test('parses the existing Vercel response contract', () {
    final card = CloudSoundCard.fromJson({
      'result': {
        'uncertainty': '无法确认具体物种',
        'card': {
          'title': '树梢传来的歌声',
          'explanation': '这段录音里有鸟类鸣叫的线索。',
          'question': '声音重复了几次？',
          'safety_note': '请站在步道上观察。',
        },
      },
    });

    expect(card.title, '树梢传来的歌声');
    expect(card.question, '声音重复了几次？');
    expect(card.uncertainty, '无法确认具体物种');
  });
}
