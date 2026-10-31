import 'package:flutter/material.dart';

import '../session_controller.dart';
import 'skeleton_painter.dart';

/// Camera preview with skeleton overlay, or a start prompt / error state.
class CameraView extends StatelessWidget {
  const CameraView({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: Colors.black,
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            switch (session.status) {
              case SessionStatus.running:
                return _Live(session: session);
              case SessionStatus.starting:
                return const _Message(icon: null, title: 'Starting camera…', body: 'Loading TensorFlow Lite models. The first run can take a few seconds.');
              case SessionStatus.error:
                return _Message(icon: Icons.videocam_off_outlined, title: 'Could not start', body: session.error ?? 'Unknown error', color: scheme.error, action: FilledButton.icon(onPressed: session.start, icon: const Icon(Icons.refresh), label: const Text('Try again')));
              case SessionStatus.idle:
                return _Message(
                  icon: Icons.accessibility_new,
                  title: 'Movement Insights',
                  body: 'Uses your camera to understand how you move — posture, gestures and expressions — and explains what it sees in plain language. Everything happens on this device; no video is recorded or uploaded.',
                  action: FilledButton.icon(onPressed: session.start, icon: const Icon(Icons.videocam), label: const Text('Start camera')),
                );
            }
          },
        ),
      ),
    );
  }
}

class _Live extends StatelessWidget {
  const _Live({required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final detector = session.detector;
    return ValueListenableBuilder<double>(
      valueListenable: detector.aspect,
      builder: (context, aspect, _) => Center(
        child: AspectRatio(
          aspectRatio: aspect,
          child: Stack(
            fit: StackFit.expand,
            children: [
              detector.buildPreview(context),
              IgnorePointer(
                child: CustomPaint(painter: SkeletonPainter(frame: session.frame, mirrored: detector.mirrored)),
              ),
              if (session.showDetails)
                Positioned(left: 12, bottom: 12, child: _Badge(text: detector.backendName)),
              if (!session.result.personVisible)
                const Align(
                  alignment: Alignment.topCenter,
                  child: Padding(padding: EdgeInsets.all(12), child: _Badge(text: 'No person in view – step back so your head and shoulders are visible')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12), textAlign: TextAlign.center)),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body, this.icon, this.action, this.color});

  final IconData? icon;
  final String title;
  final String body;
  final Widget? action;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon, size: 56, color: color ?? Colors.white70) else const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(body, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}
