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
| Space 引用 | 选中文字时向 prompt 尾部追加引用，每行（含空行）都添加 `> `，保留附件等草稿内容，清除选区并保持阅读位置；无选区沿用原行为。 |
| 本地文件链接 | 支持 OSC 8 的终端显示 Markdown 标签，通过 `file_opener` 打开文件；相对路径基于该消息的会话 cwd（与 `/pwd` 同源），复制 Markdown 保留绝对目标。 |
| 模型上下文 | 使用上游值。 |

Ctrl+C 复制；Enter 复制并跟随最新输出；Space 不复制到剪贴板。多行引用保留原文换行和缩进，例如 `第一行\n第二行` 追加为 `\n> 第一行\n> 第二行\n`；原文末尾有换行时，末尾空行也带引用前缀。

### 本地文件链接

`[SKILL.md:19](C:/project/SKILL.md:19)` 在现有终端能力检测支持 OSC 8 时只显示 `SKILL.md:19`。复用 Web 链接的终端列表；未知终端、复用器、重定向输出或目标转换失败时继续显示路径。

在 `config.toml` 顶层设置 `file_opener = "vscode"`（默认值），也可选 `vscode-insiders`、`windsurf`、`cursor`；`none` 禁用编辑器链接并保留路径。此配置独立于 Ctrl+G 的 `$VISUAL` / `$EDITOR`。终端点击通过系统已注册的编辑器 URI 协议打开，不执行环境变量中的命令。

支持 `C:/…`、`C:\…`、`/c:/…`、`file:///C:/…`，以及 `src/file.rs`、`./src/file.rs`、`../file.rs` 等相对路径。路径中的空格和中文经过 URI 编码；Markdown 目标含空格时用 `<...>` 包裹。相对路径使用消息渲染上下文保存的会话 cwd，切换目录不会改写已有链接；复制后的 Markdown 使用绝对文件 URI，粘贴到其他目录仍指向原文件。

