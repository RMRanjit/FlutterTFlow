import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../models/head_pose_math.dart';
import '../models/landmark.dart';
import 'motion_detector.dart';

MotionDetector createDetector() => WebMotionDetector();

@JS('motionBridge')
external _Bridge get _bridge;

extension type _Bridge._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> init();
  external JSPromise<JSAny?> startCamera(web.HTMLVideoElement video);
  external void stopCamera(web.HTMLVideoElement video);
  external JSString? detect(web.HTMLVideoElement video, double timestampMs);
}

/// Web backend: MediaPipe Tasks (TFLite models running in WASM/WebGL) fed by a
/// `<video>` element that Flutter hosts as a platform view.
class WebMotionDetector implements MotionDetector {
  WebMotionDetector() {
    _viewType = 'motion-video-${identityHashCode(this)}';
    _video = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'fill'
      ..style.transform = 'scaleX(-1)'; // selfie view
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _video);
  }

  late final String _viewType;
  late final web.HTMLVideoElement _video;
  final _frames = StreamController<DetectionFrame>.broadcast();
  final _aspect = ValueNotifier<double>(4 / 3);
  bool _running = false;
  int _rafId = 0;
  double _lastVideoTime = -1;

  @override
  String get backendName => 'MediaPipe · TFLite (WASM)';

  @override
  bool get supportsFaceExpressions => true;

  @override
  bool get mirrored => true;

  @override
  ValueListenable<double> get aspect => _aspect;

  @override
  Stream<DetectionFrame> get frames => _frames.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    try {
      await _bridge.init().toDart;
      await _bridge.startCamera(_video).toDart;
    } on Object catch (e) {
      throw DetectorException(_cleanError(e));
    }
    _running = true;
    _rafId = web.window.requestAnimationFrame(_tick.toJS);
  }

  void _tick(double now) {
    if (!_running) return;
    // Only run inference when the camera produced a new frame.
    if (_video.currentTime != _lastVideoTime) {
      _lastVideoTime = _video.currentTime;
      try {
        final sw = Stopwatch()..start();
        final json = _bridge.detect(_video, now);
        sw.stop();
        if (json != null) _emit(jsonDecode(json.toDart) as Map<String, dynamic>, now, sw.elapsedMicroseconds / 1000);
      } on Object catch (e, st) {
        debugPrint('Detection error: $e\n$st');
      }
    }
    _rafId = web.window.requestAnimationFrame(_tick.toJS);
  }

  void _emit(Map<String, dynamic> m, double now, double ms) {
    final w = (m['w'] as num).toDouble(), h = (m['h'] as num).toDouble();
    final aspect = w / h;
    if ((_aspect.value - aspect).abs() > 0.001) _aspect.value = aspect;

    List<Landmark?>? pose;
    final rawPose = m['pose'] as List?;
    if (rawPose != null) {
      pose = [
        for (final l in rawPose)
          Landmark((l[0] as num).toDouble(), (l[1] as num).toDouble(), z: (l[2] as num).toDouble(), score: (l[3] as num).toDouble()),
      ];
    }

    FaceFrame? face;
    final rawFace = m['face'] as Map<String, dynamic>?;
    if (rawFace != null) {
      final matrix = (rawFace['matrix'] as List?)?.cast<num>();
      face = FaceFrame(
        blendshapes: {for (final e in (rawFace['blend'] as Map<String, dynamic>).entries) e.key: (e.value as num).toDouble()},
        headPose: matrix == null ? null : headPoseFromMatrix(matrix),
        outline: [for (final p in rawFace['outline'] as List) Landmark((p[0] as num).toDouble(), (p[1] as num).toDouble())],
      );
    }

    _frames.add(DetectionFrame(timestampMs: now.round(), aspect: aspect, pose: pose, face: face, inferenceMs: ms));
  }

  String _cleanError(Object e) {
    final s = e.toString();
    // JS errors surface as "Exception: Error: msg" or similar; keep the message.
    return s.replaceFirst(RegExp(r'^(Exception: )?(Error: )?'), '');
  }

  @override
  Future<void> stop() async {
    _running = false;
    web.window.cancelAnimationFrame(_rafId);
    _bridge.stopCamera(_video);
    _lastVideoTime = -1;
  }

  @override
  Widget buildPreview(BuildContext context) => HtmlElementView(viewType: _viewType);

  @override
  void dispose() {
    stop();
    _frames.close();
    _aspect.dispose();
  }
}
