# Windows 二进制补丁管理

在普通用户的 Windows x64 Git Bash 中执行。需要已安装 x64 Node.js/npm 和 Codex，以及 Git Bash 的 curl、sha256sum、cygpath 和系统 tar.exe、PowerShell。交付入口只有 `codex-patch.sh`，不依赖旁边的 PowerShell 脚本。

```bash
bash scripts/codex-patch.sh                 # 交互菜单
bash scripts/codex-patch.sh install --yes   # 安装当前 npm 包版本对应的补丁
bash scripts/codex-patch.sh restore --yes   # 还原同版本官方二进制
bash scripts/codex-patch.sh status          # 查看 CLI/daemon 来源与状态
bash scripts/codex-patch.sh sync --yes      # 将当前 CLI 同步给 daemon
```

省略 `--yes` 时，修改操作先请求确认。操作前关闭使用目标文件的其他 CLI 会话。脚本显示当前步骤、查询命令和下载进度，查询超时 120 秒、下载超时 600 秒。

## 四项操作

- **install**：按已安装 npm 包版本下载对应 Release；缺少补丁或摘要则提示退出。校验 SHA-256 和版本后只替换 exe，自动执行 `daemon update --from-cli --yes`；不下载官方包。
- **restore**：通过 npm HTTP 元数据下载同版本 Windows 平台包，校验包的 SHA-512 integrity，提取并替换官方 exe。随后执行 `daemon update` 恢复官方更新通道；daemon 的官方通道版本可能与 CLI 不同。
- **status**：只下载对应版本的 `binary-hashes.json`，计算已有本地文件的 hash，识别官方版、补丁版或未知；不会为了识别而下载二进制。
- **sync**：独立执行 from-cli 同步；安装流程也包含此操作。

安装和同步通过 from-cli 固定 daemon 包；恢复官方更新使用上游命令，不直接编辑自动更新设置。各操作保留 daemon 原运行/停止状态；首次创建管理包时可能短暂启动。

## 文件与失败处理

脚本只管理当前 npm 环境的既有安装，版本升级通过 npm 完成。保留启动入口、辅助程序、配置及会话；不创建备份，不支持指定版本或备份恢复。历史 `.ps1`/`.bat` 保留兼容，其备份式流程与本脚本不同。

下载、摘要及版本校验完成后，先在目标目录准备文件，再替换 exe。下载或校验失败不修改安装；替换后同步失败会返回错误并指出阶段，此时重新运行 sync，或用 restore 恢复官方版。不自动回滚二进制。

## Release 摘要

CI 校验 npm 平台包 integrity 后计算官方 exe SHA-256，并与构建出的补丁 exe SHA-256 一起发布为独立 `binary-hashes.json` 附件，含 version、target、official_sha256、patched_sha256。历史 Release 尚无摘要时状态显示未知，安装提示缺少摘要；还原不依赖 Release。

## 开发验证

在 Windows CI 的 Git Bash 执行隔离回归：

```bash
bash -n scripts/codex-patch.sh
bash scripts/tests/codex-patch-shell.Tests.sh
```

fixture 覆盖查询反馈、空格路径、失败退出、摘要分类、错误版本拒绝，以及真实 main 的安装/还原文件替换、daemon 运行状态保持和状态查询流量；网络和 daemon 使用替身，不修改真实安装。真实环境仍需用户部署验收。
