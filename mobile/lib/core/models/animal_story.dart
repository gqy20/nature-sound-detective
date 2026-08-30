class AnimalStory {
  const AnimalStory({
    required this.title,
    required this.story,
    required this.observationPrompt,
    required this.notice,
    this.contentLabel = 'AI基于候选信息创作',
    this.warning = '',
    this.provider,
    this.generatedAt,
  });

  factory AnimalStory.fromJson(Map<String, Object?> json) => AnimalStory(
    title: _plainText(json['title'], fallback: '候选动物故事'),
    story: _plainText(json['story']),
    observationPrompt: _plainText(json['observation_prompt']),
    notice: _plainText(json['candidate_notice'], fallback: 'AI创作，不代表物种确认。'),
    contentLabel: _plainText(json['content_label'], fallback: 'AI基于候选信息创作'),
    warning: _plainText(json['warning']),
    provider: switch (json['provider']) {
      final String value when value.trim().isNotEmpty => value.trim(),
      _ => null,
    },
    generatedAt: switch (json['generated_at']) {
      final String value => DateTime.tryParse(value),
      _ => null,
    },
  );

  final String title;
  final String story;
  final String observationPrompt;
  final String notice;
  final String contentLabel;
  final String warning;
  final String? provider;
  final DateTime? generatedAt;

  bool get usedSafetyTemplate =>
      provider == 'reviewed-template' || warning.trim().isNotEmpty;

  Map<String, Object?> toJson() => {
    'title': title,
    'story': story,
    'observation_prompt': observationPrompt,
    'candidate_notice': notice,
    'content_label': contentLabel,
    if (warning.isNotEmpty) 'warning': warning,
    if (provider != null) 'provider': provider,
    if (generatedAt != null) 'generated_at': generatedAt!.toIso8601String(),
  };
}

String _plainText(Object? value, {String fallback = ''}) {
  final text = value is String ? value.trim() : '';
  if (text.isEmpty) return fallback;
  return text
      .replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '')
      .replaceAll(RegExp(r'\*\*|__|`'), '')
      .replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '')
      .trim();
}
