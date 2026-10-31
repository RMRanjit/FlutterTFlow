import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_poc/models/head_pose_math.dart';

List<double> matrix(double yawDeg, double pitchDeg, double rollDeg, {double scale = 1}) {
  final y = yawDeg * math.pi / 180, p = pitchDeg * math.pi / 180, r = rollDeg * math.pi / 180;
  final cy = math.cos(y), sy = math.sin(y), cp = math.cos(p), sp = math.sin(p), cr = math.cos(r), sr = math.sin(r);
  // R = Ry(yaw) * Rx(pitch) * Rz(roll), row-major.
  final rows = [
    [cy * cr + sy * sp * sr, -cy * sr + sy * sp * cr, sy * cp],
    [cp * sr, cp * cr, -sp],
    [-sy * cr + cy * sp * sr, sy * sr + cy * sp * cr, cy * cp],
  ];
  // Column-major 4x4 with translation and uniform scale.
  return [
    for (var c = 0; c < 3; c++) ...[rows[0][c] * scale, rows[1][c] * scale, rows[2][c] * scale, 0],
    1, 2, 3, 1,
  ];
}

void main() {
  test('recovers yaw/pitch/roll from a rotation matrix', () {
    final hp = headPoseFromMatrix(matrix(30, -12, 7))!;
    expect(hp.yaw, closeTo(30, 1e-6));
    expect(hp.pitch, closeTo(-12, 1e-6));
    expect(hp.roll, closeTo(7, 1e-6));
  });

  test('ignores uniform scale in the matrix', () {
    final hp = headPoseFromMatrix(matrix(-40, 5, 0, scale: 12.5))!;
    expect(hp.yaw, closeTo(-40, 1e-6));
  });

  test('rejects malformed input', () {
    expect(headPoseFromMatrix([1, 2, 3]), isNull);
    expect(headPoseFromMatrix(List.filled(16, 0)), isNull);
  });
}
