import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_poc/analysis/inference.dart';
import 'package:movement_poc/analysis/movement_analyzer.dart';
import 'package:movement_poc/models/landmark.dart';

/// Front-facing standing person, image coords. Person's left = image right.
Map<int, Landmark> standing() => {
      Pose.nose: const Landmark(0.5, 0.2),
      Pose.leftEye: const Landmark(0.53, 0.18),
      Pose.rightEye: const Landmark(0.47, 0.18),
      Pose.leftEar: const Landmark(0.57, 0.2),
      Pose.rightEar: const Landmark(0.43, 0.2),
      Pose.leftShoulder: const Landmark(0.6, 0.3),
      Pose.rightShoulder: const Landmark(0.4, 0.3),
      Pose.leftElbow: const Landmark(0.65, 0.45),
      Pose.rightElbow: const Landmark(0.35, 0.45),
      Pose.leftWrist: const Landmark(0.65, 0.6),
      Pose.rightWrist: const Landmark(0.35, 0.6),
      Pose.leftHip: const Landmark(0.57, 0.62),
      Pose.rightHip: const Landmark(0.43, 0.62),
      Pose.leftKnee: const Landmark(0.57, 0.84),
      Pose.rightKnee: const Landmark(0.43, 0.84),
      Pose.leftAnkle: const Landmark(0.57, 1.0),
      Pose.rightAnkle: const Landmark(0.43, 1.0),
    };

DetectionFrame frame(Map<int, Landmark> pts, int t, {FaceFrame? face}) {
  final list = List<Landmark?>.filled(Pose.count, null);
  pts.forEach((i, l) => list[i] = l);
  return DetectionFrame(timestampMs: t, aspect: 1, pose: list, face: face);
}

/// Feeds [n] frames ~33 ms apart, returning the last result and all events.
(AnalysisResult, List<MovementEvent>) run(MovementAnalyzer a, int n, Map<int, Landmark> Function(int i) pose,
    {int start = 0, FaceFrame? face}) {
  late AnalysisResult r;
  final events = <MovementEvent>[];
  for (var i = 0; i < n; i++) {
    r = a.analyze(frame(pose(i), start + i * 33, face: face));
    events.addAll(r.newEvents);
  }
  return (r, events);
}

bool has(AnalysisResult r, String id) => r.inferences.any((i) => i.id == id);

