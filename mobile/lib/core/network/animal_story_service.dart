import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nature_sound_detective/core/models/detection.dart';
import 'package:nature_sound_detective/core/models/field_observation_schema.dart';

class AnimalStory {
  const AnimalStory({
    required this.title,
    required this.story,
    required this.observationPrompt,
    required this.notice,
  });
  final String title;
  final String story;
  final String observationPrompt;
  final String notice;
}

class AnimalStoryService {
  AnimalStoryService({Uri? baseUri, http.Client? client})
      : baseUri = baseUri ?? Uri.parse(_defaultBaseUrl),
        _client = client ?? http.Client();

  static const _configuredBaseUrl = String.fromEnvironment('COMMUNITY_API_URL');
  static String get _defaultBaseUrl => _configuredBaseUrl.isNotEmpty
      ? _configuredBaseUrl
      : kReleaseMode
          ? 'https://listen-api.gqy20.top'
          : 'http://10.0.2.2:8770';

  final Uri baseUri;
  final http.Client _client;

  Future<AnimalStory> create({
    required SoundDetection detection,
    required Map<String, List<String>> selections,
    required FieldObservationSchema schema,
    String location = '杭州',
  }) async {
    final species = detection.specificSpecies;
    final candidateId = species?.taxonomyId ?? species?.scientificName ?? species?.nameZh ?? 'category:${detection.categoryId}';
    final labels = {
      for (final dimension in schema.dimensions)
        dimension.id: {for (final option in dimension.options) option.value: option.label},
    };
    final observations = <Map<String, Object?>>[];
    for (final entry in selections.entries) {
      for (final value in entry.value) {
        observations.add({
          'dimension': entry.key,
          'value': value,
          'label': labels[entry.key]?[value] ?? value,
          'candidate_id': candidateId,
          'source': 'flutter',
        });
      }
    }
    final result = {
      'primary_sound_type': detection.nameZh,
      'detections': [detection.toJson()],
    };
    final investigation = {
      'status': 'completed',
      'observations': observations,
    };
    final response = await _client.post(
      baseUri.resolve('/api/stories'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'result': result,
        'candidate_id': candidateId,
        'story_type': 'animal_life',
        'location': location,
        'investigation': investigation,
      }),
    ).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('动物故事暂时没有生成（${response.statusCode}）');
    }
    final value = jsonDecode(response.body) as Map<String, Object?>;
    return AnimalStory(
      title: value['title'] as String? ?? '候选动物故事',
      story: value['story'] as String? ?? '',
      observationPrompt: value['observation_prompt'] as String? ?? '',
      notice: value['candidate_notice'] as String? ?? 'AI创作，不代表物种确认。',
    );
  }
}
