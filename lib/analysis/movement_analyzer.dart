import 'dart:math' as math;

import '../models/landmark.dart';
import 'inference.dart';

/// Tunable thresholds. Distances are expressed in shoulder widths so they are
/// independent of how far the person stands from the camera.
class AnalyzerConfig {
  const AnalyzerConfig({
    this.minScore = 0.4,
    this.handRaiseMargin = 0.25,
    this.leanDegrees = 10,
    this.headTiltDegrees = 15,
    this.lookAwayDegrees = 30,
    this.slouchRatio = 0.75,
    this.sedentarySeconds = 60,
    this.slouchSeconds = 8,
    this.eyesClosedSeconds = 1.5,
    this.stableFrames = 3,
    this.eventCooldownMs = 2000,
  });

  /// Landmarks below this score are treated as missing.
  final double minScore;
  final double handRaiseMargin;
  final double leanDegrees;
  final double headTiltDegrees;
  final double lookAwayDegrees;

  /// Slouch when nose-to-shoulder distance falls below this fraction of the
  /// calibrated upright value.
  final double slouchRatio;
  final double sedentarySeconds;
  final double slouchSeconds;
  final double eyesClosedSeconds;

  /// Frames a raw condition must hold before it becomes visible (debounce).
  final int stableFrames;
  final int eventCooldownMs;
}

