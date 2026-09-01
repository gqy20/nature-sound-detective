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

enum CreationVisualMode { bird, frog, environment }

const funMusicApplicationUrl =
    'https://bailian.console.aliyun.com/cn-beijing/?tab=model';
const funMusicPermissionDeniedMessage =
    '当前 API Key 未获得 Fun-Music 邀测权限，本次已跳过音乐生成。'
    '请前往阿里云百炼模型广场申请开通：$funMusicApplicationUrl';

bool isFunMusicPermissionDenied(String? message) =>
    message?.contains('Fun-Music 邀测权限') ?? false;

class CreationSettings {
  const CreationSettings({
    this.dashscopeApiKey = '',
    this.dashscopeWorkspaceId = '',
    this.dashscopeMusicModel = 'fun-music-v1',
    this.dashscopeSpeechModel = 'qwen-audio-3.0-tts-plus',
    this.dashscopeSpeechVoice = 'longanlingxin',
    this.wanVideoModel = 'wan3.0-video',
  });

  factory CreationSettings.fromJson(Map<String, Object?> json) {
    return CreationSettings(
      dashscopeApiKey: json['dashscope_api_key'] as String? ?? '',
      dashscopeWorkspaceId: json['dashscope_workspace_id'] as String? ?? '',
      dashscopeMusicModel:
          json['dashscope_music_model'] as String? ?? 'fun-music-v1',
      dashscopeSpeechModel:
          json['dashscope_speech_model'] as String? ??
          'qwen-audio-3.0-tts-plus',
      dashscopeSpeechVoice:
          json['dashscope_speech_voice'] as String? ?? 'longanlingxin',
      wanVideoModel: switch (json['wan_video_model'] as String?) {
        null || '' || 'wan2.7-t2v' => 'wan3.0-video',
        final value => value,
      },
    );
  }

  final String dashscopeApiKey;
  final String dashscopeWorkspaceId;
  final String dashscopeMusicModel;
  final String dashscopeSpeechModel;
  final String dashscopeSpeechVoice;
  final String wanVideoModel;

  bool get hasDashscopeKey => dashscopeApiKey.trim().isNotEmpty;
  bool get hasMusic => hasDashscopeKey;
  bool get hasNarration => hasDashscopeKey;
  bool get hasVideo => hasDashscopeKey;
  bool get canCreate => hasDashscopeKey;

  String get dashscopeBaseUrl {
    final workspace = dashscopeWorkspaceId.trim();
    return workspace.isEmpty
        ? 'https://dashscope.aliyuncs.com'
        : 'https://$workspace.cn-beijing.maas.aliyuncs.com';
  }

  Map<String, Object?> toJson() => {
    'dashscope_api_key': dashscopeApiKey.trim(),
    'dashscope_workspace_id': dashscopeWorkspaceId.trim(),
    'dashscope_music_model': dashscopeMusicModel.trim(),
    'dashscope_speech_model': dashscopeSpeechModel.trim(),
    'dashscope_speech_voice': dashscopeSpeechVoice.trim(),
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
  bool get isComplete => hasVideo && hasFinalVideo;
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
    this.visualMode = CreationVisualMode.environment,
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
    final visualModeName =
        json['visual_mode'] as String? ?? CreationVisualMode.environment.name;
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
      visualMode: CreationVisualMode.values.firstWhere(
        (value) => value.name == visualModeName,
        orElse: () => CreationVisualMode.environment,
      ),
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
  final CreationVisualMode visualMode;
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
    CreationVisualMode? visualMode,
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
    visualMode: visualMode ?? this.visualMode,
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
    'visual_mode': visualMode.name,
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