位置接受 `:行[:列]`、`#L行[C列]` 和范围。生成 `编辑器://file/绝对路径:行:列`，范围定位到起点，复制保留完整范围。[VS Code 文档](https://code.visualstudio.com/docs/configure/command-line#_opening-vs-code-with-urls)明确支持行列定位；其他配置的编辑器接收同样的 URI 位置后缀，实际定位由其协议处理器支持。`~/`、UNC 路径、无 cwd 的相对路径，以及控制字符或无法转换的目标保留路径回退。

普通 Markdown 只生成白名单编辑器协议，使用独立的链接类型；不会获得 `TrustedFile` 能力，也不放宽通用 `osc8_hyperlink()` 的 HTTP/HTTPS 校验。本次补丁尚未完成完整 TUI 编译及终端点击验收，详见验证记录。

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

确认 `build`、`test`、`release` 都成功，再按安装步骤部署。核对 zip 内的 `patch_baseline` 和 `patch_is_exact`，确认实际使用的补丁来源；部署后在 TUI 验证 Space、附件、字节计数和 Esc。

CI 校验协议导出、构建产物及 `--version`；独立 Windows `test` job 与 `build` 同时依赖 `prepare`，一次编译 `codex-tui --lib`，按 `local_links`、`editor_links`、`web_links`、`terminal_hyperlinks`、`markdown_copy` 的名称并集执行相关回归，并运行 `quote_appends_to_draft_tail_and_preserves_attachments` 验证 Space 引用及附件保留。`release` 等待两者成功。完整核心/TUI 回归不在本 job 范围内。0.167.0 的验证范围见 [VALIDATION.md](patches/series/rust-v0.167.0/VALIDATION.md)。

### 构建耗时与缓存

- `Swatinem/rust-cache` 保留依赖下载及依赖编译产物；`sccache` 使用 GitHub Actions 缓存复用项目 crate 的编译输入，不按官方 tag 人工分桶。源码、编译器和编译参数变化时由工具判断是否命中；新缓存首次构建需要预热。
- `prepare` 将源码和 `.git` 一起打包，Windows 直接恢复功能历史与隐藏配置，不再重新提交整份源码。功能提交使用固定作者日期作为提交者日期，同一目标和补丁生成稳定的 `STABLE_GIT_COMMIT`。
- 源码归档使用 `tar --dereference --hard-dereference`，将符号链接和硬链接展开为实际文件，避免 Windows 解压因链接权限或恢复顺序失败；Git 历史仍保留原始链接类型。缓存统计仅在 sccache 安装成功后执行。
- `build`、`test` 仅在 sccache 安装成功后设置 `RUSTC_WRAPPER`；下载失败时由 CI runner 直接编译，Cargo 依赖缓存仍可使用。`SCCACHE_IGNORE_SERVER_IO_ERROR=1` 让编译响应连接中断时回退到 runner 直接调用编译器，保留编译器退出码。缓存统计失败不阻断构建；回退可能增加耗时。
- 两个 job 分别上传 `cache-diagnostics-build`、`cache-diagnostics-test`，保留 7 天。`sccache-server.log` 记录服务启动、退出、编译缓存结果及错误，`sccache-stats.txt` 保存最终统计；服务重启后的统计只代表新进程。`resources.jsonl` 每 30 秒记录 UTC 时间、可用/提交内存、磁盘空间和编译进程 PID/CPU/内存，`windows-events.json` 保存本次任务的资源耗尽及相关崩溃事件。采样由 `scripts/ci-cache-diagnostics.ps1` 在 CI 启停，启动时校验实际采样字段，结束时检查相邻记录间隔不超过 90 秒；诊断失败不替代构建、测试结果。
- 协议稳定版和实验版共用一次编译的生成器，生成完成后重新编译并校验内嵌协议。保留 migration 换行检查和上游 release/LTO 参数。
- `build`、`test` 各自使用 `Swatinem/rust-cache` 的 job/Rust/依赖自动键，保存下载依赖和 target；失败时也保存缓存，不按 tag 或提交额外分桶。两套 target 不竞争同一个不可变缓存键；sccache 复用输入一致的编译结果。测试使用上游 `ci-test` profile，关闭调试信息以减小链接及缓存体积。
- 查看 `cargo-timings`、`tui-test-log` artifact、sccache 命中统计及 job 步骤耗时；缓存不能消除测试可执行文件的链接开销。测试首次冷启动需预热；并行后的发布等待时间取 build/test 较慢者，还受 Runner 排队影响。

优化前基线为运行 `42524866183`：总计 99 分 42 秒，release 编译 80 分 10 秒，协议生成校验 9 分 08 秒，缓存恢复 2 分 51 秒。运行 `42600912285` 的 build/test/release 全部成功：总计 105 分 08 秒，release 编译步骤 94 分 07 秒；并行 test job 为 13 分 37 秒，92 项通过，sccache 命中率 79.71%。本次 build 中途发生 sccache 响应断连并成功回退直接编译，尚不能证明构建提速；服务断连根因待诊断附件进一步定位。

## 构建失败后

在本仓库目录执行，将 `RUN_ID` 替换为目标运行编号：

```powershell
gh run list --workflow build-windows.yml --limit 5
gh run view RUN_ID --log-failed
```

按失败步骤处理：`prepare` 查 `patch-conflicts` artifact 中的具体功能补丁名、应用日志和冲突内容；`build` 区分依赖获取、编译和协议生成失败；`test` 查看本地链接过滤器及 sccache 日志；`release` 查发布及 tag 记录，已构建产物可从 `codex-windows-x64` artifact 获取。

临时环境故障可用 `gh run rerun RUN_ID --failed` 重跑原提交。修复推送后启动新运行，才能使用新提交：

```powershell
gh workflow run build-windows.yml --ref main -f tag=rust-v0.167.0 -f force=true
```

`tag` 留空使用最新正式版；`force=true` 忽略已构建记录。`built-tags.txt` 由发布成功的 CI 维护；补丁应用失败可能仍使整体运行显示绿色，应检查实际 jobs 与附件。

## 维护与迁移

CI 优先使用 `patches/series/<基线tag>/*.patch`，按编号执行 `git am --3way`。新官方 tag 没有专属补丁时自动尝试最新 series；跨版本时只获取基线 tag，并先重建基线功能链，供后续修订进行三方合并。冲突时停止，报告失败功能，保留此前成功提交；旧版只有合并补丁时使用 `git apply` / `git apply --3way`。不再使用忽略上下文的 fuzz 应用。

本地复现 CI 的入口（报告目录使用临时目录）：

```bash
bash scripts/apply-patches.sh /path/to/upstream patches/rust-v0.167.0.patch rust-v0.167.0 /tmp/codex-patch-report
```

源码提交与维护仓库提交分开保存。本地 `patches/rust-v0.167.0` 分支已保留官方基线及 15 个功能提交，直接查看：

```bash
git log --oneline 086ccc833bc9cf01024ad2dd6af7dbd421b6bf9a..patches/rust-v0.167.0
git show patches/rust-v0.167.0
```

该源码分支以官方 tag 为浅历史边界，`main` 仍保存补丁和 CI 文件。邮件补丁是跨机器恢复功能历史的持久来源；CI 的 `patched-source` artifact 也包含完整功能链的 `.git`，保留 7 天。

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

修复已有功能时追加新的功能提交及编号补丁，不覆盖旧提交。源码分支更新后可将其导入维护仓库的本地历史视图（不切换 `main`，不导入同名 Release tag）：

```bash
git fetch --no-tags --update-shallow /path/to/upstream patched/rust-v0.167.0:refs/heads/patches/rust-v0.167.0
```

补丁流程的隔离回归：`python scripts/tests/test_apply_patches.py`，覆盖原始基线、跨版本上下文漂移、后续功能依赖、冲突定位、基线重建失败、旧版合并补丁及源码历史打包。测试不访问远端。

Cargo.lock 版本由 CI 对齐。协议 JSON、TypeScript 和压缩导出通过 workflow 的“重建并校验协议导出”步骤生成，留在构建工作区；功能提交保存源码，导出时使用 `HEAD` 排除未提交的生成物。
