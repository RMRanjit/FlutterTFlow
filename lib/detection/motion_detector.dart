import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/landmark.dart';
import 'detector_stub.dart' if (dart.library.js_interop) 'detector_web.dart' if (dart.library.io) 'detector_mobile.dart' as impl;

/// Thrown with a user-presentable message when a detector cannot start
/// (camera denied, model failed to load, unsupported platform...).
class DetectorException implements Exception {
  DetectorException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A camera + TFLite pipeline that emits [DetectionFrame]s.
///
/// Implementations: MediaPipe (TFLite in WASM) on web, `tflite_flutter` +
/// MoveNet on Android/iOS. Everything above this interface is shared.
abstract class MotionDetector {
  /// Platform-appropriate detector.
  factory MotionDetector.create() => impl.createDetector();

  /// Short description shown in the UI, e.g. "MediaPipe · TFLite (WASM)".
  String get backendName;

  /// Whether this backend reports face blendshapes (expressions, blinks).
  bool get supportsFaceExpressions;

  /// Whether the preview is displayed mirrored (selfie view), in which case
  /// overlays must be mirrored too.
  bool get mirrored;

  /// Aspect ratio (w/h) of the upright preview.
  ValueListenable<double> get aspect;

  Stream<DetectionFrame> get frames;

  /// Opens the camera and loads the models. Throws [DetectorException].
  Future<void> start();

  Future<void> stop();

  /// The camera preview widget; sized by the caller to [aspect].
  Widget buildPreview(BuildContext context);

  void dispose();
}
