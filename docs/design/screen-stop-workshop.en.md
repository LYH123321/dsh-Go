# Screen-off stops: idle fencing and unlock integration

[中文](screen-stop-workshop.md)

Not verified on a physical device. Base: `1a2af92b7cfbd5958173f57949d26f2dd8e060e8`; workshop patch 7200.

## Result

`PhoneTaskSessions.stopAll` must invalidate previous owners and queued admissions without inventing a stop hold or a `stoppedSessions` fence for an idle record. Patch 7200 makes the decision under the same `PhoneTasks` lock: live, paused, or in-flight tasks retain `stopLocked`; cold placeholders, ended tasks, and projected-idle tasks only advance their epochs and end an expired scope. An existing stop hold is neither extended nor cleared.

This closes the idle screen-off false-stop problem. A real active task stopped by screen-off still retains the existing session fence. Automatic unlock recovery must be integrated with both broadcast entry points outside this patch's write scope; localized reason strings cannot identify the cause. The contract below is a proposal, not an implemented recovery claim.

## Source evidence

| Finding | Evidence in the supplied base |
| --- | --- |
| A cold legacy placeholder could emit `stopped=true` | The registry constructs `Task(null, null, ...)`; the old `stopAll` unconditionally invoked `stopDeferred`; `stopLocked` always set `now + stopHoldMs`, even when inactive |
| The 30-second hold does not expire the session fence | `claimCancellation` sets `task.stopped` and `stoppedSessions`; `admit` and `blocked` consult these. Only `resume` and `retire` clear the session set; host run-end settlement does not |
| Two screen-off paths exist | `PhoneControl.registerScreenOffNow` and `PhoneA11yService.screenOff`, the latter forwarded through `onStopAllRequested`, use different display reasons |
| The accessibility receiver does not check the phone-control switch | `onServiceConnected` registers SCREEN_OFF and the receiver directly calls `stopAll` |
| The current Dart scope is narrower than the historical description | The snapshot's `phoneStopWatcherProvider` already tracks caller launch/version and modernSeen. Global turn cancellation is restricted to its qualifying legacy path. Patch 7200 does not modify it |

## Preserved invariants

1. **Admission fencing:** every pre-existing record still advances `admissionEpoch`. An old queued call fails `begin(expectedEpoch)` even after a stop hold expires. Fresh admissions do not inherit old tickets.
2. **Owner fencing:** the idle path advances `lifecycle`. An internally active but projected-idle scope goes through `endLocked`, dropping approvals, waivers, visual authorization, and interjections. A delayed prompt cannot adopt a successor.
3. **Batch order:** all records commit under the registry lock before external cancellation, listener publication, or cleanup. A slow first callback does not leave later owners live. An existing cancellation retains responsibility for its external work.
4. **Active stops:** live, paused, and in-flight tasks retain the original stop message, hold, sticky session fence, skill cancellation, and cleanup. Explicit owner/snapshot stops can still stop cold or idle records; deliberate user-stop semantics are unchanged.
5. **Repeated ambient notifications:** an inactive stopped record keeps its original deadline and reason. A second broadcast advances tickets but does not renew the hold or create a new false-to-true edge. An unexpired hold still reports stopped and retains its session fence.
6. **Physical leases:** pending/running/cancelling/closing, cleanup failure, journal, and skill settlement gates remain intact. Original bodies and unconfirmed display/App cleanup keep their leases.

## Local integration required: recovery after unlock

This is the follow-up contract; 7200 does not add an unused production recovery API.

- Carry a typed cause such as `PhoneStopCause.SCREEN_OFF`, `USER`, `DISABLED`, or `SERVICE_LOST`; reason remains display-only. The default is a persistent stop. Both screen-off paths and the registry listener must carry SCREEN_OFF explicitly.
- Track sessions fenced exclusively by screen-off together with their stop generation. Existing persistent fences cannot become recoverable. A later user/disabled/service-loss stop revokes unlock eligibility; duplicate screen-off notifications do not weaken it.
- Unlock permits a **new run in that session**. Preserve old-run `task.stopped`, `endRequested`, `endedRuns`, and admission epochs. Do not call existing `resume` indiscriminately: it clears per-record stops and can permit a retry of the old run.
- Legacy has no run identity. Clear its hold only after the original call and resources drain; old admissions and owners remain invalid. Do not replay actions, approvals, or waivers.
- Attempt recovery only under `isEnabled() && !isLocked()`. Existing `PhoneControl.isLocked()` combines keyguard visibility and interactivity. Reuse it. USER_PRESENT triggers a recheck; SCREEN_ON and the existing ticker cover devices without a lock screen. A broadcast is not proof of current eligibility.
- Unlock can precede cleanup. Keep the intent and recheck after settlement using pending/running/cancelling/closing/cleanup/journal/skill gates. Storage or physical cleanup failures keep the fence. Retire/restart discards old recovery receipts; never transfer them across launches.

Official Android references checked on 2026-11-11: USER_PRESENT reports presence after wake; SCREEN_ON reports interactivity, not lock-screen dismissal; `isKeyguardLocked` reports whether keyguard is showing.

- [Intent USER_PRESENT / SCREEN_ON](https://developer.android.com/reference/android/content/Intent#ACTION_USER_PRESENT)
- [PowerManager.isInteractive](https://developer.android.com/reference/android/os/PowerManager#isInteractive())
- [KeyguardManager.isKeyguardLocked](https://developer.android.com/reference/android/app/KeyguardManager#isKeyguardLocked())

## Should the accessibility receiver follow the switch?

Do not return early from the entire service receiver merely because the switch is off. The service also hosts pet/capture paths, and `stopAll` first aborts the driver and ends overlay prompts. An off preference does not prove earlier bodies, queued work, or prompts have drained. Patch 7200 removes the false stop edge without removing this cleanup path.

Any later notification optimization belongs at the PhoneControl session boundary and must prove that no call, cleanup, or pre-task prompt remains. Preserve physical abort and prompt cleanup. This optimization is not part of 7200.

## Verification and simulation checklist

Seven new registry tests cover cold legacy, unstarted modern admission, an ended run, projected legacy idle, paused activity, duplicate hold behavior, and an active modern fence lasting until explicit resume. Existing batch, cancellation reentry/failure, old-admission, and physical-drain tests remain unchanged.

- Executed: `git diff --check` for changed files; passed.
- Not run: JVM tests or Android compilation. The sandbox has no Kotlin/Flutter toolchain and the task forbids setting one up. Local command: `gradlew.bat :app:testArm64DebugUnitTest --tests "*PhoneTaskSessionsTest" --tests "*PhoneTaskChangeTest" --tests "*PhoneTasksFinishTest" --tests "*PhoneTasksPauseTest"`, then the usual complete CI.
- Device: ordinary chat without phone work must survive screen-off, with the switch on and off while accessibility remains connected; native state must not acquire stopped. Repeat screen-off/unlock three times.
- Device: active main/background phone operations still stop, do not retry old actions, and release leases after actual cleanup. Explicit user stop followed by screen-off must not recover automatically.
- Follow-up recovery: wake while still locked remains refused; after unlock a new run in the session works and the old run stays fenced. User stop, disabling, and service loss are not auto-resumed. Duplicate receivers and slow cleanup must not clear the wrong fence.

Until local or device results arrive, implementation claims describe source logic and test assertions, not observed runtime success.
