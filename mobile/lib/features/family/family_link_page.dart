import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/family/family_session_coordinator.dart';
import 'package:nature_sound_detective/core/family/family_session_models.dart';
import 'package:nature_sound_detective/core/guidance/guidance_bundle.dart';
import 'package:nature_sound_detective/core/network/parent_guidance_service.dart';
import 'package:share_plus/share_plus.dart';

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
  Timer? _pairCountdownTimer;

  @override
  void initState() {
    super.initState();
    _guidanceService = widget.guidanceService ?? ParentGuidanceNetworkService();
    _pairCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final connection = widget.coordinator.connection;
      if (mounted &&
          connection?.active != true &&
          connection?.pairExpiresAt != null) {
        setState(() {});
      }
    });
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
    _pairCountdownTimer?.cancel();
    _pairCodeController.dispose();
    super.dispose();
  }

  Future<void> _copyPairCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('连接码已复制')));
  }

  Future<void> _sharePairCode(String code) async {
    await SharePlus.instance.share(
      ShareParams(text: '自然声探员家庭连接码：$code\n请在儿童探索设备中输入。'),
    );
  }

  Future<void> _copyAiResponse(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('回应已复制，可以照着说')));
  }

  Future<void> _confirmEndSession({required bool parent}) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(parent ? '结束这次家庭探索？' : '离开这次家庭探索？'),
        content: const Text('两台设备将停止同步；已经保存的录音、观察和自然册内容不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续探索'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(parent ? '确认结束' : '确认离开'),
          ),
        ],
      ),
    );
    if (agreed != true) return;
    if (parent) {
      await widget.coordinator.endSession();
    } else {
      await widget.coordinator.leaveLocalSession();
    }
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
        final active = connection?.active == true;
        final title = role == FamilyDeviceRole.child
            ? (active ? '家长陪伴端' : '连接家长陪伴端')
            : role == FamilyDeviceRole.parent
            ? (active ? '儿童探索端' : '连接儿童探索端')
            : '孩子探索，家长陪伴';
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 40),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                if (active) ...[
                  const SizedBox(width: 12),
                  _ConnectedStatusChip(coordinator: coordinator),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              active
                  ? role == FamilyDeviceRole.child
                        ? '录音仍留在本机，家长只看到步骤摘要 · ${_syncRecencyLabel(coordinator)}'
                        : '查看孩子的探索步骤和陪伴建议 · ${_syncRecencyLabel(coordinator)}'
                  : role == FamilyDeviceRole.child
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
                onCopyCode: _copyPairCode,
                onShareCode: _sharePairCode,
                showManualRefresh: coordinator.error != null,
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
                onUseAiSuggestion: _copyAiResponse,
                onEndSession: () => _confirmEndSession(parent: true),
              )
            else
              _ChildConnected(
                coordinator: coordinator,
                onLeave: () => _confirmEndSession(parent: false),
              ),
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
    required this.onCopyCode,
    required this.onShareCode,
    required this.showManualRefresh,
  });

  final FamilySessionConnection connection;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onRefresh;
  final VoidCallback onLeave;
  final ValueChanged<String> onCopyCode;
  final ValueChanged<String> onShareCode;
  final bool showManualRefresh;

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pending
                            ? parent
                                  ? '儿童设备等待确认'
                                  : '等待家长设备确认'
                            : '等待儿童设备连接',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        pending
                            ? parent
                                  ? '核对无误后确认本次临时连接'
                                  : '家长确认后即可开始共同探索'
                            : '在儿童设备输入下方连接码',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  key: const Key('family-pairing-phase-icon'),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4F0E7),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    pending ? Icons.devices_rounded : Icons.pin_outlined,
                    color: const Color(0xFF174936),
                  ),
                ),
              ],
            ),
            if (parent)
              if (connection.pairCode case final code?) ...[
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('连接码'),
                    if (_pairExpiryLabel(connection) case final expiry?) ...[
                      const SizedBox(width: 8),
                      Text(
                        expiry,
                        key: const Key('family-pair-expiry'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF856018),
                        ),
                      ),
                    ],
                  ],
                ),
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('copy-family-pair-code'),
                        onPressed: busy ? null : () => onCopyCode(code),
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('复制'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('share-family-pair-code'),
                        onPressed: busy ? null : () => onShareCode(code),
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('分享'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '儿童设备 · 临时连接尾号 ${_sessionSuffix(connection)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
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
            else if (showManualRefresh)
              OutlinedButton.icon(
                onPressed: busy ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新连接'),
              )
            else
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 9),
                  Text('正在自动等待连接'),
                ],
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
    required this.onUseAiSuggestion,
    required this.onEndSession,
  });
  final FamilySessionCoordinator coordinator;
  final GuidanceBundle? aiBundle;
  final bool generatingAi;
  final VoidCallback onGenerateAi;
  final int selectedAiSuggestionIndex;
  final ValueChanged<int> onSelectAiSuggestion;
  final ValueChanged<String> onUseAiSuggestion;
  final VoidCallback onEndSession;

  @override
  Widget build(BuildContext context) {
    final cue = coordinator.latestCue;
    final latestCommand = coordinator.commands.lastOrNull;
    final activeMission = coordinator.activeMission;
    final aiSuggestions =
        aiBundle?.praiseSuggestions.take(5).toList() ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                            _cueTimeLabel(coordinator, cue),
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
                            child: Text(
                              coordinator.unseenCueCount > 1
                                  ? '下一条 · ${coordinator.unseenCueCount - 1}'
                                  : '标为已读',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        if (coordinator.events.isEmpty)
          Container(
            key: const Key('family-ai-waiting-strip'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE9F0E9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_outlined, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text('收到探索记录后，可以按需生成个性化回应。')),
              ],
            ),
          )
        else
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
                    if (aiSuggestions.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      FilledButton.tonalIcon(
                        key: const Key('copy-family-ai-response'),
                        onPressed: () => onUseAiSuggestion(
                          aiSuggestions[selectedAiSuggestionIndex].text,
                        ),
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('复制这句回应'),
                      ),
                    ],
                  ],
                  if (aiBundle == null) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('generate-family-session-ai-guidance'),
                      onPressed: generatingAi ? null : onGenerateAi,
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
        Text(
          activeMission == null ? '发送共同任务' : '当前共同任务',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        if (activeMission == null)
          for (final template in familyMissionLabels.entries.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                key: Key('family-mission-${template.key}'),
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
            helpRequested: coordinator.missionHelpRequested(
              latestCommand.commandId,
            ),
            deferred: coordinator.missionDeferred(latestCommand.commandId),
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
              leading: Icon(
                _eventIcon(event.type),
                color: _eventColor(event.type),
              ),
              title: Text(_eventLabel(event.type)),
              subtitle: Text(
                '${event.occurredAt.toLocal().hour.toString().padLeft(2, '0')}:'
                '${event.occurredAt.toLocal().minute.toString().padLeft(2, '0')}',
              ),
            ),
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: coordinator.busy ? null : onEndSession,
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
  const _ChildConnected({required this.coordinator, required this.onLeave});
  final FamilySessionCoordinator coordinator;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (coordinator.missionHelpRequested(command.commandId))
                        const Chip(
                          avatar: Icon(Icons.volunteer_activism_outlined),
                          label: Text('已经告诉家长：我需要帮助'),
                        )
                      else if (coordinator.missionDeferred(command.commandId))
                        const Chip(
                          avatar: Icon(Icons.schedule_rounded),
                          label: Text('已经告诉家长：我想稍后再做'),
                        ),
                      FilledButton.icon(
                        key: const Key('complete-family-mission'),
                        onPressed: coordinator.busy
                            ? null
                            : coordinator.completeLatestMission,
                        icon: const Icon(Icons.task_alt_rounded),
                        label: const Text('我完成了'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const Key('request-family-mission-help'),
                              onPressed:
                                  coordinator.busy ||
                                      coordinator.missionHelpRequested(
                                        command.commandId,
                                      )
                                  ? null
                                  : coordinator.requestMissionHelp,
                              icon: const Icon(Icons.handshake_outlined),
                              label: const Text('需要帮助'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextButton.icon(
                              key: const Key('defer-family-mission'),
                              onPressed:
                                  coordinator.busy ||
                                      coordinator.missionDeferred(
                                        command.commandId,
                                      )
                                  ? null
                                  : coordinator.deferLatestMission,
                              icon: const Icon(Icons.schedule_rounded),
                              label: const Text('稍后再做'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
      TextButton(
        onPressed: coordinator.busy ? null : onLeave,
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

class _ConnectedStatusChip extends StatelessWidget {
  const _ConnectedStatusChip({required this.coordinator});

  final FamilySessionCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    final warning = coordinator.error != null;
    final syncing = coordinator.syncing;
    final label = warning ? '需留意' : (syncing ? '同步中' : '已连接');
    final foreground = warning
        ? const Color(0xFF856018)
        : const Color(0xFF174936);
    final background = warning
        ? const Color(0xFFFFF0D2)
        : const Color(0xFFE4F0E7);
    return Semantics(
      label: warning ? '设备已连接，同步需要留意' : '设备$label',
      child: Container(
        key: const Key('family-connected-status'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              warning ? Icons.sync_problem_rounded : Icons.devices_rounded,
              size: 17,
              color: foreground,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissionDeliveryCard extends StatelessWidget {
  const _MissionDeliveryCard({
    required this.label,
    required this.received,
    required this.completed,
    required this.helpRequested,
    required this.deferred,
  });

  final String label;
  final bool received;
  final bool completed;
  final bool helpRequested;
  final bool deferred;

  @override
  Widget build(BuildContext context) {
    final (status, icon, color) = completed
        ? ('儿童已完成', Icons.task_alt_rounded, const Color(0xFF1F6B4F))
        : helpRequested
        ? ('儿童需要帮助', Icons.handshake_outlined, const Color(0xFF9A4F32))
        : deferred
        ? ('儿童想稍后再做', Icons.schedule_rounded, const Color(0xFF856018))
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

String _syncRecencyLabel(FamilySessionCoordinator coordinator) {
  if (coordinator.error != null) return '同步需留意';
  if (coordinator.syncing) return '正在同步';
  final last = coordinator.lastSyncedAt;
  if (last == null) return '等待首次同步';
  final seconds = DateTime.now().difference(last).inSeconds;
  if (seconds < 15) return '刚刚同步';
  if (seconds < 60) return '$seconds秒前同步';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes分钟前同步';
  return '较久未同步';
}

String? _pairExpiryLabel(FamilySessionConnection connection) {
  final expiresAt = connection.pairExpiresAt;
  if (expiresAt == null) return null;
  final remaining = expiresAt.difference(DateTime.now());
  if (remaining <= Duration.zero) return '已过期';
  final minutes = remaining.inMinutes;
  final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds 后失效';
}

String _sessionSuffix(FamilySessionConnection connection) {
  final value = connection.sessionId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (value.length <= 4) return value.toUpperCase();
  return value.substring(value.length - 4).toUpperCase();
}

String _cueTimeLabel(FamilySessionCoordinator coordinator, CompanionCue cue) {
  final event = coordinator.events
      .where((item) => item.eventId == cue.eventId)
      .firstOrNull;
  if (event == null) return '时间未知';
  final local = event.occurredAt.toLocal();
  final now = DateTime.now();
  final difference = now.difference(local);
  if (difference.isNegative || difference.inMinutes < 1) return '刚刚';
  if (difference.inMinutes < 60) return '${difference.inMinutes}分钟前';
  if (difference.inHours < 24 && local.day == now.day) {
    return '${difference.inHours}小时前';
  }
  if (difference.inHours < 48) {
    return '昨天 ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.month}月${local.day}日';
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
  'mission_help_requested' => '向家长请求任务帮助',
  'mission_deferred' => '告诉家长稍后再做',
  _ => '完成探索步骤',
};

IconData _eventIcon(String type) => switch (type) {
  'captured_sound' || 'imported_sound' => Icons.mic_none_rounded,
  'replayed_audio' => Icons.replay_rounded,
  'completed_observation' || 'compared_evidence' => Icons.search_rounded,
  'accepted_uncertainty' => Icons.help_outline_rounded,
  'retried_recording' => Icons.refresh_rounded,
  'completed_safe_route_stop' => Icons.route_outlined,
  'mission_received' => Icons.mark_email_read_outlined,
  'mission_completed' => Icons.task_alt_rounded,
  'mission_help_requested' => Icons.handshake_outlined,
  'mission_deferred' => Icons.schedule_rounded,
  _ => Icons.eco_outlined,
};

Color _eventColor(String type) => switch (type) {
  'mission_completed' => const Color(0xFF1F6B4F),
  'mission_help_requested' => const Color(0xFF9A4F32),
  'mission_deferred' => const Color(0xFF856018),
  'mission_received' => const Color(0xFF315D4A),
  _ => const Color(0xFF52615A),
};
