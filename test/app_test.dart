import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movement_poc/app.dart';
import 'package:movement_poc/detection/motion_detector.dart';
import 'package:movement_poc/models/landmark.dart';
import 'package:movement_poc/ui/camera_view.dart';
import 'package:movement_poc/ui/home_page.dart';
import 'package:movement_poc/ui/insights_panel.dart';

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

    // The raised hand ticks off the first challenge for the audience.
    expect(find.textContaining('Try these in front of the camera  (1/8)'), findsOneWidget);

    // Technical details are hidden until the presenter asks for them.
    expect(find.text('Fake · test'), findsNothing);
    expect(find.text('Model stats'), findsNothing);
    await tester.tap(find.byTooltip('Show technical details'));
    await tester.pump();
    expect(find.text('Fake · test'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Model stats'), 300, scrollable: find.descendant(of: find.byType(InsightsPanel), matching: find.byType(Scrollable)));
    expect(find.text('Model stats'), findsOneWidget);

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
    /// (camera bounds, insights bounds) with no layout exceptions.
    Future<(Rect, Rect)> bounds(WidgetTester tester, Size size) async {
      await pumpAt(tester, size, FakeDetector());
      expect(tester.takeException(), isNull);
      return (tester.getRect(find.byType(CameraView)), tester.getRect(find.byType(InsightsPanel)));
    }

    testWidgets('desktop web: camera and insights side by side', (tester) async {
      final (cam, panel) = await bounds(tester, const Size(1440, 900));
      expect(panel.left, greaterThanOrEqualTo(cam.right));
    });

    testWidgets('tablet landscape: side by side', (tester) async {
      final (cam, panel) = await bounds(tester, const Size(1024, 768));
      expect(panel.left, greaterThanOrEqualTo(cam.right));
    });

    testWidgets('tablet portrait: stacked', (tester) async {
      final (cam, panel) = await bounds(tester, const Size(800, 1280));
      expect(panel.top, greaterThanOrEqualTo(cam.bottom));
    });

    testWidgets('phone portrait: stacked, no overflow', (tester) async {
      final (cam, panel) = await bounds(tester, const Size(390, 844));
      expect(panel.top, greaterThanOrEqualTo(cam.bottom));
    });

    testWidgets('small phone landscape: side by side, no overflow', (tester) async {
      final (cam, panel) = await bounds(tester, const Size(740, 360));
      expect(panel.left, greaterThanOrEqualTo(cam.right));
    });

    test('breakpoint rules', () {
      expect(HomePage.useRow(const BoxConstraints(maxWidth: 1000, maxHeight: 1600)), isTrue);
      expect(HomePage.useRow(const BoxConstraints(maxWidth: 800, maxHeight: 1280)), isFalse);
      expect(HomePage.useRow(const BoxConstraints(maxWidth: 844, maxHeight: 390)), isTrue);
      expect(HomePage.useRow(const BoxConstraints(maxWidth: 390, maxHeight: 844)), isFalse);
    });
  });
}
