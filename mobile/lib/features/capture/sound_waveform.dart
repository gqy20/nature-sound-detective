import 'dart:math' as math;

import 'package:flutter/material.dart';

class ListeningWaveRing extends StatefulWidget {
  const ListeningWaveRing({
    super.key,
    required this.levels,
    required this.rms,
    required this.peak,
    required this.active,
  });

  final List<double> levels;
  final double rms;
  final double peak;
  final bool active;

  @override
  State<ListeningWaveRing> createState() => _ListeningWaveRingState();
}

class _ListeningWaveRingState extends State<ListeningWaveRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void didUpdateWidget(covariant ListeningWaveRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.active && !reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: widget.rms),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        builder: (context, animatedRms, _) => AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            key: const Key('live-audio-wave-ring'),
            painter: _ListeningRingPainter(
              levels: widget.levels,
              rms: animatedRms,
              peak: widget.peak,
              active: widget.active,
              pulse: reduceMotion ? 0.35 : _controller.value,
            ),
          ),
        ),
      ),
    );
  }
}

class AudioWaveformView extends StatefulWidget {
  const AudioWaveformView({
    super.key,
    required this.samples,
    required this.active,
    this.progress,
    this.label = '录音声纹',
  });

  final List<double> samples;
  final bool active;
  final double? progress;
  final String label;

  @override
  State<AudioWaveformView> createState() => _AudioWaveformViewState();
}

class _AudioWaveformViewState extends State<AudioWaveformView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didUpdateWidget(covariant AudioWaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.progress != widget.progress) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.active && widget.progress == null && !reduceMotion) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      label: widget.label,
      value: widget.active ? '声音正在被读取' : '声音读取已暂停',
      child: RepaintBoundary(
        child: SizedBox(
          key: const Key('recording-waveform'),
          height: 70,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _WaveformPainter(
                samples: widget.samples,
                active: widget.active,
                scan:
                    widget.progress ?? (reduceMotion ? 0.5 : _controller.value),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ListeningRingPainter extends CustomPainter {
  const _ListeningRingPainter({
    required this.levels,
    required this.rms,
    required this.peak,
    required this.active,
    required this.pulse,
  });

  final List<double> levels;
  final double rms;
  final double peak;
  final bool active;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final extent = math.min(size.width, size.height);
    final baseRadius = extent * 0.39;
    final strength = math.sqrt((rms / 0.045).clamp(0.0, 1.0));
    final peakStrength = math.sqrt((peak / 0.16).clamp(0.0, 1.0));
    final values = levels.isEmpty ? const [0.0] : levels;
    const forest = Color(0xFF174936);
    const jade = Color(0xFF8FB9A7);
    const gold = Color(0xFFD6B567);

    canvas.drawCircle(
      center,
      baseRadius + 26 + strength * 10,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                jade.withValues(alpha: active ? 0.13 : 0.035),
                forest.withValues(alpha: active ? 0.055 : 0.012),
                Colors.transparent,
              ],
              stops: const [0.25, 0.7, 1],
            ).createShader(
              Rect.fromCircle(center: center, radius: baseRadius + 46),
            ),
    );

    for (var ring = 0; ring < 2; ring++) {
      final phase = (pulse + ring * 0.5) % 1;
      final radius = baseRadius + 12 + phase * extent * 0.105;
      final alpha = active ? (1 - phase) * (0.12 + strength * 0.14) : 0.025;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring == 0 ? 2.2 : 1.2
          ..color = jade.withValues(alpha: alpha),
      );
    }
    const points = 72;
    final path = Path();
    for (var index = 0; index <= points; index++) {
      final angle = -math.pi / 2 + index / points * math.pi * 2;
      final historyPosition = index / points * (values.length - 1);
      final lower = historyPosition.floor().clamp(0, values.length - 1);
      final upper = historyPosition.ceil().clamp(0, values.length - 1);
      final historyValue =
          values[lower] +
          (values[upper] - values[lower]) * (historyPosition - lower);
      final history = math.sqrt((historyValue / 0.045).clamp(0.0, 1.0));
      final texture = 0.55 * history + 0.3 * strength + 0.15 * peakStrength;
      final radius = baseRadius + (active ? 5 + texture * 18 : 1.5);
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 3.4 : 1.5
        ..strokeJoin = StrokeJoin.round
        ..color = jade.withValues(alpha: active ? 0.7 : 0.16),
    );
    if (active && peakStrength > 0.12) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
          ..color = jade.withValues(alpha: 0.1 + peakStrength * 0.1),
      );
    }

    if (active) {
      final particleCount = math.min(18, math.max(8, values.length));
      for (var index = 0; index < particleCount; index++) {
        final value = values[index * values.length ~/ particleCount];
        if (value < 0.008 && strength < 0.16) continue;
        final angle = index / particleCount * math.pi * 2 + pulse * 0.45;
        final radius = baseRadius + 18 + value.clamp(0.0, 0.08) * 180;
        final point =
            center + Offset(math.cos(angle), math.sin(angle)) * radius;
        canvas.drawCircle(
          point,
          1.2 + peakStrength * 1.8,
          Paint()..color = gold.withValues(alpha: 0.25 + strength * 0.5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ListeningRingPainter oldDelegate) =>
      oldDelegate.active != active ||
      oldDelegate.rms != rms ||
      oldDelegate.peak != peak ||
      oldDelegate.levels != levels ||
      oldDelegate.pulse != pulse;
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.samples,
    required this.active,
    required this.scan,
  });

  final List<double> samples;
  final bool active;
  final double scan;

  @override
  void paint(Canvas canvas, Size size) {
    final values = samples.isEmpty
        ? const [0.04, 0.04, 0.04, 0.04, 0.04, 0.04, 0.04, 0.04]
        : samples;
    final count = values.length;
    final gap = count > 48 ? 2.2 : 3.2;
    final barWidth = math.max(1.6, (size.width - gap * (count - 1)) / count);
    final centerY = size.height / 2;
    final scanX = size.width * scan.clamp(0.0, 1.0);
    final base = Paint()..strokeCap = StrokeCap.round;
    for (var index = 0; index < count; index++) {
      final x = index * (barWidth + gap) + barWidth / 2;
      final value = values[index].clamp(0.0, 1.0);
      final proximity = 1 - ((x - scanX).abs() / 42).clamp(0.0, 1.0);
      final pulse = active ? proximity * 0.16 : 0.0;
      final height = math.max(7.0, (value + pulse) * (size.height - 12));
      base
        ..strokeWidth = barWidth
        ..color = x <= scanX
            ? const Color(0xFF2F7557)
            : const Color(0xFFB8C9BF);
      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        base,
      );
    }
    if (active) {
      canvas.drawLine(
        Offset(scanX, 4),
        Offset(scanX, size.height - 4),
        Paint()
          ..color = const Color(0xFFE8A33D)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.active != active ||
      oldDelegate.scan != scan;
}
