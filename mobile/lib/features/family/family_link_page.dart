import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/family/family_session_coordinator.dart';
import 'package:nature_sound_detective/core/family/family_session_models.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';
import 'package:nature_sound_detective/core/network/parent_guidance_service.dart';

class FamilyLinkPage extends StatefulWidget {
  const FamilyLinkPage({
    super.key,
    required this.coordinator,
    this.guidanceService,
    this.preferredRole,
  });

  final FamilySessionCoordinator coordinator;
  final ParentGuidanceNetworkService? guidanceService;
  final FamilyDeviceRole? preferredRole;

  @override
  State<FamilyLinkPage> createState() => _FamilyLinkPageState();
}

class _FamilyLinkPageState extends State<FamilyLinkPage> {
  final TextEditingController _pairCodeController = TextEditingController();
  late final ParentGuidanceNetworkService _guidanceService;
  GuidanceBundle? _aiBundle;
  bool _generatingAi = false;
  int _selectedAiSuggestionIndex = 0;

  @override
  void initState() {
    super.initState();
    _guidanceService = widget.guidanceService ?? ParentGuidanceNetworkService();
  }

  Future<void> _generateAiCompanion() async {
    if (_generatingAi || widget.coordinator.events.isEmpty) return;
    setState(() => _generatingAi = true);
    final events = widget.coordinator.events;
    final behaviors = events
        .map((event) => event.behavior)
        .whereType<ExplorationBehavior>()
        .toSet();
    final bundle = await _guidanceService.create(
      detection: null,
      observations: const {},
      behaviors: behaviors,
      weakSignal: false,
      events: events,
    );
    if (mounted) {
      setState(() {
        _aiBundle = bundle;
        _generatingAi = false;
        _selectedAiSuggestionIndex = 0;
      });
    }
  }

  Future<void> _showCompanionSettings() async {
    final quotaFuture = _guidanceService.loadQuota();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('家长陪伴设置', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.shield_outlined),
                title: Text('隐私范围'),
                subtitle: Text('只同步探索事件，不传原始录音、精确位置和儿童身份。'),
              ),
              FutureBuilder<ParentGuidanceQuota?>(
                future: quotaFuture,
                builder: (context, snapshot) {
                  final quota = snapshot.data;
                  final detail = quota == null
                      ? (snapshot.connectionState == ConnectionState.waiting
                            ? '正在查询…'
                            : '暂时无法查询')
                      : '已使用 ${quota.used} / ${quota.limit}，剩余 ${quota.remaining} 次';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('AI个性化回应'),
                    subtitle: Text('$detail\n本地陪伴提示不消耗次数。'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pairCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('家庭设备联动'),
      actions: [
        if (widget.preferredRole != FamilyDeviceRole.child)
          IconButton(
            key: const Key('family-companion-settings'),
            tooltip: '家长陪伴设置',
            onPressed: _showCompanionSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
      ],
    ),
    body: AnimatedBuilder(
      animation: widget.coordinator,
      builder: (context, _) {
        final coordinator = widget.coordinator;
        final connection = coordinator.connection;
        final role = connection?.role ?? widget.preferredRole;
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 40),
          children: [
            Text(
              role == FamilyDeviceRole.child
                  ? '连接家长陪伴端'
                  : role == FamilyDeviceRole.parent
                  ? '连接儿童探索端'
                  : '孩子探索，家长陪伴',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              role == FamilyDeviceRole.child
                  ? '输入家长设备显示的连接码。你的录音和观察仍保存在这台设备。'
                  : role == FamilyDeviceRole.parent
                  ? '创建临时连接，查看孩子的探索步骤和陪伴建议。'
                  : '两台设备只同步探索事件，不传儿童身份、原始录音或精确位置。',
            ),
            const SizedBox(height: 20),
            if (coordinator.error case final error?) ...[
              _FamilyNotice(message: error, error: true),
              const SizedBox(height: 12),
            ],
            if (connection == null)
              _UnlinkedDevices(
                role: role,
                pairCodeController: _pairCodeController,
                busy: coordinator.busy,
                onCreateParent: coordinator.createParentSession,
                onJoinChild: () =>
                    coordinator.joinAsChild(_pairCodeController.text.trim()),
              )
            else if (!connection.active)
              _PairingStatus(
                connection: connection,
                busy: coordinator.busy,
                onApprove: coordinator.approveChild,
                onRefresh: coordinator.refresh,
                onLeave: coordinator.leaveLocalSession,
              )
            else if (connection.role == FamilyDeviceRole.parent)
              _ParentLiveCompanion(
                coordinator: coordinator,
                aiBundle: _aiBundle,
                generatingAi: _generatingAi,
                onGenerateAi: _generateAiCompanion,
                selectedAiSuggestionIndex: _selectedAiSuggestionIndex,
                onSelectAiSuggestion: (index) =>
                    setState(() => _selectedAiSuggestionIndex = index),
              )
            else
              _ChildConnected(coordinator: coordinator),
          ],
        );
      },
    ),
  );
}

