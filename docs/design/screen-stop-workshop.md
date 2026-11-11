# 熄屏停止：空闲围栏修复与解锁接线

[English](screen-stop-workshop.en.md)

未真机验证。基底：`1a2af92b7cfbd5958173f57949d26f2dd8e060e8`；工坊线 7200。

## 结论

`PhoneTaskSessions.stopAll` 必须使先前的 owner 和已排队 admission 失效，但空闲记录不应新建停止保持，也不应把会话写进 `stoppedSessions`。7200 在同一把 `PhoneTasks` 锁内判断实际活动状态：活动、暂停或仍有调用的任务继续走原 `stopLocked`；冷启动占位、已结束和已投影空闲的任务只推进纪元并结束过期 scope。既有停止保持不续期、不被清除。

此补丁闭合空闲熄屏误报停止问题。活动任务因熄屏产生的会话围栏仍按现有合同保留；自动解锁恢复必须和范围外的两条广播入口一起接线，不能用 `stopReason` 的中文文案识别。下面给出接线合同，不声称自动恢复已实现。

## 源码核实

| 结论 | 基底依据 |
| --- | --- |
| 冷 legacy 占位也产生 `stopped=true` | `PhoneTaskSessions` 构造时即建 `Task(null, null, ...)`；旧 `stopAll` 对每项无条件 `stopDeferred`；`PhoneTasks.stopLocked` 不要求 active，始终写 `now + stopHoldMs` |
| 30 秒只是 Tasks 的保持，不是会话围栏期限 | `claimCancellation` 在 stopped snapshot 上写 `task.stopped` 和 `stoppedSessions`；`admit`、`blocked` 分别检查会话和记录。`resume`、`retire` 才清会话集合，`admitEnd`/`settleEnd` 不清它 |
| 熄屏来自两条路径 | `PhoneControl.registerScreenOffNow` 使用“熄屏”；`PhoneA11yService.screenOff` 使用“屏幕关闭了”，后经 `onStopAllRequested` 调 registry |
| 无障碍服务接收器不检查手机总开关 | `PhoneA11yService.onServiceConnected` 注册 SCREEN_OFF；`screenOff.onReceive` 直接 `stopAll` |
| 当前 Dart 比题面历史背景更窄 | 附件中的 `phoneStopWatcherProvider` 已有 caller launch/version 与 modernSeen 分流；全对话取消只保留于满足条件的 legacy 分支。因此不能把附件行为概括为所有现代会话都会被 Dart 全局取消。7200 不碰该文件 |

## 不变量

1. **admission 围栏保留。** 每次 `stopAll` 仍对全部既有记录推进 `admissionEpoch`。旧排队调用即使等到保持期后才运行，`begin(expectedEpoch)` 也拒绝；新到达的调用不继承旧票据。
2. **owner 围栏保留。** 空闲分支推进 `lifecycle`；若内部 active 但快照已按 idle 投影为 false，调用 `endLocked` 同时清除原任务批准、waiver、可视化授权和插话。已发出的 prompt/owner 不会被新任务采用。
3. **批量提交顺序不变。** registry 持锁时提交全部记录，再在锁外取消驱动/问答、发布捕获快照和清理。首个外部回调再慢，也不会让后面的旧记录继续有效。已有取消仍由原取消方负责，不再并发取消一次。
4. **活动任务保持不变。** live active、paused、in-flight 都进入原 `stopLocked`，保留停止消息、30 秒保持、sticky session fence、技能取消和原有资源清理。显式 `stop(owner/snapshot)` 仍可停止冷/空闲记录；本补丁没有改变用户主动停止的语义。
5. **重复环境通知不延长旧保持。** 已停止任务是 inactive；第二个广播只使旧票据失效，保留第一次的 `stoppedUntil` 和原因。保持尚在时快照仍为 true，故原 session fence 不丢；不产生新的 false→true。
6. **物理资源不早退。** `pending`、`running`、`cancelling`、`closing`、cleanup failure、journal 与 skill scope 的 settlement 门槛均不变。未排空的系统调用或未确认释放的显示/App 租约继续占有原记录。

## 需要本机做的：活动任务在解锁后恢复可用

这里是后续实现合同，7200 不新增没有生产调用方的恢复 API。

