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

## 验收缺口

- `0017` 需实际成功的 build/test；完成前状态为“实现已提交，集成验证未完成”。
- 真实 Windows Terminal 点击、编辑器定位、Space、压缩横幅、字节计数和 Esc 仍需用户部署后验收。
- 本轮未运行本地构建或测试。历史独立逻辑测试、旧版构建通过均不作为 `0017` 的验证结论。

## 排障线索

- 历史 E0004（实时对话遗漏进度事件匹配）由 `0012` 修复；E0616（TUI 私有字段访问）由 `0015` 修复。对应功能及测试随 series 保留。
- [CI 42600912285](https://github.com/owwkmidream/codex/actions/runs/42600912285) 发布 `0015`，92 项 TUI 回归通过；完整运行 105 分 08 秒，release 编译 94 分 07 秒。这些耗时属于旧提交。
- 历史 sccache 断连曾回退直接编译；根因未确认。诊断入口与附件说明见构建文档“CI 与失败定位”，不依据全零最终统计推断命中率。
- 更早的本地 V8 路径过长、权限失败和独立测试记录可从本文件 Git 历史追溯；当前验证统一使用 CI。