class _UnlinkedDevices extends StatelessWidget {
  const _UnlinkedDevices({
    required this.role,
    required this.pairCodeController,
    required this.busy,
    required this.onCreateParent,
    required this.onJoinChild,
  });

  final FamilyDeviceRole? role;
  final TextEditingController pairCodeController;
  final bool busy;
  final VoidCallback onCreateParent;
  final VoidCallback onJoinChild;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (role != FamilyDeviceRole.child)
        _RoleCard(
          icon: Icons.family_restroom_rounded,
          title: '这是家长陪伴设备',
          description: '创建一次临时探索，查看孩子的进度和陪伴建议。',
          actionLabel: '开始陪伴',
          onPressed: busy ? null : onCreateParent,
        ),
      if (role == null) const SizedBox(height: 14),
      if (role != FamilyDeviceRole.parent)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.explore_rounded),
                    SizedBox(width: 10),
                    Text(
                      '这是儿童探索设备',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('输入家长设备显示的6位连接码。'),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('family-pair-code-field'),
                  controller: pairCodeController,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    counterText: '',
                    labelText: '连接码',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: pairCodeController,
                  builder: (context, value, _) => FilledButton.icon(
                    key: const Key('join-family-session'),
                    onPressed: busy || value.text.length != 6
                        ? null
                        : onJoinChild,
                    icon: const Icon(Icons.link_rounded),
                    label: Text(value.text.isEmpty ? '输入6位连接码' : '连接家长设备'),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF174936), size: 27),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(description),
          const SizedBox(height: 16),
          FilledButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      ),
    ),
  );
}

class _PairingStatus extends StatelessWidget {
  const _PairingStatus({
    required this.connection,
    required this.busy,
    required this.onApprove,
    required this.onRefresh,
    required this.onLeave,
  });