void main() {
  late MovementAnalyzer analyzer;
  setUp(() => analyzer = MovementAnalyzer(config: const AnalyzerConfig(sedentarySeconds: 2)));

  test('reports no person when landmarks are missing', () {
    final r = analyzer.analyze(frame({}, 0));
    expect(r.personVisible, isFalse);
    expect(r.inferences, isEmpty);
  });

  test('standing, still, upper body fully visible', () {
    final (r, _) = run(analyzer, 10, (_) => standing());
    expect(r.personVisible, isTrue);
    expect(has(r, 'stance_Standing'), isTrue);
    expect(has(r, 'still'), isTrue);
  });

  test('detects sitting when thighs are foreshortened', () {
    final (r, _) = run(analyzer, 10, (_) => standing()..[Pose.leftKnee] = const Landmark(0.57, 0.7)..[Pose.rightKnee] = const Landmark(0.43, 0.7)..remove(Pose.leftAnkle)..remove(Pose.rightAnkle));
    expect(has(r, 'stance_Sitting'), isTrue);
  });

  test('a lunge is not mistaken for sitting', () {
    // Front (person-left) knee bent ~95deg, back leg straight and stretched
    // sideways, so its *vertical* thigh extent is small like a seated thigh.
    final (r, _) = run(analyzer, 10, (_) => standing()
      ..[Pose.leftKnee] = const Landmark(0.75, 0.8)
      ..[Pose.leftAnkle] = const Landmark(0.6, 0.98)
      ..[Pose.rightKnee] = const Landmark(0.3, 0.8)
      ..[Pose.rightAnkle] = const Landmark(0.17, 0.98));
    expect(has(r, 'stance_Lunging'), isTrue);
    expect(has(r, 'stance_Sitting'), isFalse);
  });

  test('detects squatting from knee angle', () {
    final (r, _) = run(analyzer, 10, (_) => standing()
      ..[Pose.leftKnee] = const Landmark(0.7, 0.8)
      ..[Pose.rightKnee] = const Landmark(0.3, 0.8)
      ..[Pose.leftAnkle] = const Landmark(0.57, 0.95)
      ..[Pose.rightAnkle] = const Landmark(0.43, 0.95));
    expect(has(r, 'stance_Squatting'), isTrue);
  });

  test('raised hands are attributed to the correct side', () {
    var (r, _) = run(analyzer, 6, (_) => standing()..[Pose.leftWrist] = const Landmark(0.65, 0.1));
    expect(has(r, 'left_up'), isTrue);
    expect(has(r, 'right_up'), isFalse);

    (r, _) = run(analyzer, 6, (_) => standing()
      ..[Pose.leftWrist] = const Landmark(0.65, 0.1)
      ..[Pose.rightWrist] = const Landmark(0.35, 0.1), start: 1000);
    expect(has(r, 'both_up'), isTrue);
    expect(has(r, 'left_up'), isFalse);
  });

  test('detects crossed arms', () {
    final (r, _) = run(analyzer, 6, (_) => standing()
      ..[Pose.leftWrist] = const Landmark(0.45, 0.45)
      ..[Pose.rightWrist] = const Landmark(0.55, 0.45));
    expect(has(r, 'arms_crossed'), isTrue);
  });

  test('detects leaning when shoulders tilt', () {
    final (r, _) = run(analyzer, 6, (_) => standing()..[Pose.leftShoulder] = const Landmark(0.6, 0.36));
    expect(has(r, 'lean_l'), isTrue);
    expect(has(r, 'lean_r'), isFalse);
  });

  test('fires a wave event for a raised, oscillating hand', () {
    final (_, events) = run(analyzer, 45, (i) {
      final dx = (i ~/ 6).isEven ? 0.05 : -0.05;
      return standing()
        ..[Pose.rightElbow] = const Landmark(0.35, 0.2)
        ..[Pose.rightWrist] = Landmark(0.35 + dx, 0.1);
    });
    expect(events.where((e) => e.label.contains('Wave')), isNotEmpty);
  });

  test('does not report a wave for a static raised hand', () {
    final (_, events) = run(analyzer, 45, (_) => standing()
      ..[Pose.rightElbow] = const Landmark(0.35, 0.2)
      ..[Pose.rightWrist] = const Landmark(0.35, 0.1));
    expect(events.where((e) => e.label.contains('Wave')), isEmpty);
  });

  test('distinguishes nodding from head shaking', () {
    final (_, nod) = run(analyzer, 40, (i) => standing()..[Pose.nose] = Landmark(0.5, 0.2 + ((i ~/ 4).isEven ? 0.015 : -0.015)));
    expect(nod.map((e) => e.label), contains(contains('nod')));
    expect(nod.map((e) => e.label), isNot(contains(contains('shake'))));

    final fresh = MovementAnalyzer();
    final (_, shake) = run(fresh, 40, (i) => standing()..[Pose.nose] = Landmark(0.5 + ((i ~/ 4).isEven ? 0.02 : -0.02), 0.2));
    expect(shake.map((e) => e.label), contains(contains('shake')));
  });

  test('detects a jump from fast upward body motion', () {
    final (_, events) = run(analyzer, 14, (i) {
      final dy = i < 4 ? 0.0 : -0.035 * (i - 3);
      final m = standing();
      return m.map((k, v) => MapEntry(k, Landmark(v.x, v.y + dy)));
    });
    expect(events.where((e) => e.label.contains('Jump')), isNotEmpty);
  });

  test('slouch is only judged after calibration, and recovers', () {
    var (r, _) = run(analyzer, 6, (_) => standing());
    expect(has(r, 'slouch'), isFalse);
    expect(analyzer.calibrateUpright(), isTrue);

    (r, _) = run(analyzer, 6, (_) => standing()..[Pose.nose] = const Landmark(0.5, 0.27), start: 1000);
    expect(has(r, 'slouch'), isTrue);
    expect(has(r, 'upright'), isFalse);

    (r, _) = run(analyzer, 6, (_) => standing(), start: 2000);
    expect(has(r, 'slouch'), isFalse);
    expect(has(r, 'upright'), isTrue);
  });

  test('calibration requires a visible person', () {
    expect(analyzer.calibrateUpright(), isFalse);
  });

  test('reads smile and surprise from blendshapes', () {
    var (r, _) = run(analyzer, 6, (_) => standing(), face: const FaceFrame(blendshapes: {'mouthSmileLeft': 0.8, 'mouthSmileRight': 0.7}));
    expect(has(r, 'smile'), isTrue);

    (r, _) = run(analyzer, 6, (_) => standing(), start: 1000, face: const FaceFrame(blendshapes: {'jawOpen': 0.7, 'browInnerUp': 0.8}));
    expect(has(r, 'surprise'), isTrue);
    expect(has(r, 'smile'), isFalse);
  });

  test('uses face head pose to flag looking away', () {
    final (r, _) = run(analyzer, 6, (_) => standing(), face: const FaceFrame(blendshapes: {'jawOpen': 0}, headPose: HeadPose(yaw: 45)));
    expect(has(r, 'look_away'), isTrue);
  });

  test('flags drowsiness after sustained eye closure', () {
    final (r, _) = run(analyzer, 70, (_) => standing(), face: const FaceFrame(blendshapes: {'eyeBlinkLeft': 0.9, 'eyeBlinkRight': 0.9}));
    expect(has(r, 'drowsy'), isTrue);
  });

  test('counts a blink once, not per frame', () {
    var i = 0;
    run(analyzer, 30, (_) => standing(), face: null);
    for (final v in [0.0, 0.9, 0.9, 0.9, 0.0, 0.0]) {
      analyzer.analyze(frame(standing(), 2000 + 33 * i++, face: FaceFrame(blendshapes: {'eyeBlinkLeft': v, 'eyeBlinkRight': v})));
    }
    expect(analyzer.totalBlinks, 1);
  });

  test('suggests a stretch after prolonged stillness', () {
    final (r, events) = run(analyzer, 120, (_) => standing());
    expect(has(r, 'sedentary'), isTrue);
    expect(events.where((e) => e.label.contains('stretch')).length, 1);
  });

  test('moving around raises the activity level', () {
    // Sway side to side, ~1 s period, amplitude 0.05 (~0.25 shoulder widths each way).
    final (r, _) = run(analyzer, 90, (i) {
      final dx = 0.05 * math.sin(i * 33 / 1000 * 2 * math.pi);
      return standing().map((k, v) => MapEntry(k, Landmark(v.x + dx, v.y)));
    });
    expect(r.activityLevel, greaterThan(0.3));
    expect(has(r, 'active'), isTrue);
  });

  test('per-frame landmark jitter at 30 fps is not mistaken for movement', () {
    final (r, _) = run(analyzer, 150, (i) {
      final dx = math.sin(i * 12.9898) * 0.003, dy = math.cos(i * 78.233) * 0.003;
      return standing().map((k, v) => MapEntry(k, Landmark(v.x + dx * ((k % 3) - 1), v.y + dy * ((k % 2) * 2 - 1))));
    });
    expect(r.activityLevel, lessThan(0.06));
    expect(has(r, 'still'), isTrue);
  });

  test('respects non-square aspect ratio when judging tilt', () {
    // A 2:1 frame stretches x, so a given dy yields a much smaller angle.
    final pose = standing()..[Pose.leftShoulder] = const Landmark(0.6, 0.35);
    final list = List<Landmark?>.filled(Pose.count, null);
    pose.forEach((i, l) => list[i] = l);
    MovementAnalyzer a() => MovementAnalyzer();
    late AnalysisResult wide, square;
    final w = a(), s = a();
    for (var i = 0; i < 6; i++) {
      wide = w.analyze(DetectionFrame(timestampMs: i * 33, aspect: 2, pose: list));
      square = s.analyze(DetectionFrame(timestampMs: i * 33, aspect: 1, pose: list));
    }
    expect(has(square, 'lean_l'), isTrue);
    expect(has(wide, 'lean_l'), isFalse);
  });
}
