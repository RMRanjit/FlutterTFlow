import 'dart:async';

import 'package:flutter/foundation.dart';

import 'analysis/inference.dart';
import 'analysis/movement_analyzer.dart';
import 'detection/motion_detector.dart';
import 'models/landmark.dart';

enum SessionStatus { idle, starting, running, error }

/// Glue between a [MotionDetector] and the [MovementAnalyzer]. UI listens to
/// this controller (throttled) and to [frame] (every frame, for the overlay).
class SessionController extends ChangeNotifier {
  SessionController({required this.detector, MovementAnalyzer? analyzer}) : analyzer = analyzer ?? MovementAnalyzer();

  static const maxLogEntries = 60;
  static const _uiInterval = Duration(milliseconds: 66);

  final MotionDetector detector;
  final MovementAnalyzer analyzer;
  StreamSubscription<DetectionFrame>? _sub;
  final _uiClock = Stopwatch()..start();
  final _fpsClock = Stopwatch();
  int _fpsFrames = 0;
  int _lastNotifyMs = 0;
  Set<String> _prevIds = {};

  /// Latest raw frame; the skeleton painter repaints from this directly.
  final frame = ValueNotifier<DetectionFrame?>(null);

  SessionStatus status = SessionStatus.idle;
  String? error;
  AnalysisResult result = const AnalysisResult();
  final List<MovementEvent> log = [];
  double fps = 0;
  double inferenceMs = 0;
  FaceFrame? face;

  bool get running => status == SessionStatus.running;

  Future<void> start() async {
    if (status == SessionStatus.starting || running) return;
    status = SessionStatus.starting;
    error = null;
    notifyListeners();
    try {
      await detector.start();
    } on DetectorException catch (e) {
      status = SessionStatus.error;
      error = e.message;
      notifyListeners();
      return;
    } on Object catch (e) {
      status = SessionStatus.error;
      error = 'Unexpected error: $e';
      notifyListeners();
      return;
    }
    _fpsClock
      ..reset()
      ..start();
    _fpsFrames = 0;
    _sub = detector.frames.listen(_onFrame);
    status = SessionStatus.running;
    notifyListeners();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await detector.stop();
    analyzer.reset();
    _prevIds = {};
    frame.value = null;
    result = const AnalysisResult();
    face = null;
    fps = 0;
    status = SessionStatus.idle;
    notifyListeners();
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  /// Returns false if nobody is in view to calibrate against.
  bool calibratePosture() {
    final ok = analyzer.calibrateUpright();
    if (ok) {
      log.insert(0, MovementEvent(DateTime.now(), 'Upright posture calibrated', severity: Severity.good));
    }
    notifyListeners();
    return ok;
  }

  void _onFrame(DetectionFrame f) {
    frame.value = f;
    final r = analyzer.analyze(f);
    result = r;
    face = f.face;
    inferenceMs = inferenceMs == 0 ? f.inferenceMs : inferenceMs * 0.9 + f.inferenceMs * 0.1;

    _fpsFrames++;
    final elapsed = _fpsClock.elapsedMilliseconds;
    if (elapsed >= 1000) {
      fps = _fpsFrames * 1000 / elapsed;
      _fpsFrames = 0;
      _fpsClock
        ..reset()
        ..start();
    }

    var logChanged = false;
    for (final e in r.newEvents) {
      log.insert(0, e);
      logChanged = true;
    }
    final ids = {for (final i in r.inferences) i.id};
    for (final i in r.inferences) {
      if (!_prevIds.contains(i.id) && _shouldLog(i)) {
        log.insert(0, MovementEvent(DateTime.now(), i.label, severity: i.severity));
        logChanged = true;
      }
    }
    _prevIds = ids;
    if (log.length > maxLogEntries) log.removeRange(maxLogEntries, log.length);

    final now = _uiClock.elapsedMilliseconds;
    if (logChanged || now - _lastNotifyMs >= _uiInterval.inMilliseconds) {
      _lastNotifyMs = now;
      notifyListeners();
    }
  }

  // Motion level flaps constantly and "upper body" is a standing condition.
  bool _shouldLog(Inference i) => i.kind != InferenceKind.motion && i.id != 'upper_only';

  @override
  void dispose() {
    _sub?.cancel();
    detector.dispose();
    frame.dispose();
    super.dispose();
  }
}
