import 'package:flutter/material.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/storage/creation_settings_store.dart';

class CreationSettingsPage extends StatefulWidget {
  const CreationSettingsPage({super.key, this.store});

  final CreationSettingsStore? store;

  @override
  State<CreationSettingsPage> createState() => _CreationSettingsPageState();
}

class _CreationSettingsPageState extends State<CreationSettingsPage> {
  late final CreationSettingsStore _store;
  final _formKey = GlobalKey<FormState>();
  final _minimaxKey = TextEditingController();
  final _minimaxModel = TextEditingController();
  final _dashscopeKey = TextEditingController();
  final _workspaceId = TextEditingController();
  final _wanModel = TextEditingController();
  String _region = 'beijing';
  bool _loading = true;
  bool _saving = false;
  bool _showMiniMaxKey = false;
  bool _showDashScopeKey = false;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? FileCreationSettingsStore();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await _store.load();
      if (!mounted) return;
      _minimaxKey.text = settings.minimaxApiKey;
      _minimaxModel.text = settings.minimaxMusicModel;
      _dashscopeKey.text = settings.dashscopeApiKey;
      _workspaceId.text = settings.dashscopeWorkspaceId;
      _wanModel.text = settings.wanVideoModel;
      setState(() => _region = settings.dashscopeRegion);
    } catch (error, stackTrace) {
      AppLog.error(
        'settings',
        'creation_config_load_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _showMessage('无法读取本机配置，请稍后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _minimaxKey.dispose();
    _minimaxModel.dispose();
    _dashscopeKey.dispose();
    _workspaceId.dispose();
    _wanModel.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      await _store.save(
        CreationSettings(
          minimaxApiKey: _minimaxKey.text,
          minimaxMusicModel: _minimaxModel.text,
          dashscopeApiKey: _dashscopeKey.text,
          dashscopeWorkspaceId: _workspaceId.text,
          dashscopeRegion: _region,
          wanVideoModel: _wanModel.text,
        ),
      );
      if (!mounted) return;
      _showMessage('创作配置已保存在本机');
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      AppLog.error(
        'settings',
        'creation_config_save_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _showMessage('配置保存失败，请检查存储空间后重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    try {
      await _store.clear();
      _minimaxKey.clear();
      _dashscopeKey.clear();
      _workspaceId.clear();
      if (!mounted) return;
      _showMessage('本机密钥已清除');
      setState(() {});
    } catch (error, stackTrace) {
      AppLog.error(
        'settings',
        'creation_config_clear_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _showMessage('暂时无法清除本机密钥。');
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 创作设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  Text('音乐', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text('MiniMax · 密钥仅存本机'),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('minimax-api-key-field'),
                    controller: _minimaxKey,
                    obscureText: !_showMiniMaxKey,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'MiniMax API Key',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _showMiniMaxKey ? '隐藏密钥' : '显示密钥',
                        onPressed: () =>
                            setState(() => _showMiniMaxKey = !_showMiniMaxKey),
                        icon: Icon(
                          _showMiniMaxKey
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: _requiredKey,
                  ),
                  const SizedBox(height: 28),
                  Text('视频', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text('阿里云百炼 · 可能产生费用'),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('dashscope-api-key-field'),
                    controller: _dashscopeKey,
                    obscureText: !_showDashScopeKey,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'DashScope API Key',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _showDashScopeKey ? '隐藏密钥' : '显示密钥',
                        onPressed: () => setState(
                          () => _showDashScopeKey = !_showDashScopeKey,
                        ),
                        icon: Icon(
                          _showDashScopeKey
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: _requiredKey,
                  ),
                  const SizedBox(height: 20),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 8),
                    title: const Text('高级设置'),
                    children: [
                      TextFormField(
                        controller: _minimaxModel,
                        decoration: const InputDecoration(
                          labelText: '音乐模型',
                          border: OutlineInputBorder(),
                        ),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _region,
                        decoration: const InputDecoration(
                          labelText: '地域',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'beijing', child: Text('北京')),
                          DropdownMenuItem(
                            value: 'singapore',
                            child: Text('新加坡'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _region = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _workspaceId,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Workspace ID（可选）',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _wanModel,
                        decoration: const InputDecoration(
                          labelText: '视频模型',
                          border: OutlineInputBorder(),
                        ),
                        validator: _required,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('save-creation-settings'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_saving ? '正在保存' : '保存配置'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('清除密钥'),
                  ),
                ],
              ),
            ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '请填写这一项' : null;

  String? _requiredKey(String? value) {
    if (value == null || value.trim().isEmpty) return '请填写 API Key';
    if (value.trim().length < 8) return 'API Key 看起来不完整';
    return null;
  }
}