  final FamilySessionConnection connection;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onRefresh;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final parent = connection.role == FamilyDeviceRole.parent;
    final pending = connection.status == FamilySessionStatus.pendingApproval;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              pending ? Icons.devices_rounded : Icons.qr_code_2_rounded,
              size: 52,
              color: const Color(0xFF174936),
            ),
            const SizedBox(height: 12),
            Text(
              pending
                  ? parent
                        ? '儿童设备等待确认'
                        : '等待家长设备确认'
                  : '等待儿童设备连接',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (parent)
              if (connection.pairCode case final code?) ...[
                const SizedBox(height: 18),
                const Text('在儿童设备输入连接码', textAlign: TextAlign.center),
                const SizedBox(height: 7),
                SelectableText(
                  code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 38,
                    letterSpacing: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF174936),
                  ),
                ),
              ],
            const SizedBox(height: 18),
            if (parent && pending)
              FilledButton.icon(
                key: const Key('approve-family-child'),
                onPressed: busy ? null : onApprove,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('确认这台儿童设备'),
              )
            else
              OutlinedButton.icon(
                onPressed: busy ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('刷新连接状态'),
              ),
            TextButton(
              onPressed: busy ? null : onLeave,
              child: const Text('取消连接'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParentLiveCompanion extends StatelessWidget {
  const _ParentLiveCompanion({
    required this.coordinator,
    required this.aiBundle,
    required this.generatingAi,
    required this.onGenerateAi,
    required this.selectedAiSuggestionIndex,
    required this.onSelectAiSuggestion,
  });
  final FamilySessionCoordinator coordinator;
  final GuidanceBundle? aiBundle;
  final bool generatingAi;
  final VoidCallback onGenerateAi;
  final int selectedAiSuggestionIndex;
  final ValueChanged<int> onSelectAiSuggestion;

  @override
  Widget build(BuildContext context) {
    final cue = coordinator.latestCue;
    final latestCommand = coordinator.commands.lastOrNull;
    final aiSuggestions =
        aiBundle?.praiseSuggestions.take(5).toList() ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FamilyNotice(message: _syncStatusLabel(coordinator, parent: true)),
        const SizedBox(height: 14),
        Card(
          color: const Color(0xFFFFF2CE),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: cue == null
                ? const Column(
                    children: [
                      Icon(Icons.favorite_outline_rounded, size: 32),
                      SizedBox(height: 9),
                      Text('等待孩子完成下一步探索'),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.hearing_rounded,
                            color: Color(0xFF174936),
                            size: 21,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cue.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            '刚刚',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '“${cue.say}”',
                        style: const TextStyle(fontSize: 18, height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton.icon(
                            key: const Key('open-companion-cue-reason'),
                            onPressed: () => _showCueReason(context, cue),
                            icon: const Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                            ),
                            label: const Text('为什么这样说'),
                          ),
                          FilledButton.tonal(
                            onPressed: coordinator.markCueSeen,
                            child: const Text('标为已读'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          color: const Color(0xFFE9F0E9),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'AI个性化回应',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                if (aiBundle == null)
                  const Text('本地陪伴提示始终可用。需要时可由家长明确使用1次AI生成3至5条可选回应。')
                else ...[
                  Row(
                    children: [
                      Icon(
                        aiBundle!.aiGenerated
                            ? Icons.auto_awesome_rounded
                            : Icons.shield_outlined,
                        size: 17,
                        color: const Color(0xFF315D4A),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          aiBundle!.aiGenerated
                              ? 'AI根据本次探索生成 · 请选择一句'
                              : '当前为本地审核模板 · 请选择一句',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  if (aiBundle!.warning.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      aiBundle!.warning,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF8A5A22),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  for (final (index, suggestion) in aiSuggestions.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _AiPraiseOption(
                        index: index,
                        suggestion: suggestion,
                        selected: index == selectedAiSuggestionIndex,
                        onSelected: () => onSelectAiSuggestion(index),
                      ),
                    ),
                ],
                if (aiBundle == null) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('generate-family-session-ai-guidance'),
                    onPressed: generatingAi || coordinator.events.isEmpty
                        ? null
                        : onGenerateAi,
                    icon: generatingAi
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(generatingAi ? '正在生成' : '使用1次AI生成更多回应'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text('发送共同任务', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        for (final template in familyMissionLabels.entries.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              onPressed: coordinator.busy
                  ? null
                  : () => coordinator.sendMission(template.key),
              icon: const Icon(Icons.send_outlined),
              label: Text(template.value),
            ),
          ),
        if (latestCommand != null) ...[
          const SizedBox(height: 4),
          _MissionDeliveryCard(
            label:
                familyMissionLabels[latestCommand.templateId] ??
                latestCommand.templateId,
            received: coordinator.missionReceived(latestCommand.commandId),
            completed: coordinator.missionCompleted(latestCommand.commandId),
          ),
        ],
        const SizedBox(height: 18),
        Text('探索时间线', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (coordinator.events.isEmpty)
          const Text('还没有收到探索事件。')
        else
          for (final event in coordinator.events.reversed.take(8))
            ListTile(
              dense: true,
              leading: const Icon(Icons.eco_outlined),
              title: Text(_eventLabel(event.type)),
              subtitle: Text(
                '${event.occurredAt.toLocal().hour.toString().padLeft(2, '0')}:'
                '${event.occurredAt.toLocal().minute.toString().padLeft(2, '0')}',
              ),
            ),
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: coordinator.busy ? null : coordinator.endSession,
          child: const Text('结束本次家庭探索'),
        ),
      ],
    );
  }

  Future<void> _showCueReason(BuildContext context, CompanionCue cue) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('为什么这样回应', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Text(cue.explanation),
                const SizedBox(height: 8),
                const Text('重点是肯定孩子的观察过程，不把声音候选说成确定答案。'),
              ],
            ),
          ),
        ),
      );
}

class _AiPraiseOption extends StatelessWidget {
  const _AiPraiseOption({
    required this.index,
    required this.suggestion,
    required this.selected,
    required this.onSelected,
  });

  final int index;
  final PraiseSuggestion suggestion;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    key: Key('family-ai-response-option-$index'),
    button: true,
    selected: selected,
    label: '回应选项 ${index + 1}：${suggestion.text}',
    child: Material(
      color: selected ? const Color(0xFFD9EADB) : const Color(0xFFFFFDF7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? const Color(0xFF315D4A) : const Color(0xFFD5D8D1),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: const Color(0xFF315D4A),
                size: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.ability,
                      style: const TextStyle(
                        color: Color(0xFF315D4A),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(suggestion.text),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ChildConnected extends StatelessWidget {
  const _ChildConnected({required this.coordinator});
  final FamilySessionCoordinator coordinator;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _FamilyNotice(message: _syncStatusLabel(coordinator, parent: false)),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const Icon(
                Icons.explore_rounded,
                size: 48,
                color: Color(0xFF174936),
              ),
              const SizedBox(height: 10),
              const Text('你的录音和观察仍然保存在这台设备。'),
              const SizedBox(height: 6),
              const Text('家长只能看到探索步骤摘要。'),
              if (coordinator.commands.lastOrNull case final command?) ...[
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 10),
                const Text('新的共同任务'),
                const SizedBox(height: 5),
                Text(
                  familyMissionLabels[command.templateId] ?? command.templateId,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                if (coordinator.missionCompleted(command.commandId))
                  const Chip(
                    avatar: Icon(Icons.check_rounded, size: 18),
                    label: Text('已经告诉家长：任务完成'),
                  )
                else
                  FilledButton.icon(
                    key: const Key('complete-family-mission'),
                    onPressed: coordinator.busy
                        ? null
                        : coordinator.completeLatestMission,
                    icon: const Icon(Icons.task_alt_rounded),
                    label: const Text('我完成了这个任务'),
                  ),
              ],
            ],
          ),
        ),
      ),
      TextButton(
        onPressed: coordinator.busy ? null : coordinator.leaveLocalSession,
        child: const Text('离开本次连接'),
      ),
    ],
  );
}

class _FamilyNotice extends StatelessWidget {
  const _FamilyNotice({required this.message, this.error = false});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFE5DC) : const Color(0xFFE4F0E7),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      children: [
        Icon(
          error ? Icons.error_outline : Icons.devices_rounded,
          color: error ? const Color(0xFF9A4F32) : const Color(0xFF174936),
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

class _MissionDeliveryCard extends StatelessWidget {
  const _MissionDeliveryCard({
    required this.label,
    required this.received,
    required this.completed,
  });

  final String label;
  final bool received;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final (status, icon, color) = completed
        ? ('儿童已完成', Icons.task_alt_rounded, const Color(0xFF1F6B4F))
        : received
        ? ('儿童已收到', Icons.mark_email_read_outlined, const Color(0xFF315D4A))
        : ('等待儿童端接收', Icons.schedule_send_outlined, const Color(0xFF856018));
    return Container(
      key: const Key('family-mission-delivery-status'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _syncStatusLabel(
  FamilySessionCoordinator coordinator, {
  required bool parent,
}) {
  final side = parent ? '儿童探索端' : '家长陪伴端';
  if (coordinator.error != null) return '$side已连接 · 同步暂时中断';
  if (coordinator.syncing) return '$side已连接 · 正在同步';
  final last = coordinator.lastSyncedAt;
  if (last == null) return '$side已连接 · 等待首次同步';
  final seconds = DateTime.now().difference(last).inSeconds;
  if (seconds < 15) return '$side已连接 · 刚刚同步';
  if (seconds < 60) return '$side已连接 · $seconds秒前同步';
  return '$side已连接 · 请检查网络';
}

String _eventLabel(String type) => switch (type) {
  'captured_sound' => '完成现场录音',
  'imported_sound' => '导入声音继续调查',
  'replayed_audio' => '主动回听声音',
  'completed_observation' => '完成现场观察',
  'compared_evidence' => '比较不同证据',
  'accepted_uncertainty' => '选择暂时不知道',
  'retried_recording' => '重新尝试录音',
  'completed_safe_route_stop' => '完成安全路线任务',
  'mission_received' => '收到家长共同任务',
  'mission_completed' => '完成家长共同任务',
  _ => '完成探索步骤',
};