- 为停止来源加类型，例如 `PhoneStopCause.SCREEN_OFF`、`USER`、`DISABLED`、`SERVICE_LOST`；reason 仅用于展示。默认应为持久停止，两处熄屏路径必须明确传 SCREEN_OFF。`PhoneRegistry.ControlListener` 与 `PhoneControl` 的传递也须携带类型。
- registry 另存“仅因熄屏而围栏的会话”和对应 stop generation。仅当会话此前没有用户/关开关/服务离开围栏，或先前围栏同样来自熄屏，才允许登记。随后任意持久停止立即取消其解锁资格；重复熄屏不能把持久停止升级成可恢复。
- 解锁后只开放**这个会话的新 run**。旧 run 的 `task.stopped`、`endRequested`、`endedRuns` 必须保留；旧 admission 的 epoch 不能重签。不能直接对全部记录调用现有 `resume`，它会清记录级停止，可能复活同一旧 run 的重试。
- legacy 无 run 身份，只能在原调用和资源已排空后清它的 hold；原 admission/owner 仍不可复用。不能自动重试原动作，也不继续旧批准或 waiver。
- 只有 `isEnabled() && !isLocked()` 才尝试恢复。现有 `PhoneControl.isLocked()` 已合并 `KeyguardManager.isKeyguardLocked` 与 `!PowerManager.isInteractive`，复用它，不以 SCREEN_ON 当作解锁证明。监听 USER_PRESENT，并在无锁屏设备的 SCREEN_ON/既有 ticker 路径重查当前状态。监听只是重查触发，不是授权凭证。
- 解锁可能先于清理结束。恢复检查必须复用 registry 的 pending/running/cancelling/closing/cleanup/journal/skill 门槛；先保留解锁意图，清理完成后的状态刷新再重查。任何存储或物理清理失败继续拒绝。重启/retire 清掉旧恢复票据；不跨 launch 恢复。

Android 官方说明：`ACTION_USER_PRESENT` 表示唤醒后用户已出现；SCREEN_ON 表示进入可交互状态，不保证锁屏消失；`isKeyguardLocked` 判断锁屏是否显示。资料核对时间：2026-11-11。

- [Intent 的 USER_PRESENT / SCREEN_ON](https://developer.android.com/reference/android/content/Intent#ACTION_USER_PRESENT)
- [PowerManager.isInteractive](https://developer.android.com/reference/android/os/PowerManager#isInteractive())
- [KeyguardManager.isKeyguardLocked](https://developer.android.com/reference/android/app/KeyguardManager#isKeyguardLocked())

## 无障碍广播应不应该跟总开关走

不建议在 `PhoneA11yService.screenOff` 顶部按总开关直接 return。该服务还承载桌宠/截屏等入口，`stopAll` 本身先中止 driver、结束 overlay 问答；开关写成 off 也不证明先前系统操作、队列或 prompt 已排空。丢掉这条清理路径会引入新的生命周期间隙。7200 让空闲通知不生成停止沿，已经消除本次错误，不需要同时移除接收器。

若本机要减少无关通知，应只在 `PhoneControl` 的会话通知边界作优化，并证明没有既有调用、清理和 pre-task prompt；物理 abort、遮罩问答清理仍保留。此优化不在 7200 内。

## 模拟清单与验证边界

新增 `PhoneTaskSessionsTest` 7 项，覆盖冷 legacy、未开始的 modern admission、已结束 run、legacy idle 投影、paused、双广播保持不续期、活动 modern 围栏持续到显式 resume。原有全批量提交、取消重入/异常、旧 admission、物理 drain 测试原样保留。

- 已执行：所改文件 `git diff --check`，通过。
- 未执行：JVM 测试与 Android 编译。沙箱无 Kotlin/Flutter 工具链，按题面不搭建；请求本机运行 `gradlew.bat :app:testArm64DebugUnitTest --tests "*PhoneTaskSessionsTest" --tests "*PhoneTaskChangeTest" --tests "*PhoneTasksFinishTest" --tests "*PhoneTasksPauseTest"`，再按常规完整 CI。
- 真机：在仅普通聊天运行、没有手机任务时熄屏，分别覆盖手机总开关开/关且无障碍服务仍连接；普通对话应继续，原生 task 不出现新 stopped。连续熄屏/解锁重复 3 次。
- 真机：真正在主屏/后台屏操控时熄屏，原任务仍停止，旧动作不重试，资源在实际清理后释放；手动停止再熄屏，不得因此恢复。
- 后续恢复接线验收：熄屏后先亮屏不解锁应保持拒绝；解锁后同 session 新 run 可用而旧 run 仍拒绝；用户 stop、关总开关、服务离开不因解锁恢复；两接收器重复通知与慢清理都不清错围栏。

JVM 或真机结果返回前，本文结论中的“实现行为”依据源码与测试断言，不冒充实际运行结果。