/// Turns raw landmarks into higher-level inferences: posture, gestures, motion
/// and (when blendshapes are available) facial expression. Pure Dart, no
/// platform dependencies, so it is shared by every backend and unit-testable.
class MovementAnalyzer {
  MovementAnalyzer({this.config = const AnalyzerConfig(), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AnalyzerConfig config;
  final DateTime Function() _clock;

  static const _windowMs = 1500;
  static const _speedBaselineMs = 250;
  static const _jitterFloor = 0.04;

  final _stable = <String, _Debounce>{};
  final _cooldownUntil = <String, int>{};
  final _wristX = _Series();
  final _noseX = _Series();
  final _noseY = _Series();
  final _bodyY = _Series();
  final _poseHistory = <(int, List<Landmark?>)>[];
  double _activity = 0;
  int? _lastSeenMs;
  double? _upright;
  double _latestNeckRatio = 0;
  int? _stillSince;
  int? _slouchSince;
  int? _eyesClosedSince;
  bool _blinkLatched = false;
  bool _stretchAlerted = false;
  int _blinkCount = 0;
  final _blinkTimes = <int>[];

  /// Remember the current head-to-shoulder distance as "sitting upright".
  /// Returns false if no person is currently measurable.
  bool calibrateUpright() {
    if (_latestNeckRatio <= 0) return false;
    _upright = _latestNeckRatio;
    return true;
  }

  bool get isCalibrated => _upright != null;

  void reset() {
    _stable.clear();
    _cooldownUntil.clear();
    for (final s in [_wristX, _noseX, _noseY, _bodyY]) {
      s.clear();
    }
    _poseHistory.clear();
    _activity = 0;
    _stillSince = _slouchSince = _eyesClosedSince = null;
    _stretchAlerted = false;
  }

  AnalysisResult analyze(DetectionFrame f) {
    final t = f.timestampMs;
    final ls = f.joint(Pose.leftShoulder), rs = f.joint(Pose.rightShoulder);
    final nose = f.joint(Pose.nose);
    final visible = _ok(ls) && _ok(rs) && _ok(nose);

    if (!visible) {
      final lastSeen = _lastSeenMs;
      if (lastSeen != null && t - lastSeen > 1000) reset();
      return const AnalysisResult();
    }
    _lastSeenMs = t;

    final a = f.aspect;
    // Work in aspect-corrected space so angles/distances are isotropic.
    math.Point<double> p(Landmark l) => math.Point(l.x * a, l.y);
    final pls = p(ls!), prs = p(rs!), pn = p(nose!);
    final sw = pls.distanceTo(prs);
    if (sw < 1e-4) return const AnalysisResult();
    final mid = math.Point((pls.x + prs.x) / 2, (pls.y + prs.y) / 2);

    final states = <Inference>[];
    final events = <MovementEvent>[];

    void state(String id, bool raw, Inference Function() build) {
      final d = _stable.putIfAbsent(id, () => _Debounce(config.stableFrames));
      if (d.update(raw)) states.add(build());
    }

    void fire(String id, String label, {Severity severity = Severity.info}) {
      if ((_cooldownUntil[id] ?? 0) > t) return;
      _cooldownUntil[id] = t + config.eventCooldownMs;
      events.add(MovementEvent(_clock(), label, severity: severity));
    }

    // ---- Posture ---------------------------------------------------------
    final lean = math.atan2(pls.y - prs.y, pls.x - prs.x) * 180 / math.pi;
    // Person's left shoulder is on the image's right; lower => leaning left.
    state('lean_l', lean > config.leanDegrees, () => Inference(InferenceKind.posture, 'lean_l', 'Leaning left', detail: '${lean.abs().round()}° shoulder tilt'));
    state('lean_r', lean < -config.leanDegrees, () => Inference(InferenceKind.posture, 'lean_r', 'Leaning right', detail: '${lean.abs().round()}° shoulder tilt'));

    final stance = _stance(f, mid, sw, a);
    if (stance != null) {
      state('stance_${stance.$1}', true, () => Inference(InferenceKind.posture, 'stance_${stance.$1}', stance.$1, detail: stance.$2));
    } else {
      state('upper_only', true, () => const Inference(InferenceKind.posture, 'upper_only', 'Upper body in view', detail: 'Hips/legs out of view'));
    }

    final neckRatio = (mid.y - pn.y) / sw;
    _latestNeckRatio = neckRatio;
    final upright = _upright;
    final slouching = upright != null && neckRatio < upright * config.slouchRatio;
    state('slouch', slouching, () => const Inference(InferenceKind.posture, 'slouch', 'Slouching', detail: 'Head dropped toward shoulders', severity: Severity.warning));
    if (upright != null && !slouching) {
      state('upright', true, () => const Inference(InferenceKind.posture, 'upright', 'Good posture', severity: Severity.good));
    }

    final headRoll = _headRoll(f, a);
    state('head_tilt', headRoll != null && headRoll.abs() > config.headTiltDegrees, () => Inference(InferenceKind.posture, 'head_tilt', 'Head tilted', detail: '${headRoll!.abs().round()}°'));

    final away = _lookingAway(f);
    state('look_away', away != null && away, () => const Inference(InferenceKind.face, 'look_away', 'Looking away from screen'));

    // ---- Gestures --------------------------------------------------------
    final lw = f.joint(Pose.leftWrist), rw = f.joint(Pose.rightWrist);
    final le = f.joint(Pose.leftElbow), re = f.joint(Pose.rightElbow);
    final margin = config.handRaiseMargin * sw;
    final leftUp = _ok(lw) && p(lw!).y < pls.y - margin;
    final rightUp = _ok(rw) && (p(rw!).y < prs.y - margin);
    state('both_up', leftUp && rightUp, () => const Inference(InferenceKind.gesture, 'both_up', 'Both hands raised'));
    state('left_up', leftUp && !rightUp, () => const Inference(InferenceKind.gesture, 'left_up', 'Left hand raised'));
    state('right_up', rightUp && !leftUp, () => const Inference(InferenceKind.gesture, 'right_up', 'Right hand raised'));

    if (_ok(lw) && _ok(rw)) {
      final plw = p(lw!), prw = p(rw!);
      // Person's left is on image right (larger x); crossed => left wrist is
      // left of the body midline and right wrist is right of it.
      final crossed = plw.x < mid.x - 0.1 * sw && prw.x > mid.x + 0.1 * sw && plw.y > mid.y && prw.y > mid.y && plw.y < mid.y + 2.2 * sw && prw.y < mid.y + 2.2 * sw;
      state('arms_crossed', crossed, () => const Inference(InferenceKind.gesture, 'arms_crossed', 'Arms crossed'));
    }

    // Wave: a raised hand oscillating sideways.
    final waveHand = leftUp ? lw : (rightUp ? rw : null);
    final waveElbow = leftUp ? le : (rightUp ? re : null);
    if (waveHand != null && _ok(waveElbow)) {
      _wristX.add(t, (p(waveHand).x - p(waveElbow!).x) / sw, _windowMs);
      if (_reversals(_wristX.values, 0.12) >= 3) {
        fire('wave', 'Wave detected 👋');
        _wristX.clear();
      }
    } else {
      _wristX.clear();
    }

    // Nod / shake from nose motion relative to shoulders.
    _noseX.add(t, (pn.x - mid.x) / sw, _windowMs);
    _noseY.add(t, (pn.y - mid.y) / sw, _windowMs);
    final ry = _reversals(_noseY.values, 0.035), rx = _reversals(_noseX.values, 0.05);
    final rangeY = _noseY.range, rangeX = _noseX.range;
    if (ry >= 3 && rangeY > rangeX) {
      fire('nod', 'Head nod (yes)');
      _noseY.clear();
    } else if (rx >= 3 && rangeX > rangeY) {
      fire('shake', 'Head shake (no)');
      _noseX.clear();
    }

    // Jump: fast upward body movement.
    final lh = f.joint(Pose.leftHip), rh = f.joint(Pose.rightHip);
    final bodyY = (_ok(lh) && _ok(rh)) ? ((lh!.y + rh!.y) / 2) : mid.y;
    _bodyY.add(t, bodyY / sw, 500);
    final bv = _bodyY.values;
    if (bv.length > 3 && (bv.last.$2 - bv.first.$2) < -0.45 * (_ok(lh) ? 1.2 : 0.6)) {
      fire('jump', 'Jump detected');
      _bodyY.clear();
    }

    // ---- Overall motion --------------------------------------------------
    final speed = _speed(f, sw);
    _activity = _activity * 0.9 + (speed / 1.2).clamp(0.0, 1.0) * 0.1;
    final lvl = _activity;
    state('still', lvl < 0.06, () => const Inference(InferenceKind.motion, 'still', 'Still'));
    state('light', lvl >= 0.06 && lvl < 0.3, () => const Inference(InferenceKind.motion, 'light', 'Light movement'));
    state('active', lvl >= 0.3, () => const Inference(InferenceKind.motion, 'active', 'Active', severity: Severity.good));

    // ---- Face ------------------------------------------------------------
    final face = f.face;
    if (face != null && face.hasBlendshapes) {
      final smile = (face.blend('mouthSmileLeft') + face.blend('mouthSmileRight')) / 2;
      final blink = (face.blend('eyeBlinkLeft') + face.blend('eyeBlinkRight')) / 2;
      final jaw = face.blend('jawOpen');
      final brows = math.max(face.blend('browInnerUp'), (face.blend('browOuterUpLeft') + face.blend('browOuterUpRight')) / 2);
      state('smile', smile > 0.5, () => Inference(InferenceKind.face, 'smile', 'Smiling', detail: '${(smile * 100).round()}%', severity: Severity.good));
      state('surprise', jaw > 0.4 && brows > 0.4, () => const Inference(InferenceKind.face, 'surprise', 'Surprised'));
      state('mouth_open', jaw > 0.4 && brows <= 0.4, () => const Inference(InferenceKind.face, 'mouth_open', 'Mouth open', detail: 'Talking or yawning'));
      state('brows', brows > 0.5 && jaw <= 0.4, () => const Inference(InferenceKind.face, 'brows', 'Eyebrows raised'));

      if (blink > 0.55 && !_blinkLatched) {
        _blinkLatched = true;
        _blinkCount++;
        _blinkTimes.add(t);
      } else if (blink < 0.3) {
        _blinkLatched = false;
      }
      _blinkTimes.removeWhere((x) => t - x > 60000);
      if (blink > 0.6) {
        _eyesClosedSince ??= t;
      } else {
        _eyesClosedSince = null;
      }
    } else {
      _eyesClosedSince = null;
    }

    // ---- Wellbeing (sustained conditions) --------------------------------
    final closedFor = _eyesClosedSince == null ? 0.0 : (t - _eyesClosedSince!) / 1000;
    state('drowsy', closedFor > config.eyesClosedSeconds, () => const Inference(InferenceKind.wellbeing, 'drowsy', 'Eyes closed – possible drowsiness', severity: Severity.warning));

    if (slouching) {
      _slouchSince ??= t;
    } else {
      _slouchSince = null;
    }
    final slouchFor = _slouchSince == null ? 0.0 : (t - _slouchSince!) / 1000;
    state('bad_posture', slouchFor > config.slouchSeconds, () => Inference(InferenceKind.wellbeing, 'bad_posture', 'Posture check', detail: 'Slouching for ${slouchFor.round()}s – sit up straight', severity: Severity.warning));

    if (lvl < 0.06) {
      _stillSince ??= t;
    } else {
      _stillSince = null;
      _stretchAlerted = false;
    }
    final stillFor = _stillSince == null ? 0.0 : (t - _stillSince!) / 1000;
    final sedentary = stillFor > config.sedentarySeconds;
    state('sedentary', sedentary, () => Inference(InferenceKind.wellbeing, 'sedentary', 'Time to stretch', detail: 'Barely moved for ${stillFor.round()}s', severity: Severity.warning));
    if (sedentary && !_stretchAlerted) {
      _stretchAlerted = true;
      events.add(MovementEvent(_clock(), 'Sedentary for ${config.sedentarySeconds.round()}s – suggest a stretch', severity: Severity.warning));
    }

    final pose = f.pose;
    if (pose != null) _poseHistory.add((t, pose));
    return AnalysisResult(inferences: states, newEvents: events, activityLevel: lvl, personVisible: true);
  }

  /// Blinks in the last minute (web backend only).
  int get blinksPerMinute => _blinkTimes.length;
  int get totalBlinks => _blinkCount;

  // ---------------------------------------------------------------------------

  bool _ok(Landmark? l) => l != null && l.score >= config.minScore;

  /// (label, detail) or null when the lower body is not in view.
  (String, String)? _stance(DetectionFrame f, math.Point<double> mid, double sw, double a) {
    final lh = f.joint(Pose.leftHip), rh = f.joint(Pose.rightHip);
    final lk = f.joint(Pose.leftKnee), rk = f.joint(Pose.rightKnee);
    if (!(_ok(lh) && _ok(rh) && _ok(lk) && _ok(rk))) return null;
    math.Point<double> p(Landmark l) => math.Point(l.x * a, l.y);
    final hipMid = math.Point((p(lh!).x + p(rh!).x) / 2, (p(lh).y + p(rh).y) / 2);
    final torso = hipMid.distanceTo(mid);
    if (torso < 1e-4) return null;
    // Use true segment length (not just vertical extent) so a leg stretched
    // sideways in a lunge is not mistaken for a foreshortened, seated thigh.
    final thighL = p(lk!).distanceTo(p(lh)) / torso, thighR = p(rk!).distanceTo(p(rh)) / torso;
    final seated = math.max(thighL, thighR) < 0.55;

    final la = f.joint(Pose.leftAnkle), ra = f.joint(Pose.rightAnkle);
    if (_ok(la) && _ok(ra)) {
      final kl = _angle(p(lh), p(lk), p(la!)), kr = _angle(p(rh), p(rk), p(ra!));
      final knee = (kl + kr) / 2;
      if (seated) return ('Sitting', 'Thighs foreshortened');
      if (math.min(kl, kr) < 120 && math.max(kl, kr) > 150) return ('Lunging', 'Knee angles ${kl.round()}° / ${kr.round()}°');
      if (knee < 120) return ('Squatting', 'Knee angle ${knee.round()}°');
      return ('Standing', 'Knee angle ${knee.round()}°');
    }
    return seated ? ('Sitting', 'Thighs foreshortened') : ('Standing', 'Legs extended');
  }

  /// Angle at [b] formed by a-b-c, in degrees.
  double _angle(math.Point<double> a, math.Point<double> b, math.Point<double> c) {
    final v1 = a - b, v2 = c - b;
    final dot = v1.x * v2.x + v1.y * v2.y;
    final m = math.sqrt(v1.x * v1.x + v1.y * v1.y) * math.sqrt(v2.x * v2.x + v2.y * v2.y);
    if (m < 1e-9) return 180;
    return math.acos((dot / m).clamp(-1.0, 1.0)) * 180 / math.pi;
  }

  /// Head roll in degrees, from face pose when available, else eye line.
  double? _headRoll(DetectionFrame f, double a) {
    final hp = f.face?.headPose;
    if (hp != null) return hp.roll;
    final le = f.joint(Pose.leftEye), re = f.joint(Pose.rightEye);
    if (!(_ok(le) && _ok(re))) return null;
    return math.atan2((le!.y - re!.y), (le.x - re.x) * a) * 180 / math.pi;
  }

  /// True when the head is turned well away from the camera.
  bool? _lookingAway(DetectionFrame f) {
    final hp = f.face?.headPose;
    if (hp != null) return hp.yaw.abs() > config.lookAwayDegrees;
    final nose = f.joint(Pose.nose);
    final le = f.joint(Pose.leftEar), re = f.joint(Pose.rightEar);
    if (!(_ok(nose) && _ok(le) && _ok(re))) return null;
    final half = (le!.x - re!.x).abs() / 2;
    if (half < 1e-4) return null;
    final off = (nose!.x - (le.x + re.x) / 2).abs() / half;
    return off > 0.7;
  }

  /// Mean joint speed in shoulder-widths per second.
  ///
  /// Landmark jitter is roughly constant per frame, so differencing consecutive
  /// frames would turn it into a large fake "speed" at high frame rates.
  /// Instead compare with the pose from ~[_speedBaselineMs] ago and ignore
  /// displacements below [_jitterFloor] shoulder widths.
  double _speed(DetectionFrame f, double sw) {
    final cur = f.pose;
    if (cur == null) return 0;
    _poseHistory.removeWhere((e) => f.timestampMs - e.$1 > _speedBaselineMs * 2);
    (int, List<Landmark?>)? base;
    for (final e in _poseHistory) {
      if (f.timestampMs - e.$1 >= _speedBaselineMs) base = e; // newest one that is old enough
    }
    if (base == null) return 0;
    final dt = (f.timestampMs - base.$1) / 1000;
    final prev = base.$2;
    const joints = [Pose.nose, Pose.leftShoulder, Pose.rightShoulder, Pose.leftElbow, Pose.rightElbow, Pose.leftWrist, Pose.rightWrist, Pose.leftHip, Pose.rightHip];
    var sum = 0.0;
    var n = 0;
    for (final j in joints) {
      final c = j < cur.length ? cur[j] : null;
      final o = j < prev.length ? prev[j] : null;
      if (!_ok(c) || !_ok(o)) continue;
      final dx = (c!.x - o!.x) * f.aspect, dy = c.y - o.y;
      final disp = math.sqrt(dx * dx + dy * dy) / sw;
      sum += math.max(0.0, disp - _jitterFloor);
      n++;
    }
    if (n == 0) return 0;
    return (sum / n) / dt;
  }

  /// Number of direction changes whose swing exceeds [minAmp].
  int _reversals(List<(int, double)> s, double minAmp) {
    if (s.length < 3) return 0;
    var extreme = s.first.$2;
    var dir = 0;
    var count = 0;
    for (final (_, v) in s.skip(1)) {
      if (dir >= 0 && v < extreme - minAmp) {
        if (dir == 1) count++;
        dir = -1;
        extreme = v;
      } else if (dir <= 0 && v > extreme + minAmp) {
        if (dir == -1) count++;
        dir = 1;
        extreme = v;
      } else if (dir == 1 && v > extreme) {
        extreme = v;
      } else if (dir == -1 && v < extreme) {
        extreme = v;
      }
    }
    return count;
  }
}

/// Sliding time window of (timestampMs, value).
class _Series {
  final values = <(int, double)>[];

  void add(int t, double v, int windowMs) {
    values.add((t, v));
    while (values.isNotEmpty && t - values.first.$1 > windowMs) {
      values.removeAt(0);
    }
  }

  double get range {
    if (values.isEmpty) return 0;
    var lo = values.first.$2, hi = lo;
    for (final (_, v) in values) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    return hi - lo;
  }

  void clear() => values.clear();
}

/// Requires a raw boolean to hold for [frames] consecutive updates before it
/// turns on, and to be false for as many before it turns off.
class _Debounce {
  _Debounce(this.frames);

  final int frames;
  bool _on = false;
  int _run = 0;

  bool update(bool raw) {
    if (raw == _on) {
      _run = 0;
    } else if (++_run >= frames) {
      _on = raw;
      _run = 0;
    }
    return _on;
  }
}
