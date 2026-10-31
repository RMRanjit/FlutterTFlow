import 'package:flutter/material.dart';

import '../session_controller.dart';
import 'camera_view.dart';
import 'insights_panel.dart';

/// Responsive shell: camera and insights sit side by side on wide/landscape
/// screens (desktop web, tablets, phones in landscape) and stack on portrait
/// phones and tablets.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.session});

  final SessionController session;

  static bool useRow(BoxConstraints c) => c.maxWidth >= 900 || (c.maxWidth > c.maxHeight && c.maxWidth >= 600);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Movement Insights'),
        actions: [
          ListenableBuilder(
            listenable: session,
            builder: (context, _) => session.running
                ? Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton.icon(onPressed: session.stop, icon: const Icon(Icons.stop_circle_outlined), label: const Text('Stop')),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final camera = CameraView(session: session);
            final panel = InsightsPanel(session: session);
            const gap = 16.0;
            if (useRow(c)) {
              return Padding(
                padding: const EdgeInsets.all(gap),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: camera),
                    const SizedBox(width: gap),
                    Expanded(flex: 2, child: panel),
                  ],
                ),
              );
            }
            // Stacked: the camera gets ~45% of the height (min 240) and the
            // insights scroll beneath it.
            final cameraHeight = (c.maxHeight * 0.45).clamp(240.0, 560.0);
            return Padding(
              padding: const EdgeInsets.all(gap),
              child: Column(
                children: [
                  SizedBox(height: cameraHeight, width: double.infinity, child: camera),
                  const SizedBox(height: gap),
                  Expanded(child: panel),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
