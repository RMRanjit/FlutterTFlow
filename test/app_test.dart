import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movement_poc/app.dart';
import 'package:movement_poc/detection/motion_detector.dart';
import 'package:movement_poc/models/landmark.dart';
import 'package:movement_poc/ui/home_page.dart';

class FakeDetector implements MotionDetector {
  FakeDetector({this.failWith});

  final String? failWith;
  final controller = StreamController<DetectionFrame>.broadcast();
  final _aspect = ValueNotifier<double>(4 / 3);
  bool started = false, stopped = false;

  @override
  String get backendName => 'Fake · test';
  @override
  bool get supportsFaceExpressions => false;
  @override
  bool get mirrored => true;
  @override
  ValueListenable<double> get aspect => _aspect;
  @override
  Stream<DetectionFrame> get frames => controller.stream;

  @override
  Future<void> start() async {
    if (failWith != null) throw DetectorException(failWith!);
    started = true;
  }

  @override
  Future<void> stop() async => stopped = true;

  @override
  Widget buildPreview(BuildContext context) => const ColoredBox(color: Colors.grey);

  @override
  void dispose() => controller.close();

  /// Emits a person with the right hand raised.
  void emitRaisedHand(int t) {
    final l = List<Landmark?>.filled(Pose.count, null);
    l[Pose.nose] = const Landmark(0.5, 0.2);
    l[Pose.leftShoulder] = const Landmark(0.6, 0.3);
    l[Pose.rightShoulder] = const Landmark(0.4, 0.3);
    l[Pose.rightWrist] = const Landmark(0.35, 0.1);
    controller.add(DetectionFrame(timestampMs: t, aspect: 4 / 3, pose: l));
  }
}

Future<void> pumpAt(WidgetTester tester, Size size, FakeDetector d) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MovementApp(detectorFactory: () => d));
}

void main() {
  testWidgets('shows a start prompt, then live inferences after starting', (tester) async {
    final d = FakeDetector();
    await pumpAt(tester, const Size(1200, 800), d);

    expect(find.text('Start camera'), findsOneWidget);
    await tester.tap(find.text('Start camera'));
    await tester.pump();
    await tester.pump();
    expect(d.started, isTrue);
    expect(find.text('Waiting for a person to appear…'), findsOneWidget);

    for (var i = 0; i < 6; i++) {
      d.emitRaisedHand(i * 33);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Right hand raised'), findsWidgets);
    expect(find.text('Calibrate posture'), findsOneWidget);
    expect(find.text('Fake · test'), findsWidgets);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    // stop() awaits a real stream cancel, which FakeAsync alone won't run.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(d.stopped, isTrue);
    expect(find.text('Start camera'), findsOneWidget);
  });

  testWidgets('shows a friendly error with retry when the camera fails', (tester) async {
    final d = FakeDetector(failWith: 'Camera permission was denied.');
    await pumpAt(tester, const Size(1200, 800), d);
    await tester.tap(find.text('Start camera'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Camera permission was denied.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  group('responsive layout', () {
    Future<(Offset, Offset)> positions(WidgetTester tester, Size size) async {
      await pumpAt(tester, size, FakeDetector());
      expect(tester.takeException(), isNull);
      return (tester.getTopLeft(find.text('Start camera')), tester.getTopLeft(find.text('Start the camera to see live inferences. Everything is computed on this device.')));
    }

    testWidgets('desktop web: camera and insights side by side', (tester) async {
      final (cam, panel) = await positions(tester, const Size(1440, 900));
      expect(panel.dx, greaterThan(cam.dx));
    });

    testWidgets('tablet landscape: side by side', (tester) async {
      final (cam, panel) = await positions(tester, const Size(1024, 768));
      expect(panel.dx, greaterThan(cam.dx));
    });

    testWidgets('tablet portrait: stacked', (tester) async {
      final (cam, panel) = await positions(tester, const Size(800, 1280));
      expect(panel.dy, greaterThan(cam.dy));
    });

    testWidgets('phone portrait: stacked, no overflow', (tester) async {
      final (cam, panel) = await positions(tester, const Size(390, 844));
      expect(panel.dy, greaterThan(cam.dy));
    });

    testWidgets('small phone landscape: side by side, no overflow', (tester) async {
      final (cam, panel) = await positions(tester, const Size(740, 360));
      expect(panel.dx, greaterThan(cam.dx));
    });

    test('breakpoint rules', () {
      expect(HomePage.useRow(const BoxConstraints(maxWidth: 1000, maxHeight: 1600)), isTrue);
      expect(HomePage.useRow(const BoxConstraints(maxWidth: 800, maxHeight: 1280)), isFalse);
      expect(HomePage.useRow(const BoxConstraints(maxWidth: 844, maxHeight: 390)), isTrue);
      expect(HomePage.useRow(const BoxConstraints(maxWidth: 390, maxHeight: 844)), isFalse);
    });
  });
}
