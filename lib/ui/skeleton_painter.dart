import 'package:flutter/material.dart';

import '../models/landmark.dart';

/// Draws the body skeleton and face outline over the camera preview.
class SkeletonPainter extends CustomPainter {
  SkeletonPainter({required this.frame, required this.mirrored, this.minScore = 0.4}) : super(repaint: frame);

  final ValueNotifier<DetectionFrame?> frame;
  final bool mirrored;
  final double minScore;

  static final _bone = Paint()
    ..color = const Color(0xFF4DD0E1)
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;
  static final _joint = Paint()..color = const Color(0xFFFFFFFF);
  static final _face = Paint()
    ..color = const Color(0xFFFFCA28)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame.value;
    if (f == null) return;

    Offset at(Landmark l) => Offset((mirrored ? 1 - l.x : l.x) * size.width, l.y * size.height);
    bool ok(Landmark? l) => l != null && l.score >= minScore;

    final pose = f.pose;
    if (pose != null) {
      for (final (a, b) in Pose.bones) {
        final la = f.joint(a), lb = f.joint(b);
        if (ok(la) && ok(lb)) canvas.drawLine(at(la!), at(lb!), _bone);
      }
      for (var i = 0; i < pose.length; i++) {
        final l = pose[i];
        if (ok(l) && _isDrawnJoint(i)) canvas.drawCircle(at(l!), 4, _joint);
      }
    }

    final outline = f.face?.outline;
    if (outline != null && outline.length > 2) {
      final path = Path()..moveTo(at(outline.first).dx, at(outline.first).dy);
      for (final l in outline.skip(1)) {
        final o = at(l);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path..close(), _face);
    }
  }

  // Facial points of the body model are cluttered next to the face outline.
  static bool _isDrawnJoint(int i) => i >= Pose.leftShoulder || i == Pose.nose;

  @override
  bool shouldRepaint(SkeletonPainter old) => old.mirrored != mirrored || old.frame != frame;
}
