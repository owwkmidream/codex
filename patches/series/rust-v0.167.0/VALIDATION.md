# rust-v0.167.0 补丁验证记录

日期：2026-11-09。基线：官方 `rust-v0.167.0`，提交 `086ccc833bc9cf01024ad2dd6af7dbd421b6bf9a`。

## 产物与迁移

- 合并补丁：`patches/rust-v0.167.0.patch`。
- 本目录 `0001` 至 `0012` 为可用 `git am` 恢复的功能提交及其修订，按编号依次应用。`0012` 补齐实时对话对字节进度事件的匹配分支，修复 E0004 编译错误，并补充收发阶段均不生成实时文本的回归测试。
- 历史补丁保持原样；新补丁不包含 Cargo.lock、models.json 或协议导出目录。
- 协议 JSON、TypeScript、内嵌压缩文件由 workflow 调用上游生成器重建，避免维护二进制差异。自行构建时也必须执行该生成步骤。

## 已执行的检查

| 检查 | 实际结果 |
|---|---|
| 合并补丁在原始 tag 的独立 Git index 上检查和应用 | 成功，应用后的 tree 与功能分支一致 |
| 12 个邮件补丁在干净 worktree 中依次 `git am` | 成功，最终源码与合并补丁一致；加入 0012 后已重新验证两种产物重放 |
| 源码 `git diff --check` 与全部修改的 Rust 文件 `rustfmt --check` | 通过；stable rustfmt 提示上游 nightly 专属 imports_granularity 配置不可用 |
| 从实际源码提取的重试等待函数和字节累计器，独立 `rustc --test` | 2 项通过，覆盖正负等待、服务端建议、零、i64::MIN、同轮多请求累计 |
| 新增进度类型的 Rust 派生 | 在最小工程中使用匹配版本 serde/schemars/ts-rs 编译及生成成功；字节字段导出为 TS number |
| 临时协议导出校对 | 新类型 JSON/TS 与实际 Rust 派生一致，稳定版/实验版 JSON 引用可解析，临时内嵌导出与文件一致；此项不代替完整上游生成器检查 |
| workflow | YAML 解析和新增步骤的 `bash -n` 通过 |

## 行为回归覆盖

已补充或调整源码测试，但以下 crate 测试尚未成功执行：

- HTTP 与流重连：默认/正数遵从建议，负数忽略建议；无建议时采用配置，原非模型 HTTP 指数退避测试保留。
- HTTP 回退：正数遵从建议、无建议等待配置值、负数忽略长建议；重试预算不变。
- SSE/WebSocket：无建议的 overload、policy capacity、retry limit 仍可重试；重连等待保持固定配置。
- Space：无选区和空锚点保留原行为；有选区产生引用，清除选择并保留阅读位置；草稿尾部追加并保留附件。
- 压缩横幅：复用上游 provider 能力解析，覆盖用户关闭远程压缩的配置。
- 无输出 Esc：工具调用开始/完成后不走无输出回滚；真正无输出时恢复提示词。
- 字节累计：同轮跨请求累计、跨轮清零；完成轮次的延迟通知被忽略。
- 实时对话：发送和接收阶段的字节进度事件均不生成交接文本或推理状态。

## 阻断与待验证

CI [42519034906](https://github.com/owwkmidream/codex/actions/runs/42519034906) 的补丁应用、完整协议生成和一致性检查通过；release 编译在 `realtime_text_for_event()` 漏匹配 `ModelRequestProgress` 处报 E0004，发布 job 跳过。`0012` 修复该分支；修复源码的 `git diff --check` 和 `rustfmt +1.95.0 --edition 2024 --check` 通过，完整编译结果需查看修复提交触发的新 CI。

本次执行 `cargo +1.95.0 test --offline -p codex-core --lib realtime_model_request_progress_has_no_text` 在依赖加载阶段因本机 V8 checkout 访问被拒绝（os error 5）失败，尚未编译或运行该测试。未修改本机 Cargo 缓存权限。

`cargo test -p codex-client --lib configured_retry_tests` 在依赖获取阶段退出 101，尚未开始编译测试目标：

```text
failed to load source for dependency v8
unable to update https://github.com/seanh-oai/rusty_v8.git?rev=350c5a859a9b3c84ab8701b3ad51e3b7699b30c0
failed to update submodule third_party/rust
path too long .../vendor/icu_calendar-v2/src/tests/snapshots/icu_calendar__tests__date_arithmetic_snapshot__date_add_snapshot__date_add_snapshot_Ethiopian (Amete Alem).snap
class Filesystem (30)
```

维护者需在可构建环境执行完整协议生成/一致性测试、受影响的 Rust 测试与 release 构建，再验证 Windows TUI 的 Space、压缩横幅、字节计数和 Esc 行为。新增重试测试及 TUI 快照目前只有源码审查和格式检查结果。

GitHub Issue #13 的补丁应用问题已有可重放产物，Issue 保持打开，等待构建和行为验收。本机二进制替换、daemon 设置修改及运行中进程重启不属于本次 CI 修复范围。
