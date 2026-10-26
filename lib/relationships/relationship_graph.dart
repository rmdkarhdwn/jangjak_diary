import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diary/diary_store.dart';
import '../home/home_widgets.dart';
import '../theme/diary_theme.dart';
import 'force_layout.dart';
import 'relationship_data.dart';

class RelationshipGraph extends StatefulWidget {
  const RelationshipGraph({
    super.key,
    required this.map,
    required this.now,
    required this.selectedId,
    required this.onSelect,
    required this.onConnection,
  });
  final RelationshipMap map;
  final DateTime now;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final ValueChanged<InterestConnection> onConnection;

  @override
  State<RelationshipGraph> createState() => RelationshipGraphState();
}

class RelationshipGraphState extends State<RelationshipGraph>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );
  final _transform = TransformationController();
  ForceLayout? _layout;
  int _settling = 0;

  @override
  void initState() {
    super.initState();
    _motion.addListener(() {
      if (_settling > 0) {
        _layout?.step();
        _settling--;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void didUpdateWidget(RelationshipGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.map != widget.map) {
      _layout = null;
      _transform.value = Matrix4.identity();
    }
  }

  void resetView() => setState(() {
    _transform.value = Matrix4.identity();
    _layout = null;
  });

  void zoom(double factor) {
    final scale = _transform.value.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(.65, 2.5);
    final center = _layout!.size.center(Offset.zero);
    final scene = _transform.toScene(center);
    _transform.value = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(next, next, 1, 1)
      ..translateByDouble(-scene.dx, -scene.dy, 0, 1);
  }

  @override
  void dispose() {
    _motion.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      if (_layout?.size != size) _layout = ForceLayout(widget.map, size);
      return ClipRect(
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: .65,
          maxScale: 2.5,
          boundaryMargin: const EdgeInsets.all(160),
          child: AnimatedBuilder(
            animation: _motion,
            builder: (_, _) {
              final positions = <String, Offset>{};
              for (var i = 0; i < widget.map.interests.length; i++) {
                final id = widget.map.interests[i].id;
                final phase = _motion.value * math.pi * 2 + i * 1.7;
                final drift = MediaQuery.disableAnimationsOf(context)
                    ? Offset.zero
                    : Offset(math.sin(phase) * 2, math.cos(phase * 2) * 1.5);
                positions[id] = _layout!.positions[id]! + drift;
              }
              final neighbors = widget.selectedId == null
                  ? <String>{}
                  : {
                      widget.selectedId!,
                      for (final edge in widget.map.connectionsFor(
                        widget.selectedId!,
                      )) ...[edge.left.id, edge.right.id],
                    };
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  InterestConnection? closest;
                  var distance = 14 / _transform.value.getMaxScaleOnAxis();
                  for (final edge in widget.map.connections) {
                    if (widget.selectedId != null &&
                        !edge.contains(widget.selectedId!)) {
                      continue;
                    }
                    final d = distanceToSegment(
                      details.localPosition,
                      positions[edge.left.id]!,
                      positions[edge.right.id]!,
                    );
                    if (d < distance) {
                      distance = d;
                      closest = edge;
                    }
                  }
                  if (closest != null) {
                    widget.onConnection(closest);
                  } else {
                    widget.onSelect(null);
                  }
                },
                child: SizedBox.fromSize(
                  size: size,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ConstellationPainter(
                            map: widget.map,
                            positions: Map.of(positions),
                            selectedId: widget.selectedId,
                            phase: _motion.value,
                          ),
                        ),
                      ),
                      for (final interest in widget.map.interests)
                        Positioned(
                          left: positions[interest.id]!.dx - 50,
                          top: positions[interest.id]!.dy - 30,
                          width: 100,
                          height: 80,
                          child: FocusableActionDetector(
                            shortcuts: const {
                              SingleActivator(LogicalKeyboardKey.enter):
                                  ActivateIntent(),
                              SingleActivator(LogicalKeyboardKey.space):
                                  ActivateIntent(),
                            },
                            actions: {
                              ActivateIntent: CallbackAction<ActivateIntent>(
                                onInvoke: (_) {
                                  widget.onSelect(
                                    widget.selectedId == interest.id
                                        ? null
                                        : interest.id,
                                  );
                                  return null;
                                },
                              ),
                            },
                            child: Semantics(
                              key: ValueKey('graph-node-${interest.id}'),
                              button: true,
                              selected: widget.selectedId == interest.id,
                              label:
                                  '${interest.title}, ${interest.isArchived ? '보관한 불' : interest.levelAt(widget.now).label}, ${widget.map.connectionsFor(interest.id).length}개의 연결',
                              onTap: () => widget.onSelect(interest.id),
                              child: ExcludeSemantics(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.deferToChild,
                                  onTap: () => widget.onSelect(
                                    widget.selectedId == interest.id
                                        ? null
                                        : interest.id,
                                  ),
                                  onPanStart: (_) =>
                                      _layout!.pinned = interest.id,
                                  onPanUpdate: (details) => setState(() {
                                    _layout!.move(
                                      interest.id,
                                      details.delta /
                                          _transform.value.getMaxScaleOnAxis(),
                                    );
                                    for (var i = 0; i < 3; i++) {
                                      _layout!.step();
                                    }
                                  }),
                                  onPanEnd: (_) {
                                    _layout!.pinned = null;
                                    _settling = 50;
                                  },
                                  onPanCancel: () => _layout!.pinned = null,
                                  child: _FireNode(
                                    interest: interest,
                                    level: interest.levelAt(widget.now),
                                    selected: widget.selectedId == interest.id,
                                    dimmed:
                                        widget.selectedId != null &&
                                        !neighbors.contains(interest.id),
                                    phase: _motion.value,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

class _FireNode extends StatelessWidget {
  const _FireNode({
    required this.interest,
    required this.level,
    required this.selected,
    required this.dimmed,
    required this.phase,
  });
  final Interest interest;
  final FireLevel level;
  final bool selected, dimmed;
  final double phase;

  @override
  Widget build(BuildContext context) {
    final radius = 9 + level.index * 2.6;
    final color = level == FireLevel.ash
        ? const Color(0xFFB5AEBE)
        : const Color(0xFFF2C38E);
    return Opacity(
      opacity: dimmed ? .25 : 1,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            color: Colors.transparent,
            child: Center(
              child: Container(
                width: radius * 2,
                height: radius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      color.withValues(alpha: .32),
                      color.withValues(alpha: .12),
                    ],
                  ),
                  border: Border.all(
                    color: color.withValues(alpha: selected ? 1 : .58),
                    width: selected ? 1.5 : .8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(
                        alpha: .1 + math.sin(phase * math.pi * 2) * .025,
                      ),
                      blurRadius: selected ? 36 : 24,
                      spreadRadius: selected ? 8 : 3,
                    ),
                    if (selected)
                      BoxShadow(
                        color: color.withValues(alpha: .06),
                        spreadRadius: 6,
                      ),
                  ],
                ),
                child: Center(
                  child: level == FireLevel.ash
                      ? Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        )
                      : DesignIcon(
                          'brand_flame',
                          width: 8 + level.index * 1.6,
                          height: 10 + level.index * 2.2,
                        ),
                ),
              ),
            ),
          ),
          Text(
            interest.isArchived ? '${interest.title} · 보관' : interest.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: DiaryTheme.cream.withValues(alpha: selected ? 1 : .8),
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConstellationPainter extends CustomPainter {
  const _ConstellationPainter({
    required this.map,
    required this.positions,
    required this.selectedId,
    required this.phase,
  });
  final RelationshipMap map;
  final Map<String, Offset> positions;
  final String? selectedId;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(17);
    for (var i = 0; i < 48; i++) {
      final point = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      canvas.drawCircle(
        point,
        i % 5 == 0 ? 1 : .55,
        Paint()
          ..color = DiaryTheme.cream.withValues(
            alpha: .06 + random.nextDouble() * .1,
          ),
      );
    }
    for (final edge in map.connections) {
      final a = positions[edge.left.id]!, b = positions[edge.right.id]!;
      final emphasized = selectedId == null || edge.contains(selectedId!);
      final opacity = emphasized ? .14 + edge.strength * .55 : .045;
      final width = .45 + edge.strength * edge.strength * 3;
      if (emphasized && edge.strength >= .7) {
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xFFE8BB89).withValues(alpha: .06)
            ..strokeWidth = width + 5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0xFFE2BE99).withValues(alpha: opacity)
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
      if (emphasized) {
        final midpoint = Offset.lerp(a, b, .5)!;
        canvas.drawCircle(
          midpoint,
          2.2,
          Paint()..color = const Color(0xFFE8C5A0).withValues(alpha: opacity),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ConstellationPainter oldDelegate) => true;
}
