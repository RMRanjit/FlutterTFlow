import 'package:flutter/material.dart';

import 'detection/motion_detector.dart';
import 'session_controller.dart';
import 'ui/home_page.dart';

class MovementApp extends StatelessWidget {
  const MovementApp({super.key, this.detectorFactory});

  /// Overridable so tests can inject a fake detector.
  final MotionDetector Function()? detectorFactory;

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00897B), brightness: b),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Movement Insights',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: _Root(detectorFactory: detectorFactory ?? MotionDetector.create),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root({required this.detectorFactory});

  final MotionDetector Function() detectorFactory;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  late final SessionController _session = SessionController(detector: widget.detectorFactory());

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HomePage(session: _session);
}
