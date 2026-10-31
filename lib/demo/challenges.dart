import 'package:flutter/material.dart';

import '../analysis/inference.dart';

/// One thing for the audience to try in front of the camera.
class Challenge {
  const Challenge(this.title, this.hint, this.icon, this.triggers);

  final String title;
  final String hint;
  final IconData icon;

  /// Inference ids or event ids that complete this challenge.
  final Set<String> triggers;
}

const defaultChallenges = <Challenge>[
  Challenge('Raise a hand', 'Lift one hand above your shoulder', Icons.front_hand, {'left_up', 'right_up', 'both_up'}),
  Challenge('Wave hello', 'Raise a hand and wave side to side', Icons.waving_hand, {'wave'}),
  Challenge('Smile', 'Give the camera a big smile', Icons.sentiment_satisfied_alt, {'smile'}),
  Challenge('Nod "yes"', 'Nod your head up and down', Icons.check_circle_outline, {'nod'}),
  Challenge('Shake "no"', 'Shake your head left and right', Icons.cancel_outlined, {'shake'}),
  Challenge('Cross your arms', 'Fold your arms in front of you', Icons.close_fullscreen, {'arms_crossed'}),
  Challenge('Lean to the side', 'Tilt your body left or right', Icons.swap_horiz, {'lean_l', 'lean_r'}),
  Challenge('Jump', 'Needs room: step back so your whole body is in view', Icons.north, {'jump'}),
];

/// Remembers which challenges have been completed during a session.
class ChallengeTracker {
  ChallengeTracker([this.challenges = defaultChallenges]);

  final List<Challenge> challenges;
  final Set<int> _done = {};

  int get completed => _done.length;
  int get total => challenges.length;
  bool get allDone => completed == total;
  bool isDone(int index) => _done.contains(index);

  /// Returns true if at least one challenge was newly completed.
  bool update(AnalysisResult r) {
    final ids = {
      for (final i in r.inferences) i.id,
      for (final e in r.newEvents)
        if (e.id != null) e.id!,
    };
    if (ids.isEmpty) return false;
    var changed = false;
    for (var i = 0; i < challenges.length; i++) {
      if (!_done.contains(i) && challenges[i].triggers.any(ids.contains)) {
        _done.add(i);
        changed = true;
      }
    }
    return changed;
  }

  void reset() => _done.clear();
}
