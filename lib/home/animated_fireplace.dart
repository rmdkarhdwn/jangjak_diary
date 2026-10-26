import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../diary/diary_store.dart';
import 'home_widgets.dart';

class AnimatedFireplace extends StatefulWidget {
  const AnimatedFireplace({
    super.key,
    required this.level,
    this.scale = 1,
    this.animate = true,
  });

  final FireLevel level;
  final double scale;
  final bool animate;

  @override
  State<AnimatedFireplace> createState() => _AnimatedFireplaceState();
}

class _AnimatedFireplaceState extends State<AnimatedFireplace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flicker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  void _syncAnimation() {
    final enabled =
        widget.animate && widget.level != FireLevel.ash && !_reduceMotion;
    if (enabled && !_flicker.isAnimating) {
      _flicker.repeat();
    } else if (!enabled) {
      _flicker.stop();
      _flicker.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(AnimatedFireplace oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      width: 300 * widget.scale,
      height: 320 * widget.scale,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 300,
          height: 320,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const FireplaceArt(name: 'fireplace_shell'),
              TweenAnimationBuilder<double>(
                duration: _reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                tween: Tween(end: widget.level.index.toDouble()),
                builder: (context, intensity, child) => AnimatedBuilder(
                  animation: _flicker,
                  builder: (context, child) {
                    final phase = _flicker.value * math.pi * 2;
                    final size = switch (intensity) {
                      < 1 => intensity * .19,
                      < 2 => .19 + (intensity - 1) * .30,
                      < 3 => .49 + (intensity - 2) * .51,
                      < 4 => 1 + (intensity - 3) * .20,
                      _ => 1.20 + (intensity - 4) * .15,
                    };
                    return SizedBox(
                      width: 300,
                      height: 320,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 72,
                            top: 137,
                            width: 158,
                            height: 144,
                            child: Opacity(
                              opacity:
                                  (intensity /
                                          5 *
                                          (.65 + .12 * math.sin(phase)))
                                      .clamp(0, 1),
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    colors: [
                                      Color(0xB3F9AD68),
                                      Color(0x00F9AD68),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 105,
                            top: 150,
                            width: 92,
                            height: 116,
                            child: Transform.scale(
                              key: const Key('flame-motion'),
                              alignment: Alignment.bottomCenter,
                              scaleX: size * (1 + .035 * math.sin(phase)),
                              scaleY: size * (1 + .045 * math.sin(phase + .7)),
                              child: const DesignIcon(
                                'flame',
                                width: 92,
                                height: 116,
                              ),
                            ),
                          ),
                          if (intensity >= 3 &&
                              widget.animate &&
                              !_reduceMotion)
                            Positioned(
                              left: 96,
                              top: 119,
                              width: 110,
                              height: 144,
                              child: CustomPaint(
                                painter: _Sparks(_flicker.value, intensity),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Positioned(
                left: 96,
                top: 260,
                child: DesignIcon('ash', width: 109, height: 11),
              ),
              Positioned(
                left: 99,
                top: 244,
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    widget.level == FireLevel.ash
                        ? const Color(0xFF8A827B)
                        : Colors.transparent,
                    BlendMode.srcATop,
                  ),
                  child: const DesignIcon('logs', width: 105, height: 29),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Sparks extends CustomPainter {
  const _Sparks(this.phase, this.intensity);
  final double phase;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final t = (phase + i / 3) % 1;
      final alpha = math.sin(t * math.pi) * .55;
      final x = 32 + i * 19 + math.sin(t * 6 + i) * 5;
      final y = size.height - t * (58 + intensity * 7);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: 1.8, height: 3),
        Paint()..color = const Color(0xFFFFDB9D).withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_Sparks oldDelegate) =>
      phase != oldDelegate.phase || intensity != oldDelegate.intensity;
}
