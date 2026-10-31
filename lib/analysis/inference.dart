enum InferenceKind { posture, gesture, motion, face, wellbeing }

enum Severity { info, good, warning }

/// A human-readable conclusion drawn from the movement data.
class Inference {
  const Inference(this.kind, this.id, this.label, {this.detail, this.severity = Severity.info});

  final InferenceKind kind;

  /// Stable id used for de-duplicating the event log.
  final String id;
  final String label;
  final String? detail;
  final Severity severity;

  @override
  bool operator ==(Object other) => other is Inference && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A momentary occurrence (wave, jump, nod...) shown in the activity log.
class MovementEvent {
  const MovementEvent(this.at, this.label, {this.severity = Severity.info, this.id});

  /// Stable machine id (e.g. `wave`), when the event has one.
  final String? id;
  final DateTime at;
  final String label;
  final Severity severity;
}

/// Snapshot returned by the analyzer for every frame.
class AnalysisResult {
  const AnalysisResult({
    this.inferences = const [],
    this.newEvents = const [],
    this.activityLevel = 0,
    this.personVisible = false,
  });

  /// States that currently hold, e.g. "Sitting", "Right hand raised".
  final List<Inference> inferences;

  /// Events that fired on this frame only.
  final List<MovementEvent> newEvents;

  /// 0..1 smoothed measure of how much the person is moving.
  final double activityLevel;
  final bool personVisible;
}
