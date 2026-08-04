enum CreationStage {
  idle,
  generatingMusic,
  generatingNarration,
  submittingVideo,
  waitingForVideo,
  downloadingVideo,
  composing,
  completed,
  partial,
  failed,
}

class CreationSettings {
  const CreationSettings({
    this.minimaxApiKey = '',
    this.minimaxMusicModel = 'music-2.6',
    this.minimaxSpeechModel = 'speech-2.8-hd',
    this.minimaxSpeechVoice = 'female-tianmei',
    this.dashscopeApiKey = '',
    this.dashscopeWorkspaceId = '',
    this.dashscopeRegion = 'beijing',
    this.wanVideoModel = 'wan2.7-t2v',
  });

  factory CreationSettings.fromJson(Map<String, Object?> json) {
    return CreationSettings(
      minimaxApiKey: json['minimax_api_key'] as String? ?? '',
      minimaxMusicModel: json['minimax_music_model'] as String? ?? 'music-2.6',
      minimaxSpeechModel:
          json['minimax_speech_model'] as String? ?? 'speech-2.8-hd',
      minimaxSpeechVoice:
          json['minimax_speech_voice'] as String? ?? 'female-tianmei',
      dashscopeApiKey: json['dashscope_api_key'] as String? ?? '',
      dashscopeWorkspaceId: json['dashscope_workspace_id'] as String? ?? '',
      dashscopeRegion: json['dashscope_region'] as String? ?? 'beijing',
      wanVideoModel: json['wan_video_model'] as String? ?? 'wan2.7-t2v',
    );
  }

  final String minimaxApiKey;
  final String minimaxMusicModel;
  final String minimaxSpeechModel;
  final String minimaxSpeechVoice;
  final String dashscopeApiKey;
  final String dashscopeWorkspaceId;
  final String dashscopeRegion;
  final String wanVideoModel;

  bool get hasMusic => minimaxApiKey.trim().isNotEmpty;
  bool get hasVideo => dashscopeApiKey.trim().isNotEmpty;
  bool get canCreate => hasMusic && hasVideo;

  String get dashscopeBaseUrl {
    final workspace = dashscopeWorkspaceId.trim();
    if (dashscopeRegion == 'singapore') {
      return workspace.isEmpty
          ? 'https://dashscope-intl.aliyuncs.com'
          : 'https://$workspace.ap-southeast-1.maas.aliyuncs.com';
    }
    return workspace.isEmpty
        ? 'https://dashscope.aliyuncs.com'
        : 'https://$workspace.cn-beijing.maas.aliyuncs.com';
  }

  Map<String, Object?> toJson() => {
    'minimax_api_key': minimaxApiKey.trim(),
    'minimax_music_model': minimaxMusicModel.trim(),
    'minimax_speech_model': minimaxSpeechModel.trim(),
    'minimax_speech_voice': minimaxSpeechVoice.trim(),
    'dashscope_api_key': dashscopeApiKey.trim(),
    'dashscope_workspace_id': dashscopeWorkspaceId.trim(),
    'dashscope_region': dashscopeRegion,
    'wan_video_model': wanVideoModel.trim(),
  };
}

class CreationUpdate {
  const CreationUpdate({
    required this.stage,
    required this.message,
    this.taskId = '',
    this.recordId = '',
    this.directoryPath = '',
  });

  final CreationStage stage;
  final String message;
  final String taskId;
  final String recordId;
  final String directoryPath;
}

class CreationArtifacts {
  const CreationArtifacts({
    required this.id,
    required this.directoryPath,
    this.musicPath,
    this.narrationPath,
    this.videoPath,
    this.finalVideoPath,
    this.musicError,
    this.videoError,
    this.wanTaskId = '',
  });

  final String id;
  final String directoryPath;
  final String? musicPath;
  final String? narrationPath;
  final String? videoPath;
  final String? finalVideoPath;
  final String? musicError;
  final String? videoError;
  final String wanTaskId;

