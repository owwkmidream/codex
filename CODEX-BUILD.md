# codex-patched-build

把官方 tag 对应的补丁应用到 Codex 源码，构建 Windows x64 `codex.exe`，由 Actions 发布 Release。本仓库保存补丁，不常驻保存上游源码。

## 安装与手动更新

1. 先安装对应版本 npm 包，例如 `npm install -g @openai/codex@0.167.0`。
2. 从 [Releases](../../releases) 下载同版本的补丁构建，备份原文件后覆盖 npm 包中的 `codex.exe`：

```text
<nodejs>\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\
  vendor\x86_64-pc-windows-msvc\bin\codex.exe
```

本机曾使用的目录：

```text
D:\Workspace\nvm\nodejs\node_modules\@openai\codex\node_modules\
  @openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\bin\codex.exe
```

3. 运行 `codex --version`，核对 zip 中 `BUILD-INFO.txt` 的 `upstream_tag`。
4. 使用独立守护进程时，将当前 CLI 的完整包同步过去：

```powershell
codex app-server daemon update --from-cli
codex app-server daemon version
codex app-server daemon status
```

`update --from-cli` 是 0.167.0 上游提供的手动入口，会先显示安装确认，复制当前 CLI 的完整包并固定该选择；已有守护进程运行时会重启它。请在会话空闲时执行。不要加普通 `update` 来更新补丁版：不带 `--from-cli` 会恢复官方生产更新通道。

CLI 与守护进程通常使用不同的磁盘副本。只覆盖 npm 目录不会更新已有守护进程包；后者位于 `$CODEX_HOME/packages/app-server-daemon`，旧安装也可能使用其他受管目录。以命令输出的 `managed_codex_path` 为准。

关闭自动更新的设置在 `$CODEX_HOME/app-server-daemon/settings.json` 的 `updater.autoUpdateEnabled`，与模型的 `config.toml` 分开。保留现有 JSON 的其他设置，只调整该字段。手动维护顺序为：升级 npm → 覆盖同版本补丁二进制 → `update --from-cli` → 核对运行版本。

以上步骤是部署说明；维护补丁不会自动替换本机二进制或修改运行设置。

### CLI 与辅助程序必须同版本

替换的 `codex.exe` 会使用 npm 包中的辅助程序，本仓库不构建这些文件：

```text
codex-resources\codex-command-runner.exe
codex-resources\codex-windows-sandbox-setup.exe
codex-path\rg.exe
```

跨版本更新时先升级完整 npm 包，再覆盖补丁文件；回滚时恢复同版本完整包及其补丁，随后重新执行 `update --from-cli`。

## 0.167.0 补丁的行为

| 功能 | 实现与边界 |
|---|---|
| 请求活动计数 | 按轮次清零，同轮多个请求累计请求体/响应体字节；SSE 与 WebSocket 均接入。计数表示收发活动，不含 TLS/HTTP 头等开销。 |
| 本次新增 token | 流式接口无法持续提供准确值，保留字节计数。完成事件的 usage 包含整次请求上下文，不能直接当作实时新增输入 token。 |
| 压缩横幅 | 显示本地/远程压缩，复用上游 `ProviderCapabilities::from_config`，包含 capability 覆盖与 TokenBudget 条件。 |
| 重试次数 | `request_max_retries`、`stream_max_retries` 的允许上限从 100 解锁到 1000；默认次数保持上游值。 |
| 重试等待 | provider 下新增有符号 `retry_delay_ms`，适用于模型 HTTP、流重连和本地压缩重试；传输回退也遵循该等待规则。 |
| 可重试错误 | ServerOverloaded、PolicyCapacityUnavailable、RetryLimit 在没有服务端建议时仍可重试。 |
| Cyber 提示 | 保留警告展示，UI 不因该提示主动结束 turn；Bio 的原有处理保留。 |
| resume | 仅在选择器入口请求所有 provider，保留目录过滤、上游枚举及其他调用方的过滤能力。0.167.0 中必须使用 All，Any 仍可能触发服务端默认 provider 过滤。 |
| 无输出 Esc | 固定中断时的 turn ID，复用已有回滚与草稿恢复；已出现答案、推理、计划或工具调用时保留原中断行为。 |
| SQLite 日志 | 保留 INFO 及以上级别；此项控制 SQLite 日志过滤。 |
| Space 引用 | 有选区时在当前 prompt 尾部追加 `\n> 选中文字\n`，保留草稿附件、提及、粘贴内容，清除选区并保持阅读位置；无选区时沿用原 Space 行为。 |
| 模型上下文 | 已移除 353000 覆盖，使用上游模型目录。 |

