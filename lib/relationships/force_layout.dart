import 'dart:math' as math;
import 'dart:ui';

import 'relationship_data.dart';

class ForceLayout {
  ForceLayout(this.map, this.size) {
    for (var i = 0; i < map.interests.length; i++) {
      final angle = i * 2.39996 - math.pi / 2;
      final spread = math.sqrt((i + .6) / map.interests.length);
      positions[map.interests[i].id] = Offset(
        size.width / 2 + math.cos(angle) * size.width * .34 * spread,
        size.height / 2 + math.sin(angle) * size.height * .35 * spread,
      );
      _velocities[map.interests[i].id] = Offset.zero;
    }
    for (var i = 0; i < 220; i++) {
      step();
    }
  }
  final RelationshipMap map;
  final Size size;
  final positions = <String, Offset>{};
  final _velocities = <String, Offset>{};
  String? pinned;

  Offset _bounded(Offset p) => Offset(
    p.dx.clamp(52, math.max(52, size.width - 52)),
    p.dy.clamp(42, math.max(42, size.height - 66)),
  );

  void move(String id, Offset delta) {
    positions[id] = _bounded(positions[id]! + delta);
    _velocities[id] = Offset.zero;
  }

  void step() {
    final spacing = math
        .min(size.width / 2.6, size.height / 2.5)
        .clamp(94.0, 190.0);
    final ids = positions.keys.toList();
    final forces = {for (final id in ids) id: Offset.zero};
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        var delta = positions[ids[i]]! - positions[ids[j]]!;
        if (delta.distance < .1) delta = Offset(i.isEven ? 1 : -1, 1);
        final distance = math.max(1.0, delta.distance);
        final force =
            delta /
            distance *
            (2800 / (distance * distance) +
                math.max(0, spacing * .76 - distance) * .09);
        forces[ids[i]] = forces[ids[i]]! + force;
        forces[ids[j]] = forces[ids[j]]! - force;
      }
    }
    for (final edge in map.connections) {
      final delta = positions[edge.right.id]! - positions[edge.left.id]!;
      final distance = math.max(1.0, delta.distance);
      final desired = spacing * (1.05 + (1 - edge.strength) * .45);
      final force =
          delta / distance * (distance - desired) * .012 * edge.strength;
      forces[edge.left.id] = forces[edge.left.id]! + force;
      forces[edge.right.id] = forces[edge.right.id]! - force;
    }
    final center = Offset(size.width / 2, size.height / 2 - 8);
    for (final id in ids) {
      if (id == pinned) continue;
      var velocity =
          (_velocities[id]! + forces[id]! + (center - positions[id]!) * .004) *
          .79;
      if (velocity.distance > 6) velocity = velocity / velocity.distance * 6;
      _velocities[id] = velocity;
      positions[id] = _bounded(positions[id]! + velocity);
    }
  }
}

double distanceToSegment(Offset point, Offset a, Offset b) {
  final delta = b - a;
  if (delta.distanceSquared < .001) return (point - a).distance;
  final t =
      (((point - a).dx * delta.dx + (point - a).dy * delta.dy) /
              delta.distanceSquared)
          .clamp(0.0, 1.0);
  return (point - (a + delta * t)).distance;
}
