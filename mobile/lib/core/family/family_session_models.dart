import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';

enum FamilyDeviceRole { parent, child }

enum FamilySessionStatus {
  waitingForChild,
  pendingApproval,
  active,
  ended,
  expired;

  static FamilySessionStatus parse(String? value) => switch (value) {
    'waiting_for_child' => waitingForChild,
    'pending_approval' => pendingApproval,
    'active' => active,
    'ended' => ended,
    'expired' => expired,
    _ => expired,
  };

  String get wireValue => switch (this) {
    waitingForChild => 'waiting_for_child',
    pendingApproval => 'pending_approval',
    active => 'active',
    ended => 'ended',
    expired => 'expired',
  };
}

class FamilySessionConnection {
  const FamilySessionConnection({
    required this.sessionId,
    required this.role,
    required this.status,
    required this.expiresAt,
    this.pairCode,
    this.pairExpiresAt,
    this.lastEventSequence = 0,
    this.lastCommandSequence = 0,
  });

  final String sessionId;
  final FamilyDeviceRole role;
  final FamilySessionStatus status;
  final DateTime expiresAt;
  final String? pairCode;
  final DateTime? pairExpiresAt;
  final int lastEventSequence;
  final int lastCommandSequence;

  bool get active => status == FamilySessionStatus.active;

  FamilySessionConnection copyWith({
    FamilySessionStatus? status,
    int? lastEventSequence,
    int? lastCommandSequence,
    String? pairCode,
    DateTime? pairExpiresAt,
  }) => FamilySessionConnection(
    sessionId: sessionId,
    role: role,
    status: status ?? this.status,
    expiresAt: expiresAt,
    pairCode: pairCode ?? this.pairCode,
    pairExpiresAt: pairExpiresAt ?? this.pairExpiresAt,
    lastEventSequence: lastEventSequence ?? this.lastEventSequence,
    lastCommandSequence: lastCommandSequence ?? this.lastCommandSequence,
  );

