# rust-v0.169.0 验证证据

官方基线：`d32063f96c2dff1dc96af839b3952abb6acfeda4`。最终源码提交：`04674a62e85e24334dfbc0f198d747592288eb4e`。功能约定见 [CODEX-BUILD.md](../../../CODEX-BUILD.md)。

## 迁移范围

- 对应 [Issue #14](https://github.com/owwkmidream/codex/issues/14)：旧 series 的 `0001` 与上游本地压缩重试分支冲突，prepare 后 build/test/release 跳过。
- 从 `rust-v0.167.0` 最终源码 `8cbabb2` 的净差异迁移，整理为 9 个功能补丁；旧版 25 个补丁和合并补丁保持原样。
- 逐项处理 11 个冲突文件，保留上游鉴权所有权检查、Guardian 响应筛选、重试截止时间、配置页 provider/折叠设置入口、Markdown 列测量与列表间距。补齐新增 Guardian 枚举分支及实时鉴权测试构造方。
- 扩展内联代码链接回归，Cyber 警告回归验证当前轮保持运行；CI 检查实际变更 Rust 文件，增加实时鉴权、Guardian、压缩横幅、字节累计及 Esc 行为过滤器。

## 验证与缺口

- 9 个 series 补丁经 `scripts/apply-patches.sh` 在官方干净 worktree 顺序重放，与最终源码提交 `git diff --exit-code` 对照通过。
- 合并补丁在官方基线的独立 index 应用，与最终源码提交 `git diff --cached --exit-code` 对照通过。
- rustfmt 1.95.0 检查全部 111 个受影响 Rust 文件通过；源码空白检查通过。
- 补丁脚本隔离回归 `python scripts/tests/test_apply_patches.py`：7 项通过，16.886 秒。本机未运行 Cargo 编译或行为测试。
- workflow YAML 解析通过，21 个 Bash 步骤语法检查通过；动态格式检查列表在 `codex-rs` 下解析出 111 个现存 Rust 文件。
- Rust 编译、协议导出重建及行为回归由新 CI 验证。当前状态：实现已提交，集成验证未完成。
- 真实 Windows Terminal 点击、Space 操作及独立 daemon 下轮生效仍需构建产物验收；本次未部署本机。