  bool get hasMusic => musicPath != null;
  bool get hasVideo => videoPath != null;
  bool get hasFinalVideo => finalVideoPath != null;
  bool get isComplete => hasMusic && hasVideo && hasFinalVideo;
}

class CreationRecord {
  const CreationRecord({
    required this.id,
    required this.subject,
    required this.location,
    required this.createdAt,
    required this.updatedAt,
    required this.stage,
    required this.message,
    required this.directoryPath,
    required this.sourceAudioPath,
    this.musicPath = '',
    this.narrationPath = '',
    this.videoPath = '',
    this.finalVideoPath = '',
    this.wanTaskId = '',
    this.musicError = '',
    this.videoError = '',
    this.compositionError = '',
  });

  factory CreationRecord.fromJson(Map<String, Object?> json) {
    final stageName = json['stage'] as String? ?? CreationStage.idle.name;
    return CreationRecord(
      id: json['id'] as String? ?? '',
      subject: json['subject'] as String? ?? '自然环境声',
      location: json['location'] as String? ?? '杭州',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      stage: CreationStage.values.firstWhere(
        (value) => value.name == stageName,
        orElse: () => CreationStage.failed,
      ),
      message: json['message'] as String? ?? '',
      directoryPath: json['directory_path'] as String? ?? '',
      sourceAudioPath: json['source_audio_path'] as String? ?? '',
      musicPath: json['music_path'] as String? ?? '',
      narrationPath: json['narration_path'] as String? ?? '',
      videoPath: json['video_path'] as String? ?? '',
      finalVideoPath: json['final_video_path'] as String? ?? '',
      wanTaskId: json['wan_task_id'] as String? ?? '',
      musicError: json['music_error'] as String? ?? '',
      videoError: json['video_error'] as String? ?? '',
      compositionError: json['composition_error'] as String? ?? '',
    );
  }

  final String id;
  final String subject;
  final String location;
  final DateTime createdAt;
  final DateTime updatedAt;
  final CreationStage stage;
  final String message;
  final String directoryPath;
  final String sourceAudioPath;
  final String musicPath;
  final String narrationPath;
  final String videoPath;
  final String finalVideoPath;
  final String wanTaskId;
  final String musicError;
  final String videoError;
  final String compositionError;

  bool get canResume =>
      !{CreationStage.completed, CreationStage.failed}.contains(stage) ||
      (wanTaskId.isNotEmpty && videoPath.isEmpty);

  bool get isComplete =>
      stage == CreationStage.completed && finalVideoPath.isNotEmpty;

  CreationRecord copyWith({
    CreationStage? stage,
    String? message,
    String? musicPath,
    String? narrationPath,
    String? videoPath,
    String? finalVideoPath,
    String? wanTaskId,
    String? musicError,
    String? videoError,
    String? compositionError,
  }) => CreationRecord(
    id: id,
    subject: subject,
    location: location,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    stage: stage ?? this.stage,
    message: message ?? this.message,
    directoryPath: directoryPath,
    sourceAudioPath: sourceAudioPath,
    musicPath: musicPath ?? this.musicPath,
    narrationPath: narrationPath ?? this.narrationPath,
    videoPath: videoPath ?? this.videoPath,
    finalVideoPath: finalVideoPath ?? this.finalVideoPath,
    wanTaskId: wanTaskId ?? this.wanTaskId,
    musicError: musicError ?? this.musicError,
    videoError: videoError ?? this.videoError,
    compositionError: compositionError ?? this.compositionError,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'subject': subject,
    'location': location,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'stage': stage.name,
    'message': message,
    'directory_path': directoryPath,
    'source_audio_path': sourceAudioPath,
    'music_path': musicPath,
    'narration_path': narrationPath,
    'video_path': videoPath,
    'final_video_path': finalVideoPath,
    'wan_task_id': wanTaskId,
    'music_error': musicError,
    'video_error': videoError,
    'composition_error': compositionError,
  };
}
