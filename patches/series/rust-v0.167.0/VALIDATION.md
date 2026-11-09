# rust-v0.167.0 补丁验证记录

日期：2026-11-09。基线：官方 `rust-v0.167.0`，提交 `086ccc833bc9cf01024ad2dd6af7dbd421b6bf9a`。

## 产物与迁移

- 合并补丁：`patches/rust-v0.167.0.patch`。
- 本目录 `0001` 至 `0014` 为可用 `git am` 恢复的功能提交及其修订，按编号依次应用。`0012` 补齐实时对话对字节进度事件的匹配分支，修复 E0004 编译错误；`0013` 修复 Space 多行逐行引用；`0014` 接入普通本地文件链接的编辑器 OSC 8、路径兼容和 Markdown 复制目标。
- 历史补丁保持原样；新补丁不包含 Cargo.lock、models.json 或协议导出目录。
- 协议 JSON、TypeScript、内嵌压缩文件由 workflow 调用上游生成器重建，避免维护二进制差异。自行构建时也必须执行该生成步骤。

## 已执行的检查

| 检查 | 实际结果 |
|---|---|
| 合并补丁在原始 tag 的独立 Git index 上检查和应用 | 成功，应用后的 tree 与功能分支一致 |
| 13 个邮件补丁在干净 checkout 中通过 CI 入口依次 `git am --3way` | 成功，最终源码与合并补丁、功能源码分支一致；加入 0013 后已重新验证两种产物重放 |
| 源码 `git diff --check` 与全部修改的 Rust 文件 `rustfmt --check` | 通过；stable rustfmt 提示上游 nightly 专属 imports_granularity 配置不可用 |
| 从实际源码提取的重试等待函数和字节累计器，独立 `rustc --test` | 2 项通过，覆盖正负等待、服务端建议、零、i64::MIN、同轮多请求累计 |
| 新增进度类型的 Rust 派生 | 在最小工程中使用匹配版本 serde/schemars/ts-rs 编译及生成成功；字节字段导出为 TS number |
| 临时协议导出校对 | 新类型 JSON/TS 与实际 Rust 派生一致，稳定版/实验版 JSON 引用可解析，临时内嵌导出与文件一致；此项不代替完整上游生成器检查 |
| workflow | YAML 解析和新增步骤的 `bash -n` 通过 |
| 新 CI 补丁入口 | 6 项隔离 Git 回归通过：精确应用、稳定提交标识、跨版本上下文合并及功能依赖、功能冲突定位、基线重建失败、旧版合并补丁精确/三方应用 |
| 源码归档 | 实际 0.167.0 源码 tar 打包/还原通过，保留 `.git`、隐藏 `.cargo/config.toml` 及 Space 修改；对应 fixture 修正 Windows tar 路径后，Python 启动返回 Permission denied，未完成该 fixture 复跑 |
| Space 字符串逻辑 | 采用实际实现表达式的独立 `rustc --test` 通过，覆盖单行、多行、空行、缩进、末尾/开头换行、CRLF 和已有引用；不代替完整 TUI 回归 |
| 新 workflow 静态检查 | YAML 解析、21 个 Bash 步骤的 `bash -n`、内嵌 Python 语法检查通过 |

## 行为回归覆盖

已补充或调整源码测试，但以下 crate 测试尚未成功执行：

- HTTP 与流重连：默认/正数遵从建议，负数忽略建议；无建议时采用配置，原非模型 HTTP 指数退避测试保留。
- HTTP 回退：正数遵从建议、无建议等待配置值、负数忽略长建议；重试预算不变。
- SSE/WebSocket：无建议的 overload、policy capacity、retry limit 仍可重试；重连等待保持固定配置。
- Space：无选区和空锚点保留原行为；有选区逐行添加引用前缀，空行和缩进保留，清除选择并保留阅读位置；草稿尾部追加并保留附件。
- 压缩横幅：复用上游 provider 能力解析，覆盖用户关闭远程压缩的配置。
- 无输出 Esc：工具调用开始/完成后不走无输出回滚；真正无输出时恢复提示词。
- 字节累计：同轮跨请求累计、跨轮清零；完成轮次的延迟通知被忽略。
- 实时对话：发送和接收阶段的字节进度事件均不生成交接文本或推理状态。

