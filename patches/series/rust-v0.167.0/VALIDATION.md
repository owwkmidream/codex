# rust-v0.167.0 验证证据

官方基线：`086ccc833bc9cf01024ad2dd6af7dbd421b6bf9a`。功能语义以 [CODEX-BUILD.md](../../../CODEX-BUILD.md) 为准；本文件只记录验证归属和缺口。接手时先查目标提交的实际 jobs，历史成功不代表后续提交已验证。

## 已发布基线：0016

- 维护提交：`2a0ea797366c00236670758ecd0972f6bad94abe`；源码提交：`c6b5824`。
- [CI 42637459939](https://github.com/owwkmidream/codex/actions/runs/42637459939)：prepare、build、test、release 全部成功，2026-11-09 发布。
- Release 附件：`codex-rust-v0.167.0-windows-x64.zip`，120,726,798 字节，2026-11-09 15:40:20 UTC 更新。
- 覆盖范围以该提交 workflow 的测试过滤器为准：本地链接、编辑器/Web 链接、终端链接、Markdown 复制和 Space 引用。完整核心/TUI 测试不在该范围内。
- [CI 42641362734](https://github.com/owwkmidream/codex/actions/runs/42641362734) 虽为绿色，但 prepare/build/test/release 均跳过，不是新的构建或发布证据。

## 重试修订：0017

源码提交 `4d2a231`，维护提交 `a8bc004`。增加百万次上限，统一有符号等待策略，未配置时恢复官方等待策略。

| 检查 | 证据 |
|---|---|
| series 重放 | 17 个补丁在官方基线的干净 worktree 中全部应用成功，与源码提交的 `git diff --exit-code` 对照通过。 |
| 合并补丁重放 | 在官方基线的独立 Git index 应用成功，与源码提交的 `git diff --cached --exit-code` 对照通过。 |
| 格式与空白 | 受影响 Rust 文件经 rustfmt 1.95.0 格式化，源码 `git diff --check` 通过；stable rustfmt 提示 nightly 专属 imports_granularity 不可用。 |
| 编译与行为 | 首轮 [CI 42725085412](https://github.com/owwkmidream/codex/actions/runs/42725085412) 的 test 在 rustfmt 缺失时退出 1，未执行回归；workflow 已显式安装该组件，修复需由新运行验证。 |

CI 已接入等待策略单元测试、配置次数边界、流重连单元测试及 `retry_after` 集成回归。用例覆盖服务器长建议截断、较短原等待保留、零等待、负数固定等待、未配置原版退避、HTTP/流重连/传输回退和次数预算。

查询该修订及后续文档提交的状态：

```powershell
gh run list --workflow build-windows.yml --limit 5
gh run view RUN_ID
gh run view RUN_ID --log-failed
```

## 集成测试构造方修复：0018

- 源码提交 `88d27c0`；补齐 4 个 core 集成测试文件中 7 处 `ModelProviderInfo` 的 `retry_delay_ms: None`，保持未配置时的官方等待策略。
- [CI 42730102080](https://github.com/owwkmidream/codex/actions/runs/42730102080)：build 成功；test 在 `cargo test --locked --profile ci-test -p codex-core --test all retry_after::` 编译阶段报 7 处 E0063，release 跳过。重试单元测试通过，集成及后续 TUI 回归未完成。
- 18 个 series 补丁已在官方提交 `086ccc8` 的干净 worktree 重放，与源码提交对照无差异；合并补丁在独立 index 重放，对照同样通过。
- CI 格式检查加入这 4 个受影响测试文件；本机未运行 Rust 编译或测试。修复仍需新 CI 验证，状态为“实现已提交，集成验证未完成”。

## Custom 配置入口：0019

- 源码提交 `ee3b3ac`：`/config → Custom` 编辑当前 provider 的官方 `stream_max_retries`；全局 Delay 独立存储到 `$CODEX_HOME/custom.toml`，支持 Default/Capped/Fixed、非负毫秒和零等待。不迁移旧字段。
- 核心层按轮固定 Delay 和 Stream 次数快照；模型 HTTP、流重连、本地压缩及传输回退使用本轮设置。新增独立文件、次数刷新与默认恢复、保存不改动其他 provider、输入边界及宽窄终端渲染回归。
- 19 个 series 补丁在官方提交 `086ccc8` 的干净 worktree 重放成功，与源码提交 `git diff --exit-code` 无差异；合并补丁在独立 index 重放，与源码提交同样无差异。
- 本机 rustfmt 1.95.0 格式检查、源码空白检查通过；补丁维护脚本隔离回归 `python scripts/tests/test_apply_patches.py`：7 项通过，16.731 秒。未在本机运行 Cargo 构建或测试。
- 上一轮 [CI 42749759334](https://github.com/owwkmidream/codex/actions/runs/42749759334) 的重试集成命令 `cargo test --locked --profile ci-test -p codex-core --test all retry_after::` 在 Windows 以 `0xc00000fd / STATUS_STACK_OVERFLOW` 退出；本次将重试和 TUI 回归的 `RUST_MIN_STACK` 设为 16 MiB，并加入 Custom 回归及受影响文件格式检查。
- 本修订需由推送后的新 dispatch 验证；状态为“实现已提交，集成验证未完成”。真实终端操作及独立 daemon 的下轮生效仍需构建产物验收。

## Custom CI 修复：0020

- 源码提交 `ee379ef`：补齐 `app-server-client::legacy_core::custom_retry` 导出，修复 TUI 的 5 处 E0432/E0433；重试回归使用合法的自定义 provider，保留其定义以验证清空次数恢复默认值。
- 失败证据：[CI 42753862665](https://github.com/owwkmidream/codex/actions/runs/42753862665)，维护提交 `d8aec05`。build 在 TUI 编译阶段失败；test 的 `custom_retry::tests::saves_take_effect_next_turn_and_default_restores_official_count` 因覆盖内置 `openai` 被官方配置校验拒绝。此前 4 项重试测试与 Custom 独立文件用例通过；重试集成及后续 TUI 回归未执行，release 跳过。
- 内置 provider 不支持次数覆盖：Custom 显示不可编辑，保存端同时拒绝该写入；全局 Delay 保持可用。增加保存不改动原配置、内置 provider 禁用次数但仍可编辑 Delay 的回归。
- 20 个 series 补丁在官方提交 `086ccc8` 的干净 worktree 重放成功，与 `ee379ef` 对照无差异；合并补丁在官方提交的独立 index 应用成功，与 `ee379ef` 对照无差异。本地同名 tag 指向旧提交，校验使用完整官方提交 ID。
- 本机 rustfmt 1.95.0 与空白检查通过；未运行本地 Cargo 构建或测试。CI 格式检查新增 `app-server-client/src/lib.rs`；行为回归由现有 Custom 过滤器执行。状态为“实现已提交，集成验证未完成”，需新 dispatch 验证。

### 导航回归修订：0021

- 源码提交 `2361d1f`：列表会跳过禁用行，回归改为验证跳过内置 provider 的次数行后仍打开 Delay 编辑器。保留 `0020` 历史，追加测试修订补丁。
- 最终 21 个补丁在官方基线上顺序重放，与 `2361d1f` 源码一致；最终合并补丁在官方基线的独立 index 应用，与 `2361d1f` 同样无差异。变更文件的 rustfmt 1.95.0 和空白检查通过，未运行本地 Cargo 测试。
- [CI 42760149697](https://github.com/owwkmidream/codex/actions/runs/42760149697) 对应维护提交 `17e659a`，因测试修订被替代，已申请取消；最终提交需启动新 dispatch，状态仍为“实现已提交，集成验证未完成”。

## Capped 重试断言修复：0022

- 源码提交 `d83a5cf`：修正 5 个 SSE/WebSocket 集成测试的等待断言。首次原版退避为带抖动的 180～220ms，Capped 200ms 的正确结果为 180～200ms；保留次数、事件、请求和重连结果检查。
- 失败证据：[CI 42760278588](https://github.com/owwkmidream/codex/actions/runs/42760278588)，维护提交 `933543d`。build 成功；重试集成回归 42 项通过、5 项失败，实际等待 185～199ms 与固定 200ms 断言不符。此前重试与 Custom 单元测试通过；后续 TUI 回归未执行，release 跳过。
- 22 个 series 补丁在官方提交 `086ccc833bc9cf01024ad2dd6af7dbd421b6bf9a` 的干净 worktree 重放，与 `d83a5cf` 对照无差异；合并补丁在独立 index 应用，与该源码对照同样通过。
- rustfmt 1.95.0 格式检查和源码空白检查通过；未在本机运行 Cargo 构建或测试。状态为“实现已提交，集成验证未完成”，需新 dispatch 验证。

## Space 引用光标插入：0023

- 源码提交 `f8fbad8`：鼠标和键盘选区共用的引用入口改为在保留的输入光标处插入。`A|B` 引用后为 `A\n> 引用内容\n|\nB`，光标位于引用后的空行，后文整体后移。保留原文逐行前缀、缩进和空行。
- 使用 textarea 的插入操作移动文本元素，保留本地/远程图片、提及绑定和折叠粘贴；引用插入不执行选区替换或 Vim Replace 覆盖。历史选区清除和阅读位置保留沿用现有两条调用路径。
- 新增/更新 `transcript_quote` 回归：中文光标中间/开头/末尾/空草稿、连续引用与后续输入、原文末尾空行、远程附件，以及普通/Vim Replace 模式下后方本地图片、提及和折叠粘贴的负载与元素范围保留。CI 同时检查受影响 Rust 文件格式。
- 23 个 series 补丁在官方提交 `086ccc833bc9cf01024ad2dd6af7dbd421b6bf9a` 的新 worktree 重放，与 `f8fbad8` 的 `git diff --exit-code` 对照通过；合并补丁在官方基线的独立 index 应用，与该源码对照同样通过。
- 本机 rustfmt 1.95.0 和源码空白检查通过；按仓库约定未在本机运行 Cargo 构建或行为测试。推送后使用 `tag=rust-v0.167.0`、`force=true` 启动新 dispatch；状态为“实现已提交，集成验证未完成”。本轮交付截至推送并触发 CI，测试及构建结果由该次运行确认。

## 远程压缩重试断言修复：0024

- 源码提交 `56acf58`：两个远程压缩 v2 流失败用例复用 `assert_capped_first_retry_delay`，验证 Capped 200ms 下的 180～200ms 首次等待；保留次数、事件、请求和最终结果检查。
- 失败证据：[CI 42871940697](https://github.com/owwkmidream/codex/actions/runs/42871940697)，维护提交 `edfca38`。build 成功，重试集成 45 项通过、2 项失败，实际 191ms、182ms 与固定 200ms 断言不符；后续 TUI 回归未执行，release 跳过。
- 24 个 series 补丁在官方提交 `086ccc833bc9cf01024ad2dd6af7dbd421b6bf9a` 的干净 worktree 重放，与 `56acf58` 对照无差异；合并补丁在独立 index 重放，与该源码对照通过。rustfmt 1.95.0 与源码空白检查通过。
- 未在本机运行 Cargo 构建或测试；推送后以 `tag=rust-v0.167.0`、`force=true` 启动新 dispatch。状态为“实现已提交，集成验证未完成”。

## 验收缺口

- `0017` 需实际成功的 build/test；完成前状态为“实现已提交，集成验证未完成”。
- 真实 Windows Terminal 点击、编辑器定位、Space、压缩横幅、字节计数和 Esc 仍需用户部署后验收。
- 本轮未运行本地构建或测试。历史独立逻辑测试、旧版构建通过均不作为 `0017` 的验证结论。

## 排障线索

- 历史 E0004（实时对话遗漏进度事件匹配）由 `0012` 修复；E0616（TUI 私有字段访问）由 `0015` 修复。对应功能及测试随 series 保留。
- [CI 42600912285](https://github.com/owwkmidream/codex/actions/runs/42600912285) 发布 `0015`，92 项 TUI 回归通过；完整运行 105 分 08 秒，release 编译 94 分 07 秒。这些耗时属于旧提交。
- 历史 sccache 断连曾回退直接编译；根因未确认。诊断入口与附件说明见构建文档“CI 与失败定位”，不依据全零最终统计推断命中率。
- 更早的本地 V8 路径过长、权限失败和独立测试记录可从本文件 Git 历史追溯；当前验证统一使用 CI。
