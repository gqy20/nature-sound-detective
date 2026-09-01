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
  final _dashscopeKey = TextEditingController();
  final _workspaceId = TextEditingController();
  final _dashscopeMusicModel = TextEditingController();
  final _dashscopeSpeechModel = TextEditingController();
  final _dashscopeSpeechVoice = TextEditingController();
  final _wanModel = TextEditingController();
  bool _loading = true;
  bool _saving = false;
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
      _dashscopeKey.text = settings.dashscopeApiKey;
      _workspaceId.text = settings.dashscopeWorkspaceId;
      _dashscopeMusicModel.text = settings.dashscopeMusicModel;
      _dashscopeSpeechModel.text = settings.dashscopeSpeechModel;
      _dashscopeSpeechVoice.text = settings.dashscopeSpeechVoice;
      _wanModel.text = settings.wanVideoModel;
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
    _dashscopeKey.dispose();
    _workspaceId.dispose();
    _dashscopeMusicModel.dispose();
    _dashscopeSpeechModel.dispose();
    _dashscopeSpeechVoice.dispose();
    _wanModel.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      await _store.save(
        CreationSettings(
          dashscopeApiKey: _dashscopeKey.text,
          dashscopeWorkspaceId: _workspaceId.text,
          dashscopeMusicModel: _dashscopeMusicModel.text,
          dashscopeSpeechModel: _dashscopeSpeechModel.text,
          dashscopeSpeechVoice: _dashscopeSpeechVoice.text,
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
                  Text('统一创作服务', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text('阿里云百炼 · 音乐、旁白和视频共用一个 API Key'),
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
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7F1E9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '创作固定使用北京地域的 Fun-Music、Qwen-Audio-TTS 和 Wan。'
                          '请使用北京地域的百炼 Key。',
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Fun-Music 目前为邀测模型。若 API Key 没有推理权限，'
                          '应用会跳过配乐，继续生成旁白和视频。',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 8),
                    title: const Text('模型与地域'),
                    children: [
                      TextFormField(
                        controller: _workspaceId,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Workspace ID（推荐）',
                          helperText: '留空时兼容公共域名；填写后使用专属域名，稳定性更好。',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('dashscope-music-model-field'),
                        controller: _dashscopeMusicModel,
                        decoration: const InputDecoration(
                          labelText: '音乐模型',
                          border: OutlineInputBorder(),
                        ),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('dashscope-speech-model-field'),
                        controller: _dashscopeSpeechModel,
                        decoration: const InputDecoration(
                          labelText: '旁白模型',
                          border: OutlineInputBorder(),
                        ),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('dashscope-speech-voice-field'),
                        controller: _dashscopeSpeechVoice,
                        decoration: const InputDecoration(
                          labelText: '旁白音色',
                          border: OutlineInputBorder(),
                        ),
                        validator: _required,
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
