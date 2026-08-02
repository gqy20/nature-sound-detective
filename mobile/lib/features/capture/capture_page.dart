import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nature_sound_detective/core/audio/audio_recorder.dart';
import 'package:nature_sound_detective/core/audio/method_channel_audio_recorder.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({super.key, this.recorder});

  final AudioRecorder? recorder;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  static const _maxDuration = Duration(seconds: 20);

  late final AudioRecorder _recorder;
  Timer? _timer;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  bool _busy = false;
  RecordedAudio? _recording;
  String? _error;

  bool get _isRecording => _startedAt != null;

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder ?? MethodChannelAudioRecorder();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_isRecording) {
      unawaited(_recorder.cancel());
    }
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_busy) return;
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    setState(() {
      _busy = true;
      _recording = null;
      _error = null;
    });
    try {
      final permitted =
          await _recorder.hasPermission() ||
          await _recorder.requestPermission();
      if (!permitted) {
        throw PlatformException(
          code: 'permission_denied',
          message: '需要麦克风权限才能记录自然声音。',
        );
      }
      final session = await _recorder.start(maxDuration: _maxDuration);
      if (!mounted) return;
      setState(() {
        _startedAt = session.startedAt;
        _elapsed = Duration.zero;
      });
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted || _startedAt == null) return;
        final elapsed = DateTime.now().difference(_startedAt!);
        setState(
          () => _elapsed = elapsed > _maxDuration ? _maxDuration : elapsed,
        );
        if (elapsed >= _maxDuration && !_busy) {
          unawaited(_stopRecording());
        }
      });
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? '无法开始录音。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopRecording() async {
    if (_busy || !_isRecording) return;
    setState(() => _busy = true);
    _timer?.cancel();
    try {
      final recording = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _recording = recording;
        _startedAt = null;
        _elapsed = recording.duration;
      });
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message ?? '录音保存失败，请再试一次。';
          _startedAt = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (_elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    return Scaffold(
      appBar: AppBar(title: const Text('自然声探员')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '把耳朵借给大自然',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                '录下杭州身边的声音，寻找鸟、青蛙和昆虫的线索。',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const Spacer(),
              Text(
                _isRecording ? '$seconds 秒' : '最长 20 秒',
                key: const Key('recording-duration'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('record-button'),
                onPressed: _busy ? null : _toggleRecording,
                icon: Icon(
                  _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                ),
                label: Text(_isRecording ? '结束录音' : '开始录音'),
              ),
              if (_recording case final recording?) ...[
                const SizedBox(height: 16),
                Text(
                  '已保存 ${recording.duration.inSeconds} 秒 WAV 录音',
                  key: const Key('recording-saved'),
                  textAlign: TextAlign.center,
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 16),
                Text(
                  error,
                  key: const Key('recording-error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              const Text('靠近目标声音，避开说话声和车辆。', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
