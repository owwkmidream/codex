# 仓库维护约定

本仓库维护官方 Codex tag 对应的 Windows 构建补丁。上游源码放在独立临时 checkout/worktree，仓库保存可重放的补丁及维护文档。

## 按任务读取

- 修改补丁、配置、安装或守护进程更新说明时，先读 [CODEX-BUILD.md](CODEX-BUILD.md) 的对应章节；这里是当前功能约定的来源。
- 接手 0.167.0 验证或失败排查时，读 [VALIDATION.md](patches/series/rust-v0.167.0/VALIDATION.md)，再用 `gh run view` 取得最新状态和失败日志。
- 修改 CI 或判断是否已发布时，核对 [.github/workflows/build-windows.yml](.github/workflows/build-windows.yml)、实际 jobs、Release 附件及 `built-tags.txt`。workflow 是执行入口，构建记录由成功发布的 CI 维护。

## 维护补丁

1. 固定目标官方 tag，在干净上游 worktree 中重放相应 series；修改上游源码前读取其适用的 `AGENTS.md`。
2. 按功能保留小提交，修复同一功能时保留其历史和迁移关系；行为以 `CODEX-BUILD.md` 为验收依据。
3. 同步导出 `patches/<tag>.patch` 与 `patches/series/<tag>/*.patch`，在干净基线上验证两种产物重放后的源码一致。导出命令见构建文档。
4. 历史版本补丁保持原样，新版本写入对应 tag 文件。Cargo.lock 由 CI 对齐；协议 JSON、TypeScript、压缩导出通过上游生成器重建，功能提交只保存相关源码。
5. 测试断言、快照、配置/schema、跨层事件及公开导出随行为一起维护；新增字段要检查所有构造方、转换与消费方。

## 验证与交付

- 修改源码后运行受影响的有价值测试和格式检查；环境阻断时记录命令、失败阶段和未覆盖行为。补丁应用通过、独立逻辑测试通过和完整构建通过分别报告。
- 判断构建成功时确认 `build` 实际执行并成功；判断发布成功时另外确认 `release` 及附件。`prepare` 允许失败后反馈 Issue，整条运行绿色可能没有产物。
- 新提交需要新的 workflow dispatch；重跑旧 run 仍使用原提交。构建文档给出了两种入口。
- `CODEX-BUILD.md` 的功能、部署步骤及 CI 说明随本次改动更新；临时进度和会话交接写入系统临时目录，通过路径交接。
- 本机二进制替换由用户手动完成。修改全局 npm 包、daemon 设置或重启运行中的会话前，取得对应部署授权。
