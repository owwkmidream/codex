# rust-v0.169.0 验证证据

官方基线：`d32063f96c2dff1dc96af839b3952abb6acfeda4`。最终源码提交：`1b2b620e41d41a0fc943ba9e6bf2933505623c65`。功能约定见 [CODEX-BUILD.md](../../../CODEX-BUILD.md)。

## 迁移范围

- 对应 [Issue #14](https://github.com/owwkmidream/codex/issues/14)：旧 series 的 `0001` 与上游本地压缩重试分支冲突，prepare 后 build/test/release 跳过。
- 从 `rust-v0.167.0` 最终源码 `8cbabb2` 的净差异迁移，整理为 9 个功能补丁；旧版 25 个补丁和合并补丁保持原样。
- 逐项处理 11 个冲突文件，保留上游鉴权所有权检查、Guardian 响应筛选、重试截止时间、配置页 provider/折叠设置入口、Markdown 列测量与列表间距。补齐新增 Guardian 枚举分支及实时鉴权测试构造方。
- 扩展内联代码链接回归，Cyber 警告回归验证当前轮保持运行；CI 检查实际变更 Rust 文件，增加实时鉴权、Guardian、压缩横幅、字节累计及 Esc 行为过滤器。

## 验证与缺口

- 迁移时的 9 个 series 补丁经 `scripts/apply-patches.sh` 在官方干净 worktree 顺序重放，与迁移源码提交 `04674a6` 的 `git diff --exit-code` 对照通过。
- 迁移时的合并补丁在官方基线的独立 index 应用，与迁移源码提交 `04674a6` 的 `git diff --cached --exit-code` 对照通过。
- rustfmt 1.95.0 检查全部 111 个受影响 Rust 文件通过；源码空白检查通过。
- 补丁脚本隔离回归 `python scripts/tests/test_apply_patches.py`：7 项通过，16.886 秒。本机未运行 Cargo 编译或行为测试。
- workflow YAML 解析通过，21 个 Bash 步骤语法检查通过；动态格式检查列表在 `codex-rs` 下解析出 111 个现存 Rust 文件。
- 构建提交：`962fff22d448d1bfed054292f9263907addc1a02`；[CI 43903342391](https://github.com/owwkmidream/codex/actions/runs/43903342391) 使用 `tag=rust-v0.169.0`、`force=true`。prepare、script-test、build 成功；test 编译失败，release 跳过，详情见下面的 0010 修订。
- Rust 编译、协议导出重建及行为回归由 CI 验证。当前状态：实现已提交，集成验证未完成；Issue #14 保持开放，待修复提交的 build/test/release 及附件验收。
- 真实 Windows Terminal 点击、Space 操作及独立 daemon 下轮生效仍需构建产物验收；本次未部署本机。

## 终止错误流测试适配：0010

- 源码提交 `1b2b620`：补齐 `responses_error_tests.rs` 中 `spawn_response_stream` 的 `request_bytes` 参数，使用无实际请求的 `0`；测试允许请求和响应字节进度事件通过，保留终止错误分类、不可重试及流结束断言。
- 失败命令：`cargo test --locked --profile ci-test -p codex-api --lib realtime_websocket::methods::auth_tests`。上述 CI 在测试编译阶段报 `error[E0061]: this function takes 5 arguments but 4 arguments were supplied`，位置为 `codex-api/src/sse/responses_error_tests.rs:147:30`，缺少第二个 `u64` 参数，退出码为 101；该阶段及后续行为回归未完成。
- CI 增加 `cargo test --locked --profile ci-test -p codex-api --lib sse::responses::error_tests`，直接执行受影响测试模块；格式检查沿用实际变更 Rust 文件清单。
- 10 个 series 补丁在官方基线的干净 worktree 顺序重放，与 `1b2b620` 的 `git diff --exit-code` 对照通过；更新后的合并补丁在官方基线独立 index 应用，与该源码的 `git diff --cached --exit-code` 对照通过。
- 修改文件的 rustfmt 1.95.0 检查和源码空白检查通过。本机未运行 Cargo 编译或行为测试；提交推送后启动新 dispatch，结果以该次 CI 为准。