  factory FamilySessionConnection.fromJson(
    Map<String, Object?> json,
  ) => FamilySessionConnection(
    sessionId: json['session_id'] as String? ?? '',
    role: json['role'] == 'parent'
        ? FamilyDeviceRole.parent
        : FamilyDeviceRole.child,
    status: FamilySessionStatus.parse(json['status'] as String?),
    expiresAt:
        DateTime.tryParse(json['expires_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    pairCode: json['pair_code'] as String?,
    pairExpiresAt: DateTime.tryParse(json['pair_expires_at'] as String? ?? ''),
    lastEventSequence: (json['last_event_sequence'] as num?)?.toInt() ?? 0,
    lastCommandSequence: (json['last_command_sequence'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toJson() => {
    'session_id': sessionId,
    'role': role.name,
    'status': status.wireValue,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    if (pairCode != null) 'pair_code': pairCode,
    if (pairExpiresAt != null)
      'pair_expires_at': pairExpiresAt!.toUtc().toIso8601String(),
    'last_event_sequence': lastEventSequence,
    'last_command_sequence': lastCommandSequence,
  };
}

class FamilyExplorationEvent {
  const FamilyExplorationEvent({
    required this.eventId,
    required this.sequence,
    required this.type,
    required this.occurredAt,
    this.payload = const {},
  });

  final String eventId;
  final int sequence;
  final String type;
  final DateTime occurredAt;
  final Map<String, Object?> payload;

  factory FamilyExplorationEvent.fromJson(Map<String, Object?> json) =>
      FamilyExplorationEvent(
        eventId: json['event_id'] as String? ?? '',
        sequence: (json['sequence'] as num?)?.toInt() ?? 0,
        type: json['event_type'] as String? ?? '',
        occurredAt:
            DateTime.tryParse(json['occurred_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        payload: switch (json['payload']) {
          Map<Object?, Object?> value => value.cast<String, Object?>(),
          _ => const {},
        },
      );

  Map<String, Object?> toJson() => {
    'event_id': eventId,
    'sequence': sequence,
    'event_type': type,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'payload': payload,
  };
}

extension FamilyExplorationEventBehavior on FamilyExplorationEvent {
  ExplorationBehavior? get behavior => switch (type) {
    'captured_sound' => ExplorationBehavior.capturedSound,
    'imported_sound' => ExplorationBehavior.importedSound,
    'replayed_audio' => ExplorationBehavior.replayedAudio,
    'completed_observation' => ExplorationBehavior.completedObservation,
    'compared_evidence' => ExplorationBehavior.comparedEvidence,
    'accepted_uncertainty' => ExplorationBehavior.acceptedUncertainty,
    'retried_recording' => ExplorationBehavior.retriedRecording,
    'completed_safe_route_stop' => ExplorationBehavior.observedSafely,
    _ => null,
  };
}

class FamilyCommand {
  const FamilyCommand({
    required this.commandId,
    required this.templateId,
    required this.sequence,
    required this.createdAt,
  });

  final String commandId;
  final String templateId;
  final int sequence;
  final DateTime createdAt;

  factory FamilyCommand.fromJson(Map<String, Object?> json) => FamilyCommand(
    commandId: json['command_id'] as String? ?? '',
    templateId: json['template_id'] as String? ?? '',
    sequence: (json['sequence'] as num?)?.toInt() ?? 0,
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

class CompanionCue {
  const CompanionCue({
    required this.eventId,
    required this.behavior,
    required this.title,
    required this.say,
    required this.explanation,
    required this.priority,
  });

  final String eventId;
  final ExplorationBehavior behavior;
  final String title;
  final String say;
  final String explanation;
  final int priority;
}

class CompanionCueEngine {
  const CompanionCueEngine();

  CompanionCue? build(List<FamilyExplorationEvent> events) {
    final values = events
        .map(_fromEvent)
        .whereType<CompanionCue>()
        .toList(growable: false);
    if (values.isEmpty) return null;
    values.sort((left, right) {
      final priority = right.priority.compareTo(left.priority);
      if (priority != 0) return priority;
      final leftSequence = events
          .firstWhere((event) => event.eventId == left.eventId)
          .sequence;
      final rightSequence = events
          .firstWhere((event) => event.eventId == right.eventId)
          .sequence;
      return rightSequence.compareTo(leftSequence);
    });
    return values.first;
  }

  CompanionCue? _fromEvent(FamilyExplorationEvent event) =>
      switch (event.type) {
        'accepted_uncertainty' => CompanionCue(
          eventId: event.eventId,
          behavior: ExplorationBehavior.acceptedUncertainty,
          title: '孩子愿意保留不确定',
          say: '你愿意说暂时不知道，说明你很认真地对待证据。',
          explanation: '肯定诚实判断，而不是要求孩子必须选出答案。',
          priority: 100,
        ),
        'mission_completed' => CompanionCue(
          eventId: event.eventId,
          behavior: ExplorationBehavior.completedObservation,
          title: '孩子完成了共同任务',
          say: '你把刚才的任务认真做完了，还记得把结果告诉我。',
          explanation: '及时确认共同任务，帮助孩子感受到家长真的在参与。',
          priority: 95,
        ),
        'compared_evidence' => CompanionCue(
          eventId: event.eventId,
          behavior: ExplorationBehavior.comparedEvidence,
          title: '孩子正在比较不同证据',
          say: '你把声音和周围环境放在一起比较，这是一种很好的调查方法。',
          explanation: '肯定推理过程，不把候选物种说成确定答案。',
          priority: 90,
        ),
        'retried_recording' => CompanionCue(
          eventId: event.eventId,
          behavior: ExplorationBehavior.retriedRecording,
          title: '孩子失败后又试了一次',
          say: '你愿意换个方法再试，说明你正在从刚才的经验里调整。',
          explanation: '把注意力放在调整策略，而不是一次录音是否成功。',
          priority: 80,
        ),
        'completed_safe_route_stop' => CompanionCue(
          eventId: event.eventId,
          behavior: ExplorationBehavior.observedSafely,
          title: '孩子完成了安全观察任务',
          say: '你留在步道上安静观察，这是尊重自然的方式。',
          explanation: '强化安全边界和对自然的尊重。',
          priority: 75,
        ),
        'completed_observation' => CompanionCue(
          eventId: event.eventId,
          behavior: ExplorationBehavior.completedObservation,
          title: '孩子完成了现场观察',
          say: '你不只看候选，还回到现场找线索，观察得很完整。',
          explanation: '肯定观察过程，而不是判断是否正确。',
          priority: 65,
        ),
        'replayed_audio' => CompanionCue(
          eventId: event.eventId,
          behavior: ExplorationBehavior.replayedAudio,
          title: '孩子主动回听了声音',
          say: '你没有急着选答案，而是又认真听了一遍。',
          explanation: '肯定主动求证的行为。',
          priority: 55,
        ),
        'captured_sound' => CompanionCue(
          eventId: event.eventId,
          behavior: ExplorationBehavior.capturedSound,
          title: '孩子完成了一次现场录音',
          say: '你把刚才听见的声音保存下来，让发现有了可以回听的证据。',
          explanation: '把录音理解成留下证据，而不是完成任务打卡。',
          priority: 30,
        ),
        'mission_received' => CompanionCue(
          eventId: event.eventId,
          behavior: ExplorationBehavior.completedObservation,
          title: '孩子已经收到共同任务',
          say: '任务已经到你那里了，按自己的节奏慢慢找线索。',
          explanation: '确认任务送达，不催促孩子立即完成。',
          priority: 25,
        ),
        _ => null,
      };
}

const familyMissionLabels = <String, String>{
  'compare_high_low_sound': '比较高处和低处的声音',
  'listen_again_before_guessing': '猜测前再认真听一次',
  'compare_sound_and_habitat': '比较声音和周围生境',
  'keep_a_safe_distance': '留在步道并保持安全距离',
  'allow_not_knowing': '允许保留“暂时不知道”',
};
