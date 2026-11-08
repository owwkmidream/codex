# Windows 补丁管理

在独立的普通用户终端运行，先退出正在使用目标文件的 Codex CLI。需要 Windows x64、x64 Node.js/npm，以及 GitHub/npm 网络访问。脚本针对当前 `npm root -g` 对应的安装，支持 Windows PowerShell 5.1 和 PowerShell 7。

双击 `codex-patch.bat` 打开菜单；也可在 PowerShell 中执行：

```powershell
.\scripts\codex-patch.ps1 -Action Install
```

| 操作 | 命令参数 | 结果 |
|---|---|---|
| 安装或更新补丁 | `-Action Install` | 下载本仓库最新已发布正式 Release，下载 npm 同版本完整包，替换 CLI 并同步 daemon。 |
| 指定补丁版本 | `-Action Install -Version 0.167.0` | 使用指定版本，尚未发布则在替换前报错。 |
| 卸载补丁、恢复官方最新版 | `-Action Official` 或 `-Action Uninstall` | 从 npm 下载完整官方最新版，同时替换 CLI 和 daemon；保留 Codex、配置和会话数据。 |
| 查看本地备份 | `-Action Backups` | 列出备份编号、CLI 版本及原 daemon 运行状态。 |
| 恢复备份 | `-Action Restore -BackupId 备份编号` | 分别恢复 CLI 和 daemon 的原完整包；省略编号则使用最近一个含 CLI 的备份。 |
| 查看状态 | `-Action Status` | 显示版本、路径、来源、磁盘文件一致性、daemon 状态及自动更新开关。 |
| 核验手动安装的补丁 | `-Action Status -VerifyRelease` | 下载各自版本的 Release，按实际文件内容核验。 |
| 只同步 daemon | `-Action Sync` | 将当前 CLI 完整包复制并固定给 daemon。 |

上述参数同样可传给 `.bat`。自动化执行时追加 `-Yes` 跳过确认，例如：

```powershell
.\scripts\codex-patch.bat -Action Install -Yes
```

## 安装、备份与更新行为

“最新补丁”取 GitHub 已发布的 Release，可能落后于 npm，也可能低于当前 CLI 版本；执行前会展示目标版本。脚本先下载、解包并核对版本，再开始修改现有安装。GitHub 提供下载摘要时同时验证 SHA256。

npm 官方包在空的临时前缀下载，随后将完整包和 npm 生成的启动入口复制到当前 npm 前缀。这样恢复同版本官方包时也会覆盖已修改的文件，并保持辅助程序匹配。

每次修改前备份完整 CLI 包、npm 启动入口和 daemon 包。默认保存在 `$CODEX_HOME/patch-manager/backups`；未设置 `CODEX_HOME` 时使用用户目录的 `.codex`。可用 `-StateDirectory` 改变管理数据目录。备份保留原样，可手动清理不再需要的备份；本次下载目录执行结束后自动清理。

同步统一调用 `daemon update --from-cli --yes`，关闭 `updater.autoUpdateEnabled` 并固定本地包。**恢复官方版或备份后，自动更新也保持关闭**。daemon 原来运行则恢复运行，原来停止则保持停止；首次建立包时可能短暂启动后停止。需要恢复官方生产更新通道时，按 [CODEX-BUILD.md](../CODEX-BUILD.md) 的 daemon 更新说明处理。

发生错误时尝试从操作前备份回滚；错误会返回非零退出码。若回滚未完成，使用错误中给出的备份编号执行 `Restore`。首次安装之前没有旧 CLI 时，备份不包含可恢复的软件包，可用 `Official` 重新安装官方版。切换 Node/npm 环境后，需要切回备份所属的 npm root 才能恢复。

## 状态的含义

“已确认补丁版”表示与从本仓库 Release 下载并登记的二进制内容一致；“已登记 npm 官方版”表示与本脚本下载的 npm 二进制一致。已有文件未登记时显示“未知”，可用 `-VerifyRelease` 核验；仅凭相同版本号无法识别补丁。

“磁盘文件一致”比较 CLI 和 daemon 文件内容。运行中的 daemon 是否已加载新文件，还需结合运行版本及最近同步/重启结果；同版本手动替换文件后应重新同步。

## 脚本格式

- `.bat`、`.cmd`：由 Windows `cmd.exe` 执行的批处理。这里的 `.bat` 只负责启动 PowerShell 菜单。
- `.ps1`：PowerShell 脚本，适合处理 JSON、网络下载、文件和进程。本实现的逻辑位于此文件。
- `.sh`：通常由 `sh`/Bash 执行。PowerShell 可以调用已安装的 Git Bash，例如 `bash ./script.sh`，或 WSL，例如 `wsl bash ./script.sh`；脚本仍由 Bash 解释，路径和可用命令取决于该环境。

`.bat` 优先调用 PowerShell 7，未安装时使用 Windows PowerShell 5.1；其 `ExecutionPolicy Bypass` 仅用于本次启动，不修改系统执行策略。

## 开发验证

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/tests/codex-patch.Tests.ps1
pwsh.exe -NoProfile -File scripts/tests/codex-patch.Tests.ps1
```

测试使用临时 npm/daemon/HTTP 替身，覆盖完整包备份、独立恢复、同版本官方恢复、失败回滚、下载摘要和路径边界；不会安装或重启本机 Codex。
