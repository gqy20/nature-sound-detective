import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/storage/exploration_record.dart';

class PublicationPage extends StatefulWidget {
  const PublicationPage({
    super.key,
    required this.record,
    required this.service,
  });

  final ExplorationRecord record;
  final CommunityService service;

  @override
  State<PublicationPage> createState() => _PublicationPageState();
}

class _PublicationPageState extends State<PublicationPage> {
  static const _areas = <String, String>{
    'xihu': '西湖区',
    'shangcheng': '上城区',
    'gongshu': '拱墅区',
    'binjiang': '滨江区',
    'yuhang': '余杭区',
    'xiaoshan': '萧山区',
  };

  String _areaId = 'xihu';
  bool _adultConfirmed = false;
  bool _publicConsent = false;
  bool _reviewConsent = false;
  bool _publishing = false;
  String? _error;

  Future<void> _publish() async {
    if (!_adultConfirmed || !_publicConsent || _publishing) return;
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final post = await widget.service.publish(
        PublicationRequest(
          record: widget.record,
          consent: PublicationConsent(
            areaId: _areaId,
            areaName: _areas[_areaId]!,
            adultConfirmed: _adultConfirmed,
            publicConsent: _publicConsent,
            reviewConsent: _reviewConsent,
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop(post);
    } on CommunityException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '发布暂时失败，声音仍安全保存在自然册。');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.record.detections.firstOrNull;
    final subject =
        primary?.specificSpecies?.nameZh ?? primary?.nameZh ?? '待确认的自然声音';
    return Scaffold(
      appBar: AppBar(title: const Text('加入共听杭州')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFE8EFE8),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('准备公开的声音线索'),
                const SizedBox(height: 8),
                Text(subject, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('${widget.record.duration.inSeconds} 秒 · 仅使用这次录音和调查结果'),
                if (widget.record.fieldChecks.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('包含已完成的现场观察'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text('展示到哪个区域？', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('只公开区域级位置，不上传精确坐标。'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _areas.entries
                .map(
                  (entry) => ChoiceChip(
                    key: Key('publish-area-${entry.key}'),
                    label: Text(entry.value),
                    selected: _areaId == entry.key,
                    onSelected: (_) => setState(() => _areaId = entry.key),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 28),
          Text('公开授权', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          CheckboxListTile(
            key: const Key('adult-confirmation'),
            contentPadding: EdgeInsets.zero,
            value: _adultConfirmed,
            onChanged: (value) =>
                setState(() => _adultConfirmed = value ?? false),
            title: const Text('我是成年人，并同意这次公开'),
            subtitle: const Text('儿童不能独立完成公开授权。'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            key: const Key('public-consent'),
            contentPadding: EdgeInsets.zero,
            value: _publicConsent,
            onChanged: (value) =>
                setState(() => _publicConsent = value ?? false),
            title: const Text('匿名发布这条探索卡'),
            subtitle: const Text('不展示儿童姓名、头像或精确位置，可随时撤回。'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            key: const Key('review-consent'),
            contentPadding: EdgeInsets.zero,
            value: _reviewConsent,
            onChanged: (value) =>
                setState(() => _reviewConsent = value ?? false),
            title: const Text('另外提交人工复核'),
            subtitle: const Text('与匿名公开分开授权，不会自动用于模型训练。'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Color(0xFF9B3B32))),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('confirm-publication'),
            onPressed: _adultConfirmed && _publicConsent && !_publishing
                ? _publish
                : null,
            icon: _publishing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.radar_rounded),
            label: Text(_publishing ? '正在加入城市声景…' : '加入共听杭州'),
          ),
          const SizedBox(height: 12),
          const Text(
            '公开状态会标记为“公众协助中”，不会把 AI 候选描述为专业确认。',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
