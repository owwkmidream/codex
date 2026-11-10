# Codex Windows 补丁

本仓库保存可重放补丁，由 [workflow](.github/workflows/build-windows.yml) 构建 Windows x64 `codex.exe`。下载见 [Releases](https://github.com/owwkmidream/codex/releases)，验证证据见目标 series 的 `VALIDATION.md`。

## 功能约定

当前基线为官方 `rust-v0.167.0`。本节描述仓库源码；已发布附件的功能以该次构建提交的文档为准。

| 功能 | 行为 |
|---|---|
| 请求活动 | SSE/WebSocket 显示收发字节；同轮多请求累计、跨轮清零。进度事件不转成实时对话文本，当前无法持续取得准确的本次新增 token。 |
| 压缩横幅 | 复用 provider 能力解析，包含能力覆盖与 TokenBudget 条件，区分本地/远程压缩。 |
| 重试 | 请求和流重试次数上限 1,000,000，默认次数保持上游值；ServerOverloaded、PolicyCapacityUnavailable、RetryLimit 无建议时仍可重试。 |
| Cyber 提示 | 显示警告，UI 不主动结束 turn；Bio 保持上游处理。 |
| resume | 列出所有 provider 会话，保留目录过滤。 |
| 无输出 Esc | 固定中断 turn ID 并恢复提示词；已有答案、推理、计划或工具调用时保留原行为。 |
| SQLite 日志 | 保留 INFO 及以上级别。 |
| Space 引用 | 将选择内容逐行加上 `> ` 后插入输入光标处，光标停在引用后的空行，原后文从下一行开始；保留附件、提及和折叠粘贴，清除选区并保持阅读位置；无选区沿用原行为。 |
| 本地文件链接 | 支持 OSC 8 的终端显示 Markdown 标签，通过 `file_opener` 打开文件。 |
| 模型上下文 | 使用上游值。 |

### 重试配置

`/config → Custom` 提供快捷编辑，自动保存后下一轮生效，当前轮重试保持原设置。

**Stream Max Retry** 直接读写当前自定义 provider 的官方字段，页面显示 provider ID；次数为 `0～1,000,000`，清空输入恢复 Default。内置 provider 使用官方默认次数，界面禁用次数编辑；Delay 仍可编辑。仍可在现有自定义 provider 表中手动设置：

```toml
model_provider = "openai-custom"

[model_providers.openai-custom]
name = "OpenAI custom"
base_url = "https://api.openai.com/v1"
wire_api = "responses"
requires_openai_auth = true
request_max_retries = 1000000
stream_max_retries = 1000000
```

- 次数表示首次请求之外的重试次数；两项上限均为 1,000,000，默认次数保持上游值。

**Retry Delay** 是跨 provider 的全局设置，独立保存在 `$CODEX_HOME/custom.toml`，不向官方 `config.toml` 或其 schema 添加字段：

```toml
retry_delay_mode = "capped"
retry_delay_ms = 10000
```

- `default`：沿用官方原版各路径的等待策略，保留补丁扩展的可重试错误类型；界面隐藏毫秒输入。
- `capped`：等待上限，取原等待与配置值的较小值，覆盖指数退避、服务器建议等所有来源。
- `fixed`：忽略所有等待来源，固定等待指定毫秒数。
- 时间只接受非负整数；`capped`、`fixed` 下零表示立即重试。未设置时为 Default，首次选择 Capped/Fixed 的时间为 10,000 毫秒。
- 不迁移或读取旧 provider 下的 `retry_delay_ms`；有旧字段时需自行移除。

等待配置适用于模型 HTTP、流重连、本地压缩和传输回退；非模型 HTTP 客户端保留原退避行为。核心层每轮读取设置，TUI、`codex exec` 和使用同一 `$CODEX_HOME` 的独立 daemon 共用；远程主机需要其自身的配置文件。Stream 次数保留官方配置层优先级，Custom 只编辑当前用户配置文件。`0019` 在保留历史补丁的基础上提供当前配置入口与持久化。

### 选择与文件链接

Ctrl+C 复制；Enter 复制并跟随最新输出；Space 引用不写入剪贴板。鼠标与键盘选区均插入提示词此前保留的输入光标处，保留原文换行、缩进及空行，包括末尾空行。例如 `A|B` 引用“内容”后成为 `A\n> 内容\n|\nB`（`|` 表示光标）。开头、末尾和空草稿遵循相同换行规则，连续引用从上次插入后的光标位置继续。

顶层配置 `file_opener` 支持 `vscode`（默认）、`vscode-insiders`、`windsurf`、`cursor`；`none` 禁用编辑器链接。它独立于 Ctrl+G 的 `$VISUAL`/`$EDITOR`。

- 支持盘符路径、`/c:/…`、`file:///…` 和相对路径；相对路径固定基于该消息的会话 cwd，与 `/pwd` 同源。复制 Markdown 保留绝对文件 URI，切换目录不改写已有链接。
- 支持空格、中文、百分号及 `:行[:列]`、`#L行[C列]`、范围后缀；范围定位到起点。Markdown 目标含空格时用 `<...>` 包裹。
- `~/`、UNC、无 cwd、控制字符或转换失败时保留路径。未知终端、复用器、重定向输出沿用显示回退。
- 普通点击使用白名单编辑器协议处理器，Windows Terminal 的 Ctrl+左键由终端处理 OSC 8。普通 Markdown 不获得 `TrustedFile` 能力，通用链接仍只接受 HTTP/HTTPS。

## 安装与 daemon 更新

推荐在 Git Bash 使用单文件脚本 `bash scripts/codex-patch.sh`，安装和还原均匹配已有 npm 包版本；参数、摘要识别及 daemon 行为见 [scripts/README.md](scripts/README.md)。本机部署由用户发起。手动安装：

1. 下载 Release zip，核对其中 `BUILD-INFO.txt` 的 `upstream_tag`、`patch_baseline` 和 `patch_is_exact`。
2. 安装同版本完整 npm 包，例如 `npm install -g @openai/codex@0.167.0`，使辅助程序匹配。
3. 退出占用目标文件的 CLI 并备份；将 zip 内的 `codex.exe` 覆盖到 `npm root -g` 下的 `@openai/codex/node_modules/@openai/codex-win32-x64/vendor/x86_64-pc-windows-msvc/bin/codex.exe`。
4. 运行 `codex --version`。使用独立 daemon 时，在会话空闲后执行：

```powershell
codex app-server daemon update --from-cli
codex app-server daemon version
codex app-server daemon status
```

CLI 与 daemon 使用不同磁盘副本，daemon 路径以 `managedCodexPath` 为准。`--from-cli` 固定当前完整 CLI 包并重启 daemon；不带该参数的 `daemon update` 恢复官方生产更新通道。自动更新开关是 `$CODEX_HOME/app-server-daemon/settings.json` 的 `updater.autoUpdateEnabled`，独立于 `config.toml`。回滚时恢复同版本完整 npm 包及补丁，再同步 daemon。

## CI 与失败定位

Codex 二进制的构建、测试及相关重型依赖准备在 CI 执行；仓库脚本的语法检查和隔离测试优先在本机执行，授权边界见 [AGENTS.md](AGENTS.md)。CI 命令与缓存配置以 [workflow](.github/workflows/build-windows.yml) 为准，受影响行为的证据见 [VALIDATION.md](patches/series/rust-v0.167.0/VALIDATION.md)。

```powershell
gh workflow run build-windows.yml --ref main -f tag=rust-v0.167.0 -f force=true
gh run list --workflow build-windows.yml --limit 5
gh run view RUN_ID
gh run view RUN_ID --log-failed
```

`tag` 留空使用最新正式版；`force=true` 忽略已构建记录。修复提交后须启动新 dispatch；`gh run rerun RUN_ID --failed` 只适合重试原提交的临时环境故障。

| 阶段 | 查看什么 |
|---|---|
| prepare | `patch-conflicts` 附件中的功能补丁名、应用日志和冲突。 |
| build | 依赖获取、协议生成/校验、release 编译；核对 `codex-windows-x64` 附件与版本输出。 |
| test | 格式检查、重试回归、本地链接和 Space 引用回归；完整命令见 workflow。 |
| release | 实际成功状态、Release 附件及 `built-tags.txt`。 |

`prepare` 失败反馈 Issue 或版本已构建时，run 可能绿色而没有产物。发布完成须确认 build/test/release 均实际成功。`built-tags.txt` 仅由成功发布的 CI 维护。

构建与测试分别上传 `cache-diagnostics-build`、`cache-diagnostics-test`，保留 7 天；内含 sccache 日志、统计、资源采样及 Windows 事件。sccache 失败可回退直接编译，最终全零统计不能代表整轮命中率。性能结论须对照实际耗时与采样。

## 维护补丁

1. 固定官方 tag，在干净上游 checkout 重放 `patches/series/<tag>/*.patch`。CI 使用 `git am --3way`；没有专属 series 时尝试最新基线，冲突停止并报告对应功能。
2. 按功能追加提交与编号补丁，保留已有提交和历史版本。测试、schema、跨层事件和公开导出随行为更新。
3. 导出两种产物，并在干净基线上重放后比较源码：

```bash
git am /path/to/patches/series/rust-v0.167.0/*.patch
git diff --binary --full-index rust-v0.167.0 HEAD -- . ':!codex-rs/Cargo.lock' > /path/to/patches/rust-v0.167.0.patch
git format-patch --binary --full-index --no-signature --start-number NEXT -1 HEAD -o /path/to/patches/series/rust-v0.167.0
```

`NEXT` 是下一个编号；一次追加多个提交时调整提交范围。新版本写入新 tag 目录。跨版本迁移可用 `git rebase --onto <新tag> rust-v0.167.0`；上游已有等价功能时先核对配置兼容再移除对应补丁。

CI 入口：`bash scripts/apply-patches.sh /path/to/upstream patches/rust-v0.167.0.patch rust-v0.167.0 /tmp/codex-patch-report`。补丁流程的隔离回归命令为 `python scripts/tests/test_apply_patches.py`，可直接在本机运行，CI 同样执行。

Cargo.lock 的 workspace 版本由 CI 对齐。协议 JSON、TypeScript 和压缩导出通过上游生成器重建，功能提交保存相关源码。源码归档包含功能历史与隐藏配置；`patched-source` 附件保留 7 天。跨机器恢复以持久保存的邮件补丁为准。

完成条件：合并补丁与 series 重放源码一致，受影响 CI 测试与完整构建通过；发布另核对 release 和附件。未通过集成验证时明确标为“实现已提交，集成验证未完成”。
