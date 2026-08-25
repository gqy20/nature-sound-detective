import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/storage/creation_store.dart';
import 'package:nature_sound_detective/core/storage/exploration_record.dart';

class PublicationPage extends StatefulWidget {
  const PublicationPage({
    super.key,
    required this.record,
    required this.service,
    this.creationRecordsLoader,
    this.availableWorks,
  });

  final ExplorationRecord record;
  final CommunityService service;
  final Future<List<CreationRecord>> Function()? creationRecordsLoader;
  final List<CreationRecord>? availableWorks;

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
  List<CommunityPark> _parks = const [];
  List<CommunitySite> _sites = const [];
  String? _parkId;
  String? _siteId;
  List<CreationRecord> _works = const [];
  String? _selectedWorkId;
  bool _includeWork = false;
  bool _adultConfirmed = false;
  bool _publicConsent = false;
  bool _reviewConsent = false;
  bool _publishing = false;
  String? _error;
  CommunityPost? _publishedPost;

  @override
  void initState() {
    super.initState();
    _loadSites();
    final availableWorks = widget.availableWorks;
    if (availableWorks == null) {
      _loadWorks();
    } else {
      _works = availableWorks;
      _selectedWorkId = availableWorks.firstOrNull?.id;
    }
  }

  String get _subject {
    final primary = widget.record.detections.firstOrNull;
    return primary?.specificSpecies?.nameZh ??
        primary?.nameZh ??
        '待确认的自然声音';
  }

  String _workPath(CreationRecord record) => record.finalVideoPath.isNotEmpty
      ? record.finalVideoPath
      : record.videoPath;

  Future<void> _loadWorks() async {
    try {
      final loader = widget.creationRecordsLoader ?? CreationStore().list;
      final records = await loader();
      final matches = <CreationRecord>[];
      for (final record in records) {
        final path = _workPath(record);
        if (record.subject == _subject &&
            path.isNotEmpty &&
            await File(path).exists() &&
            await File(path).length() <= 25 * 1024 * 1024) {
          matches.add(record);
        }
      }
      if (!mounted) return;
      setState(() {
        _works = matches;
        _selectedWorkId = matches.firstOrNull?.id;
      });
    } catch (_) {
      // A missing works library must never block publishing the real recording.
    }
  }

  Future<void> _loadSites() async {
    try {
      final parks = await widget.service.listParks();
      if (!mounted || parks.isEmpty) return;
      final preferredParkId = widget.record.routeContext?.parkId;
      final park = parks
          .where((item) => item.id == preferredParkId)
          .firstOrNull ?? parks.first;
      final parkId = park.id;
      final sites = await widget.service.listSites(parkId: parkId);
      if (!mounted) return;
      setState(() {
        _parks = parks;
        _parkId = parkId;
        _areaId = park.areaId;
        _sites = sites;
        _siteId = sites
            .where((item) => item.id == widget.record.routeContext?.siteId)
            .firstOrNull
            ?.id ?? sites.firstOrNull?.id;
      });
    } catch (_) {
      // District-only publishing remains available as a compatibility fallback.
    }
  }

  Future<void> _selectPark(CommunityPark park) async {
    setState(() {
      _parkId = park.id;
      _areaId = park.areaId;
      _sites = const [];
      _siteId = null;
    });
    try {
      final sites = await widget.service.listSites(parkId: park.id);
      if (mounted && _parkId == park.id) {
        setState(() {
          _sites = sites;
          _siteId = sites.firstOrNull?.id;
        });
      }
    } catch (_) {}
  }

  Future<void> _publish() async {
    if (!_adultConfirmed || !_publicConsent || _publishing) return;
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final post = _publishedPost ??
          await widget.service.publish(
            PublicationRequest(
              record: widget.record,
              consent: PublicationConsent(
                areaId: _areaId,
                areaName: _areas[_areaId]!,
                adultConfirmed: _adultConfirmed,
                publicConsent: _publicConsent,
                reviewConsent: _reviewConsent,
                parkId: _parkId,
                zoneId: _sites
                    .where((item) => item.id == _siteId)
                    .firstOrNull
                    ?.zoneId,
                siteId: _siteId,
              ),
            ),
          );
      _publishedPost = post;
      if (_includeWork && _selectedWorkId != null) {
        final work = _works
            .where((item) => item.id == _selectedWorkId)
            .firstOrNull;
        if (work != null) {
          await widget.service.addMedia(
            post.id,
            filePath: _workPath(work),
            mediaType: 'video',
            sourceType: work.finalVideoPath.isNotEmpty
                ? 'composed'
                : 'ai_generated',
            provider: 'nature-story-pipeline',
          );
        }
      }
      if (mounted) Navigator.of(context).pop(post);
    } on CommunityException catch (error) {
      if (mounted) {
        setState(() => _error = _publishedPost == null
            ? error.message
            : '声音已经加入社区，但作品上传失败。可以重试作品上传，不会重复发布声音。');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = _publishedPost == null
            ? '发布暂时失败，声音仍安全保存在自然册。'
            : '声音已经加入社区，但作品上传失败。可以重试作品上传，不会重复发布声音。');
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                Text(_subject, style: Theme.of(context).textTheme.titleLarge),
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
          Text('展示到哪个公园？', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('只公开区域级位置，不上传精确坐标。'),
          const SizedBox(height: 12),
          if (_parks.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _parks.map((park) => ChoiceChip(
                key: Key('publish-park-${park.id}'),
                label: Text(park.name),
                selected: _parkId == park.id,
                onSelected: (_) => _selectPark(park),
              )).toList(),
            )
          else
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
          if (_sites.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('选择公开分区', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _sites.map((site) => ChoiceChip(
                key: Key('publish-site-${site.id}'),
                label: Text(site.zoneName),
                selected: _siteId == site.id,
                onSelected: (_) => setState(() => _siteId = site.id),
              )).toList(),
            ),
          ],
          if (_works.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text('同时发布自然作品', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text('作品用于讲述和分享；生态趋势仍只依据真实录音与现场观察。'),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const Key('include-community-work'),
              contentPadding: EdgeInsets.zero,
              value: _includeWork,
              onChanged: (value) =>
                  setState(() => _includeWork = value ?? false),
              title: const Text('附上这个动物的自然故事视频'),
              subtitle: Text(
                _works.length == 1 ? '已找到 1 件作品' : '已找到 ${_works.length} 件作品',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_includeWork && _works.length > 1)
              RadioGroup<String>(
                groupValue: _selectedWorkId,
                onChanged: (value) => setState(() => _selectedWorkId = value),
                child: Column(
                  children: _works
                      .map(
                        (work) => RadioListTile<String>(
                          value: work.id,
                          title: Text(work.subject),
                          subtitle: Text(
                            '${work.createdAt.month}月${work.createdAt.day}日生成',
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
          ],
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
            label: Text(
              _publishing
                  ? (_publishedPost == null ? '正在加入城市声景…' : '正在重试作品上传…')
                  : (_publishedPost == null ? '加入共听杭州' : '重试作品上传'),
            ),
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