Ctrl+C 保持复制功能；Enter 保持“复制并跟随最新输出”。Space 不操作剪贴板，也不跟随最新输出。多行选中文字按原文追加，仅在整体前面加一个 `> `。

### 配置重试

在现有 provider 表中加入字段，不要重复创建同名表：

```toml
[model_providers.openai]
request_max_retries = 1000
stream_max_retries = 1000
retry_delay_ms = 10000
```

| 值 | 有服务端重试建议 | 没有建议 |
|---|---|---|
| 未配置或 `10000` | 遵从建议 | 等待 10 秒 |
| `2000` | 遵从建议 | 等待 2 秒 |
| `-10000` | 忽略建议，等待 10 秒 | 等待 10 秒 |
| `0` | 遵从建议 | 立即重试 |

重试等待不改变重试资格、预算与取消语义。未显式配置的非模型 HTTP 客户端保留上游退避行为。

## 按功能维护历史

历史的 `patches/rust-v0.156.1.patch` 至 `rust-v0.166.0.patch` 保留原样。0.167.0 提供两种等价交付：

- `patches/rust-v0.167.0.patch`：Actions 继续使用的合并补丁。
- `patches/series/rust-v0.167.0/*.patch`：按功能拆分的 Git 邮件补丁，保存提交顺序、说明与真实基线，供后续迁移。

在干净上游仓库中恢复这些提交：

```bash
git clone --branch rust-v0.167.0 https://github.com/openai/codex.git
cd codex
git switch -c patched/rust-v0.167.0
git am /path/to/codex-patched-build/patches/series/rust-v0.167.0/*.patch
```

补丁只保存协议源码，不保存上游生成的 JSON、TypeScript 和压缩导出。应用后，先执行 workflow 的“重建并校验协议导出”步骤，再运行其他测试和构建。该步骤调用上游 `schema_fixtures_tests::write_schema_fixtures_from_env`，分别设置 `CODEX_APP_SERVER_SCHEMA_EXPERIMENTAL=0/1`，生成稳定版和实验版导出，再运行上游一致性测试。

后续升级时保留该分支，再迁移到新 tag；只处理确实发生变化的功能：

```bash
git fetch origin tag <新tag>
git switch -c patched/<新tag>
git rebase --onto <新tag> rust-v0.167.0
# 逐个处理冲突，运行受影响的测试，再导出新版本。
git diff --binary --full-index <新tag> HEAD -- . ':!codex-rs/Cargo.lock' > /path/to/patches/<新tag>.patch
git format-patch --binary --full-index --no-signature -o /path/to/patches/series/<新tag> <新tag>..HEAD
```

新功能放在独立提交中，修订既有功能时整理到对应提交；不要再对整份补丁做跨版本字符串替换。上游已实现同等能力时，可以删除相应功能提交，但应先核对行为和配置兼容。

生成的 `codex-rs/app-server-protocol/schema/` 留在构建工作区，不纳入功能提交。导出命令中的 `HEAD` 用于排除这些未提交的生成物，避免每次升级都迁移压缩二进制差异。

## Actions 构建流程

每天 06:00 UTC 检查官方正式 Release；`built-tags.txt` 控制是否跳过已构建版本。

1. 优先选 `patches/<tag>.patch`；尚无专属补丁时尝试版本号最大的已有补丁。
2. 依次尝试 `git apply`、`patch -p1 --fuzz=3`、`git apply --3way`。fuzz 先 dry-run，全部 hunk 成功才应用。
3. 无法自动匹配时创建冲突 Issue。上下文变化、缺失 pre-image 与语义冲突都需按具体输出区分；应用成功还需编译与行为检查。
4. 对齐 Cargo.lock 的 workspace 版本，重建并校验稳定版/实验版协议导出，再 `cargo build --locked --release --bin codex`。
5. 打包并发布 Windows x64 zip，记录已构建 tag。

补丁不包含 Cargo.lock。官方 tag 的 lock 中 workspace 包版本为 0.0.0，而 Cargo.toml 已使用发布版本。workflow 校验 0.0.0 行数与 `version.workspace = true` 包数相等后，才按目标版本替换。

Actions → `build-windows-codex` → Run workflow：

- `tag`：目标官方 tag，留空使用最新正式版。
- `force`：忽略已构建记录，强制重建；已记录 tag 不加 force 会跳过。

CLI 构建不使用 V8 运行时，但 Cargo 解析 workspace 依赖时仍可能获取 V8 Git 源码。本次本机验证遇到其子模块的 Windows 长路径错误，记录见 [验证记录](patches/series/rust-v0.167.0/VALIDATION.md)。发布前应在可构建环境补齐 Rust 测试、协议导出一致性检查和 Windows TUI 验证。
