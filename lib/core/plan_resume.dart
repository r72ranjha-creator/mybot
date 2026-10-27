import '../data/models.dart';

/// Where an approval points inside a plan.
///
/// `plan.steps` is a list; `PlanStep.index` is the 1-based number the user sees
/// in "Step 2: …". Resuming used to pass the 1-based number straight into the
/// list, so approving step 1 re-entered at position 1 — step 2 — and the step
/// the user had just approved never ran. This is the one place that translates
/// between the two, and it accepts the older payload shape too.
class PlanResume {
  PlanResume._();

  static int? positionFor(TaskPlan plan, Map<String, Object?> payload) {
    final number = (payload['stepNumber'] as num?)?.toInt();
    final raw = (payload['stepIndex'] as num?)?.toInt();
    final stepNumber = number ?? raw;
    if (stepNumber == null) return null;
    for (var i = 0; i < plan.steps.length; i++) {
      if (plan.steps[i].index == stepNumber) return i;
    }
    // Old payloads stored a 0-based list position for plans whose step numbers
    // started at 1; fall back to it only when it lands on a real step.
    if (raw != null && raw >= 0 && raw < plan.steps.length) return raw;
    return null;
  }
}
