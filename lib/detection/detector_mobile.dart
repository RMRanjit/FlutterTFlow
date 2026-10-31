import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/landmark.dart';
import 'frame_preprocessor.dart';
import 'motion_detector.dart';

MotionDetector createDetector() => MobileMotionDetector();

/// MoveNet keypoint order -> index in the shared 33-point [Pose] layout.
const _moveNetToPose = [
  Pose.nose, Pose.leftEye, Pose.rightEye, Pose.leftEar, Pose.rightEar, //
  Pose.leftShoulder, Pose.rightShoulder, Pose.leftElbow, Pose.rightElbow,
  Pose.leftWrist, Pose.rightWrist, Pose.leftHip, Pose.rightHip,
  Pose.leftKnee, Pose.rightKnee, Pose.leftAnkle, Pose.rightAnkle,
];

/// Android/iOS backend: `camera` image stream -> MoveNet Lightning on
/// `tflite_flutter`. MoveNet only tracks 17 body keypoints, so face expression
/// data (blendshapes) is unavailable here; head pose is inferred from the
/// face keypoints in the body model.
class MobileMotionDetector implements MotionDetector {
  static const _modelAsset = 'assets/models/movenet_lightning_f16.tflite';
  static const _inputSize = 192;

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  CameraController? _controller;
  CameraDescription? _camera;
  Interpreter? _interpreter;
  TensorType? _inputType;
  final _frames = StreamController<DetectionFrame>.broadcast();
  final _aspect = ValueNotifier<double>(3 / 4);
  final _input = Uint8List(_inputSize * _inputSize * 3);
  final _clock = Stopwatch();
  bool _busy = false;
  bool _running = false;

  @override
  String get backendName => 'MoveNet · TFLite (tflite_flutter)';

  @override
  bool get supportsFaceExpressions => false;

  @override
  bool get mirrored => _camera?.lensDirection == CameraLensDirection.front;

  @override
  ValueListenable<double> get aspect => _aspect;

  @override
  Stream<DetectionFrame> get frames => _frames.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    try {
      _interpreter ??= await Interpreter.fromAsset(_modelAsset, options: InterpreterOptions()..threads = 4);
      _inputType = _interpreter!.getInputTensor(0).type;
    } on Object catch (e) {
      throw DetectorException('Could not load the TFLite model: $e');
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw DetectorException('No camera was found on this device.');
      _camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      final controller = CameraController(
        _camera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      _controller = controller;
      _clock.start();
      _running = true;
      await controller.startImageStream(_onImage);
    } on CameraException catch (e) {
      throw DetectorException(e.code.contains('Denied') || e.code.contains('Restricted') ? 'Camera permission was denied.' : 'Could not open the camera: ${e.description ?? e.code}');
    }
  }

  int _rotation(CameraController c) {
    final sensor = _camera!.sensorOrientation;
    if (Platform.isIOS) return sensor;
    final device = _orientations[c.value.deviceOrientation] ?? 0;
    return _camera!.lensDirection == CameraLensDirection.front ? (sensor + device) % 360 : (sensor - device + 360) % 360;
  }

  RawFrame? _toRaw(CameraImage img) {
    final planes = [for (final p in img.planes) RawPlane(p.bytes, p.bytesPerRow, p.bytesPerPixel ?? 1)];
    switch (img.format.group) {
      case ImageFormatGroup.bgra8888:
        return RawFrame(img.width, img.height, RawFormat.bgra8888, planes);
      case ImageFormatGroup.yuv420:
        return RawFrame(img.width, img.height, RawFormat.yuv420, planes);
      case ImageFormatGroup.nv21:
        return RawFrame(img.width, img.height, RawFormat.nv21, planes);
      default:
        return null;
    }
  }

  void _onImage(CameraImage img) {
    final controller = _controller, interpreter = _interpreter;
    if (_busy || !_running || controller == null || interpreter == null) return;
    _busy = true;
    try {
      final raw = _toRaw(img);
      if (raw == null) return;
      final sw = Stopwatch()..start();
      final lb = preprocessFrame(raw, _rotation(controller), _inputSize, _input);
      final keypoints = _infer(interpreter);
      sw.stop();

      final pose = List<Landmark?>.filled(Pose.count, null);
      for (var k = 0; k < _moveNetToPose.length; k++) {
        final (y, x, score) = keypoints[k];
        final (ix, iy) = lb.toImage(x, y);
        pose[_moveNetToPose[k]] = Landmark(ix, iy, score: score);
      }
      if ((_aspect.value - lb.aspect).abs() > 0.001) _aspect.value = lb.aspect;
      _frames.add(DetectionFrame(timestampMs: _clock.elapsedMilliseconds, aspect: lb.aspect, pose: pose, inferenceMs: sw.elapsedMicroseconds / 1000));
    } on Object catch (e, st) {
      debugPrint('Detection error: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  /// Runs MoveNet; returns 17 (y, x, score) triples normalized to the input.
  List<(double, double, double)> _infer(Interpreter interpreter) {
    final Uint8List bytes;
    switch (_inputType) {
      case TensorType.float32:
        final f = Float32List(_input.length);
        for (var i = 0; i < f.length; i++) {
          f[i] = _input[i].toDouble();
        }
        bytes = f.buffer.asUint8List();
      case TensorType.int32:
        final n = Int32List(_input.length);
        for (var i = 0; i < n.length; i++) {
          n[i] = _input[i];
        }
        bytes = n.buffer.asUint8List();
      default: // uint8
        bytes = _input;
    }
    final output = [
      [
        List.generate(17, (_) => List<double>.filled(3, 0)),
      ],
    ];
    interpreter.run(bytes, output);
    return [for (final k in output[0][0]) (k[0], k[1], k[2])];
  }

  @override
  Future<void> stop() async {
    _running = false;
    final c = _controller;
    _controller = null;
    if (c != null) {
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } on Object catch (_) {}
      await c.dispose();
    }
  }

  @override
  Widget buildPreview(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return const SizedBox.shrink();
    return CameraPreview(c);
  }

  @override
  void dispose() {
    stop();
    _interpreter?.close();
    _interpreter = null;
    _frames.close();
    _aspect.dispose();
  }
}
