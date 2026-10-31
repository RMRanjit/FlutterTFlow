import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_poc/analysis/inference.dart';
import 'package:movement_poc/demo/challenges.dart';

void main() {
  test('completes challenges from states and from one-off events', () {
    final t = ChallengeTracker();
    expect(t.completed, 0);

    final raised = AnalysisResult(inferences: [const Inference(InferenceKind.gesture, 'left_up', 'Left hand raised')]);
    expect(t.update(raised), isTrue);
    expect(t.isDone(0), isTrue);
    expect(t.update(raised), isFalse, reason: 'already completed, nothing new');

    final wave = AnalysisResult(newEvents: [MovementEvent(DateTime(2026), 'Wave detected', id: 'wave')]);
    expect(t.update(wave), isTrue);
    expect(t.isDone(1), isTrue);
    expect(t.completed, 2);
  });

  test('ignores events without an id and unrelated inferences', () {
    final t = ChallengeTracker();
    final r = AnalysisResult(
      inferences: [const Inference(InferenceKind.motion, 'still', 'Still')],
      newEvents: [MovementEvent(DateTime(2026), 'Something')],
    );
    expect(t.update(r), isFalse);
    expect(t.completed, 0);
  });

  test('finishes and resets', () {
    final t = ChallengeTracker();
    final all = AnalysisResult(inferences: [
      for (final c in defaultChallenges) Inference(InferenceKind.gesture, c.triggers.first, c.title),
    ]);
    t.update(all);
    expect(t.allDone, isTrue);
    t.reset();
    expect(t.completed, 0);
  });

  test('every trigger id used by a challenge is actually emitted by the analyzer', () {
    // Guards against typos drifting between the challenge list and the analyzer.
    final analyzer = File('lib/analysis/movement_analyzer.dart').readAsStringSync();
    for (final c in defaultChallenges) {
      for (final id in c.triggers) {
        expect(analyzer.contains("'$id'"), isTrue, reason: 'analyzer never emits "$id" (challenge "${c.title}")');
      }
    }
  });
}
