import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class CommunityVideoPage extends StatefulWidget {
  const CommunityVideoPage({
    super.key,
    required this.url,
    required this.sourceLabel,
  });

  final String url;
  final String sourceLabel;

  @override
  State<CommunityVideoPage> createState() => _CommunityVideoPageState();
}

class _CommunityVideoPageState extends State<CommunityVideoPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      await _controller.setLooping(true);
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _error = '作品视频暂时无法播放。');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF10271E),
    appBar: AppBar(
      title: const Text('社区自然作品'),
      backgroundColor: const Color(0xFF10271E),
      foregroundColor: Colors.white,
    ),
    body: Center(
      child: _error != null
          ? Text(_error!, style: const TextStyle(color: Colors.white))
          : !_ready
          ? const CircularProgressIndicator(color: Colors.white)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _controller.value.isPlaying
                          ? _controller.pause()
                          : _controller.play();
                    });
                  },
                  icon: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(_controller.value.isPlaying ? '暂停' : '播放'),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.sourceLabel,
                  style: const TextStyle(color: Color(0xFFCFE0D5)),
                ),
              ],
            ),
    ),
  );
}