## 阻断与待验证

本地链接补丁 `0014`：

- 源码提交 `539b03d`；14 个 series 在官方基线的干净 worktree 中 `git am` 成功，合并补丁在独立 Git index 中应用成功，两者均通过 `git diff --exit-code` 与源码提交对照。
- 从实际生产源码提取路径解析、编辑器目标校验和对应测试，使用原 `codex-utils-path-uri` / `codex-utils-string` 依赖在独立临时 Cargo 工程执行：4 项通过（包括原有根路径测试）。覆盖 Windows 盘符及 `/c:/`、相对路径、文件 URI、空格中文、百分号、行列范围、`none` 和不安全目标；发现并修复了复制往返中的盘符大小写差异。
- 已补充 TUI 用例：短标签、表格和窄屏换行、Markdown 复制、流式与完整渲染一致、cwd 固定、禁用/终端回退、OSC 8 滚动和协议边界。它们尚未执行成功。
- `cargo +1.95.0 test --offline -p codex-tui --lib local_links` 首次在 60 秒内无输出而终止；随后增加诊断输出重试，明确在加载 `v8` 的 `third_party/rust` 子模块时因 Windows 路径过长退出 101，尚未编译 TUI。未修改全局 Git/Cargo 配置。
- 受影响 Rust 文件的 `rustfmt +1.95.0 --edition 2024 --check` 和 `git diff --check` 通过；独立路径测试不代替完整 TUI 测试、真实 Windows Terminal 点击与编辑器定位验收。
- CI 新增独立 Windows `test` job，与 `build` 并行，复用 `patched-source`、Rust cache 和 sccache；Rust target 缓存按 job 分开保存，避免并行写入相同不可变键。一次编译 TUI 测试目标，执行本地链接及相邻回归；`release` 需同时等待 `build`、`test` 成功。
- 新增测试 job 后的 YAML 解析、27 个 Bash 步骤语法检查及维护文件 `git diff --check` 通过；本轮未在本机运行构建、测试或下载测试依赖。缓存命中与耗时待云端运行测量。
- CI [42568144779](https://github.com/owwkmidream/codex/actions/runs/42568144779) 下载 sccache 返回 HTTP 504；[42563437087](https://github.com/owwkmidream/codex/actions/runs/42563437087) 在编译 `codex-tui` 时读取 sccache 响应失败（`os error 10054`）。两者未报告 Rust 源码诊断。workflow 已将安装和统计改为非阻断步骤，仅安装成功时启用 wrapper，并通过 `SCCACHE_IGNORE_SERVER_IO_ERROR=1` 在响应连接中断时由 CI runner 直接编译。修复后的 YAML、显式 Bash 步骤语法及 diff 检查通过；实际构建与测试结果仍需新运行确认。

CI 执行 `cargo test --locked --profile ci-test -p codex-tui --lib -- local_links editor_links web_links terminal_hyperlinks markdown_copy`，测试 profile 关闭调试信息。发布前确认 build、test 与 release 的实际结果；当前实现已提交，集成验证未完成，未在本机部署。

CI [42519034906](https://github.com/owwkmidream/codex/actions/runs/42519034906) 的 release 编译曾在 `realtime_text_for_event()` 漏匹配 `ModelRequestProgress` 处报 E0004。`0012` 修复后，新运行 [42524866183](https://github.com/owwkmidream/codex/actions/runs/42524866183) 的协议生成校验、build、release 均成功，已有 `codex-rust-v0.167.0-windows-x64.zip` 附件。这份已发布产物尚不含 `0013`。

加入 `0013` 后，修改文件的 `git diff --check` 与 `rustfmt +1.95.0 --edition 2024 --check` 通过。`cargo +1.95.0 test --offline --manifest-path codex-rs/Cargo.toml -p codex-tui --lib quote_appends_to_draft_tail_and_preserves_attachments` 在 60 秒内没有返回测试结果，进程树按测试超时终止；完整 TUI 回归尚未验证。新 workflow 的 sccache 命中及实际提速仍需新 CI 测量。

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
