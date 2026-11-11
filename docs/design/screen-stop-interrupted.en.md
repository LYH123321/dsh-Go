Not validated on a physical device.

# Stop-time interruption facts: 7210

[中文](screen-stop-interrupted.md). This patch depends on the frozen 7200 patch and implements ADDENDUM-03 without rewriting 7200. Dart parsing and watcher changes belong to the local integration and remain outside this patch.

## Result

The new native `task.interrupted` boolean records whether a stop in the current stop hold interrupted a phone task whose public active projection was true at that instant. PhoneTasks records it under its lock before ending the task and exports it through Snapshot.toMap. When Dart observes a stopped rising edge, it uses this fact instead of inferring interruption from adjacent active samples.

7200 prevents idle ambient stopAll calls from producing a stopped edge or a 30-second hold. 7210 records real interruption when the ticker missed a task's start or normal finish. Explicit user stops retain their existing ability to hold a cold/idle lifetime; their interrupted value is false and must not cancel unrelated conversations.

## Source and latch semantics

PhoneControl.emitStatus enqueues pushIfChanged on ticker. pushIfChanged calls captureStatus again, which reads tasks.snapshot().toMap; it does not retain every intermediate active sample. Adjacent native transitions can therefore collapse into one delivered status. No PhoneControl, PhonePlugin or Dart watcher edits are needed to carry the new field.

Let a be internal active, p paused, f inFlight, l the last activity time and Ti idleMs. The existing public projection is:

`A(t) = a && !(a && !p && f == 0 && t - l > Ti)`.

Paused and in-flight tasks remain active beyond the idle deadline. Before a stop, let U be the hold deadline and I the latch. Using one clock sample t under the same lock, stopLocked records:

`I' = (t < U && I) || A(t)`, then retains the existing stop transition with `U' = t + stopHoldMs`.

The current snapshot clears interruption after the hold expires. A newly admitted task, clearStop, valid resumeForSnapshot and successful finishScope also clear it. Repeated stops during a hold cannot replace true with false. A refused retry retains the fact while extending the same hold as before. An expired hold cannot donate true to a later cold stop even if no intermediate snapshot was taken.

stopActiveDeferred passes the same clock sample into stopLocked so an idle-boundary crossing between two reads cannot contradict the ambient stop decision. Snapshots remain immutable historical samples: an already captured old Change remains true when appropriate, but publishing it never writes the bit into a new task.

## Existing invariants

The field grants no admission, cleanup or recovery authority. admissionEpoch, lifecycle, stale-owner rejection, explicit stop hold renewal, 7200's non-renewing ambient repeats and physical cleanup gates retain their behavior. Public activity still follows the original idleLocked policy.

stoppedSessions remains a separate persistent session fence. After a modern task's 30-second hold expires, its session can still report stopped=true while interrupted=false. This does not authorize a new run or bypass resume/retire. Retiring rows retain historical frozen snapshots and are not authorization for current global cancellation. Existing callerCapability/launch, statusRevision, modernSeen and rising-edge gates must remain in place.

This is not a durable event log. If the complete stopped interval is missed, or explicitly cleared before ticker samples it, the existing state channel may deliver no rising edge. The new field removes the ambiguity of determining interruption from neighboring active samples when a stop edge is observed; it does not promise delivery of every stop event.

## Required Dart integration

The wire key is interrupted in the task map produced by PhoneTasks.Snapshot.toMap. New native always emits an Android Boolean, decoded as Dart bool; its initial value is false. The top-level task.interrupted carries the current legacy task fact.

Parsing must distinguish absence from explicit false. A nullable boolean may represent absent old-native metadata as null. Present boolean values are authoritative. Present malformed values should fail closed as false, without legacy inference or string coercion.

For a stopped rising edge that still satisfies the existing legacy-only cancellation and revision/launch gates, use the native boolean when present. Only when the field is absent fall back to the #999 rule provided in ADDENDUM-03: previous active OR current active. Explicit false must never be overwritten by previous active=true. Preserve initial/new-launch baselines, modern and mixed-session isolation, and stale-status rejection. This patch adds no atomic host expected-run cancellation and must not expand cancel-all authority.

```dart
final interrupted = taskMap.containsKey('interrupted')
    ? taskMap['interrupted'] is bool && taskMap['interrupted'] == true
    : previousTaskActive || currentTaskActive;
if (eligibleLegacyLaunch && stoppedRisingEdge && interrupted) {
  // Existing cancellation path.
}
```

External access to the #999 page was unavailable; its current diff was not reviewed. The old-native fallback above follows the user's authoritative ADDENDUM-03, while the snapshot's existing callerCapability isolation gates were inspected directly.

## Tests and device checks

PhoneTasksInterruptedTest adds ten deterministic cases: unsampled start, cold/idle explicit stop, immediate stop after normal finish, repeated holds, expiration without an intermediate sample, refused retry renewal, new task and explicit clear paths, paused/in-flight projection, one clock sample at the idle boundary, and late publication of an old captured Change. Four registry tests in PhoneTaskSessionsTest cover wire booleans, normal finish and idle ambient stops, new tasks and persistence of the modern session fence after interruption expires.

JVM/Android tests and device checks have not run in this sandbox; no Kotlin/Android setup was installed. Static and patch-application checks are recorded in the delivery notes. Device checks should delay ticker and exercise start-then-screen-off, finish-then-screen-off, duplicate screen receivers, hold expiration, explicit resume and a new task, while verifying that modern/mixed sessions never use global cancellation.
