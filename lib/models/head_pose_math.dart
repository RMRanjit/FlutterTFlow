import 'dart:math' as math;

import 'landmark.dart';

/// Extracts yaw/pitch/roll (degrees) from a column-major 4x4 face
/// transformation matrix such as MediaPipe's `facialTransformationMatrixes`.
///
/// Uses a Y-X-Z decomposition (R = Ry(yaw) * Rx(pitch) * Rz(roll)). Scale in
/// the matrix is removed first. The analyzer only relies on the magnitudes of
/// these angles, so the sign convention of the source matrix does not matter.
HeadPose? headPoseFromMatrix(List<num> m) {
  if (m.length < 16) return null;
  final sx = math.sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2]);
  if (sx < 1e-9) return null;
  double r(int row, int col) => m[col * 4 + row] / sx;

  final pitch = math.asin((-r(1, 2)).clamp(-1.0, 1.0));
  final yaw = math.atan2(r(0, 2), r(2, 2));
  final roll = math.atan2(r(1, 0), r(1, 1));
  const deg = 180 / math.pi;
  return HeadPose(yaw: yaw * deg, pitch: pitch * deg, roll: roll * deg);
}
