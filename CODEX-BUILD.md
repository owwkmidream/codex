# Codex Windows 补丁构建

本仓库维护官方 tag 对应的补丁，通过 [workflow](.github/workflows/build-windows.yml) 构建并发布 Windows x64 `codex.exe`。构建结果查看 [Actions](https://github.com/owwkmidream/codex/actions)，产物下载见 [Releases](https://github.com/owwkmidream/codex/releases)。

## 安装与手动更新

自动下载、备份、替换 CLI 并同步 daemon，可使用 [scripts/codex-patch.bat](scripts/codex-patch.bat)；安装、恢复与状态检查参数见 [脚本说明](scripts/README.md)。以下为手动流程。

1. 下载目标版本 Release 的 zip，核对其中 `BUILD-INFO.txt` 的 `upstream_tag`。
2. 安装相同版本的完整 npm 包，使辅助程序保持匹配，例如 `npm install -g @openai/codex@0.167.0`。
3. 退出占用目标文件的 CLI，备份原文件，将 zip 中的 `codex.exe` 覆盖到 `npm root -g` 输出目录下的：

```text
@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\bin\codex.exe
```

4. 运行 `codex --version` 核对版本。使用独立守护进程时，在会话空闲时同步当前 CLI 包并核对状态：

```powershell
codex app-server daemon update --from-cli
codex app-server daemon version
codex app-server daemon status
```

CLI 与 daemon 使用不同的磁盘副本，daemon 实际路径以 `managedCodexPath` 输出为准。`update --from-cli` 会固定使用当前 CLI 包，并重启运行中的 daemon；不带该参数的普通 `update` 会恢复官方生产更新通道。

自动更新开关位于 `$CODEX_HOME/app-server-daemon/settings.json` 的 `updater.autoUpdateEnabled`，与 `config.toml` 分开。回滚时恢复同版本完整 npm 包及补丁，再同步 daemon。

## 当前补丁：0.167.0

| 功能 | 行为 |
|---|---|
| 请求活动 | SSE/WebSocket 显示收发字节，同轮多请求累计、跨轮清零；进度事件不转成实时对话文本。目前无法持续取得准确的本次新增 token。 |
| 压缩横幅 | 复用上游 provider 能力解析，包含能力覆盖及 TokenBudget 条件，区分本地/远程压缩。 |
| 重试 | 次数允许上限 1000，默认次数保持上游值；ServerOverloaded、PolicyCapacityUnavailable、RetryLimit 无建议时仍可重试。 |
| Cyber 提示 | 显示警告，UI 不主动结束 turn；Bio 保持上游处理。 |
| resume | 列出所有 provider 的会话，保留目录过滤。 |
| 无输出 Esc | 固定中断 turn ID 并恢复提示词；已有答案、推理、计划或工具调用时保留原中断行为。 |
| SQLite 日志 | 保留 INFO 及以上级别。 |
| Space 引用 | 选中文字时向 prompt 尾部追加 `\n> 选中文字\n`，保留附件等草稿内容，清除选区并保持阅读位置；无选区沿用原行为。 |
| 模型上下文 | 使用上游值。 |

Ctrl+C 复制；Enter 复制并跟随最新输出；Space 不复制到剪贴板。多行引用保留原文，仅在整体前面加一个 `> `。

### 重试配置

在现有 provider 表中加入字段：

```toml
[model_providers.openai]
request_max_retries = 1000
stream_max_retries = 1000
retry_delay_ms = 10000
```

- 未配置等待：有服务端建议时遵从建议，否则等待 10 秒。
- `retry_delay_ms >= 0`：优先采用建议，无建议时等待配置毫秒数；`0` 表示无建议时立即重试。
- `retry_delay_ms < 0`：忽略建议，固定等待绝对值毫秒数，例如 `-10000` 为 10 秒。

等待配置适用于模型 HTTP、流重连、本地压缩及传输回退；非模型 HTTP 客户端保留原退避行为。

## 构建成功后

确认 `build`、`release` 都成功，再按安装步骤部署。核对 zip 内的 `patch_baseline` 和 `patch_is_exact`，确认实际使用的补丁来源；部署后在 TUI 验证 Space、附件、字节计数和 Esc。

CI 校验协议导出、构建产物及 `--version`，完整核心/TUI 回归需另行运行。0.167.0 的验证范围见 [VALIDATION.md](patches/series/rust-v0.167.0/VALIDATION.md)。

## 构建失败后

在本仓库目录执行，将 `RUN_ID` 替换为目标运行编号：

```powershell
gh run list --workflow build-windows.yml --limit 5
gh run view RUN_ID --log-failed
```

按失败步骤处理：`prepare` 查补丁冲突；`build` 区分依赖获取、编译、协议生成和测试失败；`release` 查发布及 tag 记录，已构建产物可从 `codex-windows-x64` artifact 获取。

临时环境故障可用 `gh run rerun RUN_ID --failed` 重跑原提交。修复推送后启动新运行，才能使用新提交：

```powershell
gh workflow run build-windows.yml --ref main -f tag=rust-v0.167.0 -f force=true
```

`tag` 留空使用最新正式版；`force=true` 忽略已构建记录。`built-tags.txt` 由发布成功的 CI 维护；补丁应用失败可能仍使整体运行显示绿色，应检查实际 jobs 与附件。

## 维护与迁移

在包含官方 tag 的上游 checkout 中恢复功能提交，再迁移、验证和导出：

```bash
git switch -c patched/rust-v0.167.0 rust-v0.167.0
git am /path/to/patches/series/rust-v0.167.0/*.patch
git switch -c patched/<新tag>
git rebase --onto <新tag> rust-v0.167.0
git diff --binary --full-index <新tag> HEAD -- . ':!codex-rs/Cargo.lock' > /path/to/patches/<新tag>.patch
git format-patch --binary --full-index --no-signature -o /path/to/patches/series/<新tag> <新tag>..HEAD
```

按功能保留小提交，旧版本补丁保持原样；合并补丁与 series 应在干净基线上重放得到相同源码。上游已提供同等能力时，核对行为及配置兼容后移除对应补丁。

Cargo.lock 版本由 CI 对齐。协议 JSON、TypeScript 和压缩导出通过 workflow 的“重建并校验协议导出”步骤生成，留在构建工作区；功能提交保存源码，导出时使用 `HEAD` 排除未提交的生成物。
