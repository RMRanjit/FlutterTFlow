import 'package:flutter/material.dart';

import '../analysis/inference.dart';
import '../session_controller.dart';

/// Live explanation of what the models see: current states, alerts, stats and
/// a log of recent movements.
class InsightsPanel extends StatelessWidget {
  const InsightsPanel({super.key, required this.session});

  final SessionController session;

  static const _groups = <(InferenceKind, String, IconData)>[
    (InferenceKind.posture, 'Posture', Icons.airline_seat_recline_normal),
    (InferenceKind.gesture, 'Gestures', Icons.back_hand_outlined),
    (InferenceKind.face, 'Face', Icons.face_retouching_natural),
    (InferenceKind.motion, 'Motion', Icons.directions_run),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final r = session.result;
        final alerts = r.inferences.where((i) => i.kind == InferenceKind.wellbeing).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 24),
          children: [
            if (!session.running)
              const _Card(child: Text('Start the camera to see live inferences. Everything is computed on this device.'))
            else ...[
              for (final a in alerts) _AlertCard(inference: a),
              _Card(
                title: 'Right now',
                trailing: TextButton.icon(
                  onPressed: () {
                    final ok = session.calibratePosture();
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(ok ? 'Posture calibrated – this is now your "upright".' : 'Nobody in view to calibrate.')));
                  },
                  icon: const Icon(Icons.tune, size: 18),
                  label: Text(session.analyzer.isCalibrated ? 'Recalibrate' : 'Calibrate posture'),
                ),
                child: r.personVisible ? _states(context, r) : const Text('Waiting for a person to appear…'),
              ),
              _Card(title: 'Activity level', child: _ActivityMeter(level: r.activityLevel)),
              _Card(title: 'Model stats', child: _stats(context)),
              _Card(
                title: 'Recent activity',
                trailing: session.log.isEmpty ? null : TextButton(onPressed: session.clearLog, child: const Text('Clear')),
                child: _Log(entries: session.log),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _states(BuildContext context, AnalysisResult r) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (final (kind, _, icon) in _groups) {
      final items = r.inferences.where((i) => i.kind == kind).toList();
      if (items.isEmpty) continue;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [for (final i in items) _InferenceChip(inference: i)]),
            ),
          ],
        ),
      ));
    }
    if (rows.isEmpty) return const Text('Analysing…');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _stats(BuildContext context) {
    final detector = session.detector;
    final a = session.analyzer;
    final hasFace = session.face?.hasBlendshapes ?? false;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _Stat('Backend', detector.backendName),
        _Stat('Frame rate', '${session.fps.toStringAsFixed(0)} fps'),
        _Stat('Inference', '${session.inferenceMs.toStringAsFixed(0)} ms'),
        if (hasFace) _Stat('Blinks / min', '${a.blinksPerMinute}'),
        if (!hasFace)
          _Stat('Face expressions', detector.supportsFaceExpressions ? 'no face detected' : 'not available on mobile (body model only)'),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.title, this.trailing});

  final Widget child;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(child: Text(title!, style: theme.textTheme.titleSmall)),
                  ?trailing,
                ]),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

class _InferenceChip extends StatelessWidget {
  const _InferenceChip({required this.inference});

  final Inference inference;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (inference.severity) {
      Severity.good => (scheme.primaryContainer, scheme.onPrimaryContainer),
      Severity.warning => (scheme.errorContainer, scheme.onErrorContainer),
      Severity.info => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    };
    return Tooltip(
      message: inference.detail ?? inference.label,
      child: Chip(
        label: Text(inference.detail == null ? inference.label : '${inference.label} · ${inference.detail}'),
        backgroundColor: bg,
        labelStyle: TextStyle(color: fg),
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.inference});

  final Inference inference;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: scheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
        title: Text(inference.label, style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600)),
        subtitle: inference.detail == null ? null : Text(inference.detail!, style: TextStyle(color: scheme.onErrorContainer)),
      ),
    );
  }
}

class _ActivityMeter extends StatelessWidget {
  const _ActivityMeter({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: level.clamp(0, 1), minHeight: 10)),
        const SizedBox(height: 6),
        Text('${(level * 100).round()}%', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _Log extends StatelessWidget {
  const _Log({required this.entries});

  final List<MovementEvent> entries;

  static String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const Text('Gestures, nods, waves, jumps and alerts will appear here.');
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final e in entries.take(12))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Text(_time(e.at), style: theme.textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()], color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(e.label, style: TextStyle(color: e.severity == Severity.warning ? theme.colorScheme.error : null)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
