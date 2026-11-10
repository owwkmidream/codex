# 仓库维护约定

本仓库保存官方 Codex tag 对应的 Windows 补丁；上游源码在独立临时 checkout/worktree 中维护。

## 按任务读取

- 修改功能、配置或补丁：读 [CODEX-BUILD.md](CODEX-BUILD.md) 的“功能约定”和“维护补丁”。
- 验证或排查失败：读目标 series 的 `VALIDATION.md`（当前为 [0.167.0](patches/series/rust-v0.167.0/VALIDATION.md)），再查实际 CI jobs 和日志。
- 修改 CI 或发布说明：读 [.github/workflows/build-windows.yml](.github/workflows/build-windows.yml)；核对目标提交、Release 附件与 `built-tags.txt`。
- 修改安装、恢复、状态脚本或部署说明：读 [scripts/README.md](scripts/README.md)，使用其中的隔离 fixture 验证。

## 实现与验收

1. 固定官方 tag，在干净上游 worktree 重放对应 series；编辑前读取上游适用的 `AGENTS.md`。
2. 按功能追加小提交及编号补丁，保留已有提交与历史版本。行为变更同步测试、快照、配置/schema、构造方、跨层事件和公开导出。
3. 同步导出合并补丁与 series，在干净基线上重放，确认两者源码一致。Cargo.lock 由 CI 对齐；协议 JSON、TypeScript 和压缩导出由上游生成器重建。
4. **Codex 二进制**：本机资源不足，其 Cargo 构建、测试、独立编译测试及相关重型依赖准备统一在 CI 执行；CI 失败也不回退到本地重任务，除非用户明确指定本地范围。**仓库脚本**：语法检查和隔离 fixture 测试已获授权，可直接在本机运行，默认超时 60 秒；覆盖 Bash、PowerShell 和补丁维护脚本，测试不得修改真实 Codex 安装或运行中的 daemon。
5. Codex 源码修改须在 CI 检查格式和受影响行为。CI 阻断时记录失败命令、阶段和未覆盖行为，保持“实现已提交，集成验证未完成”状态。脚本修改优先本地隔离验证，CI 可补充平台回归。
6. 构建成功须有实际成功的 `build` job；发布成功还须有成功的 `test`、`release` 及附件。绿色 run 可能跳过构建。新提交启动新 dispatch，旧 run 重跑仍用旧提交。
7. 本机部署另需用户授权，包括全局 npm 包替换、daemon 设置修改和会话重启。

## 文档归属

- `CODEX-BUILD.md`：当前功能与维护操作；随行为更新。
- `VALIDATION.md`：按提交归属的验证证据、未验收行为；历史细节通过 Git 和 CI 链接追溯。
- Release：附件内容、安装入口、对应构建提交的文档链接；只描述已发布产物。
- 临时进度、日志分析和交接：系统临时目录，通过路径交接。
