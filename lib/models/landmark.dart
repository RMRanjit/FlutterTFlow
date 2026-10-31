/// A single normalized landmark. x/y are in [0,1] relative to the source image
/// (x to the right, y downward); z is a relative depth hint (may be 0).
class Landmark {
  const Landmark(this.x, this.y, {this.z = 0, this.score = 1});

  final double x;
  final double y;
  final double z;

  /// Detector confidence / visibility in [0,1].
  final double score;
}

/// Indices into [PoseFrame.landmarks], following the MediaPipe 33-point body
/// topology. Left/right refer to the *person's* left/right, not the image's.
///
/// Both backends emit this layout: the web backend (MediaPipe) fills all 33
/// points, the mobile backend (MoveNet, 17 points) fills the subset below and
/// leaves the rest as null.
abstract final class Pose {
  static const nose = 0;
  static const leftEye = 2;
  static const rightEye = 5;
  static const leftEar = 7;
  static const rightEar = 8;
  static const leftShoulder = 11;
  static const rightShoulder = 12;
  static const leftElbow = 13;
  static const rightElbow = 14;
  static const leftWrist = 15;
  static const rightWrist = 16;
  static const leftHip = 23;
  static const rightHip = 24;
  static const leftKnee = 25;
  static const rightKnee = 26;
  static const leftAnkle = 27;
  static const rightAnkle = 28;

  static const count = 33;

  /// Pairs drawn as the skeleton overlay (only joints common to both backends).
  static const bones = <(int, int)>[
    (leftEar, leftEye),
    (leftEye, nose),
    (nose, rightEye),
    (rightEye, rightEar),
    (leftShoulder, rightShoulder),
    (leftShoulder, leftElbow),
    (leftElbow, leftWrist),
    (rightShoulder, rightElbow),
    (rightElbow, rightWrist),
    (leftShoulder, leftHip),
    (rightShoulder, rightHip),
    (leftHip, rightHip),
    (leftHip, leftKnee),
    (leftKnee, leftAnkle),
    (rightHip, rightKnee),
    (rightKnee, rightAnkle),
  ];
}

/// Head orientation in degrees. Positive yaw = turned to the person's left,
/// positive pitch = looking up, positive roll = head tilted to the person's
/// right shoulder.
class HeadPose {
  const HeadPose({this.yaw = 0, this.pitch = 0, this.roll = 0});

  final double yaw;
  final double pitch;
  final double roll;
}

/// Face expression data. Only the web (MediaPipe FaceLandmarker) backend
/// produces blendshape scores; on mobile [blendshapes] is empty.
class FaceFrame {
  const FaceFrame({this.blendshapes = const {}, this.headPose, this.outline = const []});

  /// ARKit-style blendshape name -> score in [0,1], e.g. `mouthSmileLeft`.
  final Map<String, double> blendshapes;
  final HeadPose? headPose;

  /// A few key face points (for drawing), normalized like [Landmark].
  final List<Landmark> outline;

  double blend(String name) => blendshapes[name] ?? 0;
  bool get hasBlendshapes => blendshapes.isNotEmpty;
}

/// Everything detected in one video frame.
class DetectionFrame {
  const DetectionFrame({
    required this.timestampMs,
    required this.aspect,
    required this.pose,
    this.face,
    this.inferenceMs = 0,
  });

  final int timestampMs;

  /// Source image width / height, needed for angle maths in non-square frames.
  final double aspect;

  /// Length [Pose.count]; entries are null when a joint was not detected.
  final List<Landmark?>? pose;
  final FaceFrame? face;
  final double inferenceMs;

  Landmark? joint(int index) {
    final p = pose;
    if (p == null || index >= p.length) return null;
    return p[index];
  }
}
