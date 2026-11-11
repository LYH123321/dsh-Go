未真机验证

# 原生停止时的打断事实：7210

[English](screen-stop-interrupted.en.md)。本补丁依赖已冻结的 7200，不替换或重写它；落实 ADDENDUM-03。Dart 读取与 watcher 由本机修改，本补丁不触碰避让文件。

## 结论

新原生状态的 `task.interrupted` 是布尔值，表示**当前停止保持期内，至少有一次停止在发生当刻打断了公开投影为 active 的手机任务**。它由 PhoneTasks 在锁内、结束任务之前记录，经 Snapshot.toMap 进入既有状态通道。Dart 收到 stopped 上升沿时，直接采用该事实，不再用前一份或这一份 active 猜测新原生是否打断过任务。

7200 和本补丁分别解决两个问题。7200 让环境 stopAll 在空闲时不产生 stopped 上升沿和30秒保持；7210 为真实停止记录当刻事实，覆盖 ticker 未送达“刚开始”或“刚结束”中间状态的窗口。显式用户 stop 仍可对冷/空闲生命周期建立原有保持，此时 interrupted=false；不能据此取消无关对话。

## 源码证据与取值

基底 PhoneControl.emitStatus 只向 ticker 排入 pushIfChanged；后者重新调用 captureStatus。captureStatus 取 `tasks.snapshot().toMap()`，不会使用停止回调当时的某个中间 active 快照。因此两个相邻原生变化可能合并成一次对外状态，ADDENDUM-03 指出的两个窗口确实存在。本补丁沿用该通道，不改 PhoneControl、PhonePlugin 或 Dart watcher。

令 a 是内部 active，p 是 paused，f 是 inFlight，l 是最近活动时间，Ti 是 idleMs。公开活动投影为：

`A(t) = a && !(a && !p && f == 0 && t - l > Ti)`。

这与 snapshot.active 的原有口径相同。暂停或仍有调用执行的任务即使超过空闲时长仍算在跑；只有空闲投影不算。不是简单使用内部 isActive。

停止前的保持截止时间为 U，原打断位为 I。stopLocked 在同一个锁内按一个时钟样本 t 执行：

`I' = (t < U && I) || A(t)`；随后沿用原有停止流程，`U' = t + stopHoldMs`。

对外当前快照的 interrupted 仅在停止保持仍成立时保留。保持到期的 snapshot、成功进入下一任务，以及 clearStop、有效 resumeForSnapshot、成功 finishScope 均清零。保持期内重复停止不能把已经为 true 的事实覆盖成 false；被拒绝的重试仍按原逻辑延长同一保持，也保留该事实。到期后即使没有任何中间 snapshot，下一次冷 stop 也不能继承旧 true。

环境 stopActiveDeferred 的活动判定和 stopLocked 使用同一个 t，避免跨越 idle 边界的二次时钟采样造成“决定停止时在跑，记录时却不在跑”。Snapshot 仍是不可变的历史取样：已捕获的旧 Change.snapshot 不会随着新任务改值；旧捕获值也不会重新写回当前任务。

## 与既有不变量的关系

interrupted 只增加事实记录，不参与准入、清理或恢复授权。admissionEpoch 的递增条件、lifecycle、旧 owner 失效、显式 stop 保持续期、7200 环境重复 stop 不续期，以及物理清理门都不变。paused 和 inFlight 的活动投影继续由原 idleLocked 定义。

`stoppedSessions` 是独立的会话围栏。现代会话30秒保持到期后可能仍是 stopped=true，同时 interrupted=false；这不表示会话已获恢复，也不允许绕过 resume/retire。tasks 列表中退休记录沿用原来的冻结历史快照，不能把历史记录的字段当成当前全局取消授权。本机应继续使用原有 callerCapability/launch、statusRevision、modernSeen 与 stopped 上升沿边界；该新字段不扩大可以取消的会话集合。

该方案没有新增持久事件队列或确认机制。如果 stopped=true 的整个保持期被跳过，或者在 ticker 取样前已经被显式恢复/结束，现有状态通道仍可能没有停止沿；本补丁只消除“在已观察到停止沿时，用相邻 active 快照判断打断事实”的采样歧义，不声称可靠投递每一个停止事件。

## 需要本机做的：精确 Dart 合同

1. 原生 wire 字段名为 `interrupted`，位于 PhoneTasks.Snapshot.toMap 产生的任务 map 中；状态顶层的 `task.interrupted` 是 Android Boolean / Dart bool。新原生总会输出它，默认 false。
2. 解析必须区分“缺字段”和“明确 false”。可用 nullable bool：字段不存在解析成 null；字段存在且值为布尔才使用；存在但类型错误按 false 处理，不回退旧推断，不把字符串 `"true"` 当真。
3. 对仍符合既有 legacy-only 全局取消资格、且通过状态版本/launch 门的 stopped 上升沿，决定是否打断的规则为：字段存在时取原生布尔值；仅旧原生完全没有字段时回退 ADDENDUM-03 所述 #999 规则，即上一份 active 或这一份 active 为真。明确 false 绝不能被上一份 active=true 覆盖。
4. stopped 边沿、首次订阅基线、新 launch 基线、现代/混合会话隔离、乱序状态拒绝继续保留。现代会话没有原子 host expected-run 取消协议，本补丁不赋予全局 cancel-all 权限。

示意逻辑只表达新增判据，不是对禁区的补丁：

```dart
final interrupted = taskMap.containsKey('interrupted')
    ? taskMap['interrupted'] is bool && taskMap['interrupted'] == true
    : previousTaskActive || currentTaskActive;
if (eligibleLegacyLaunch && stoppedRisingEdge && interrupted) {
  // 沿用已有取消路径。
}
```

读取 PR #999 页面时外部访问返回不可用；没有把该 PR 的当前 diff 声称为已审。以上旧版回退以用户提供的 ADDENDUM-03 精确规则为依据，基底源码的 callerCapability 隔离门已只读核实。

## 测试与本机模拟

新增 PhoneTasksInterruptedTest 的10个确定性场景：未送达 active 即停止；冷/空闲显式 stop；正常 finish 后紧接 stop；保持内重复；无中间快照的到期后冷 stop；拒绝重试续期；新任务及显式清保持；暂停/在途任务；idle 边界单次采样；旧 Change 发布不能改新任务的位。PhoneTaskSessionsTest 另增4个完整注册表场景，核 wire 布尔、正常 finish/空闲 stopAll、新任务，以及现代会话围栏在 interrupted 到期后仍保持。

本沙箱未运行 JVM/Android 测试或真机：无 Kotlin/Android 工具链，按题面由本机批量代跑。实际静态检查与补丁可应用检查写在交付说明。真机应在人为延迟 ticker 的情况下分别复现：刚开始就熄屏、正常完成后立即熄屏、两个熄屏接收器重复停止、保持到期、显式恢复后开始新任务；检查布尔与取消范围，并回归现代/混合会话不会全局取消。
