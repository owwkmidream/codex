#requires -Version 5.1
<#
.SYNOPSIS
安装、检查及还原 Windows x64 Codex CLI / daemon 补丁。
.EXAMPLE
.\codex-patch.ps1 -Action Install -Yes
.EXAMPLE
.\codex-patch.ps1 -Action Status -VerifyRelease
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Install', 'Restore', 'Official', 'Uninstall', 'Status', 'Backups', 'Sync')]
    [string]$Action = 'Menu',
    [string]$Version,
    [string]$BackupId,
    [string]$StateDirectory,
    [switch]$VerifyRelease,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$script:Repository = 'owwkmidream/codex'
$script:PlatformPackage = '@openai/codex-win32-x64'
$script:TargetTriple = 'x86_64-pc-windows-msvc'

function Invoke-Tool {
    param([string]$File, [string[]]$Arguments)
    # 原生命令的非零退出码不会自动触发 PowerShell 的 Stop。
    $output = @(& $File @Arguments)
    if ($LASTEXITCODE -ne 0) { throw "$File 执行失败（退出码 $LASTEXITCODE）。" }
    return ($output -join "`n").Trim()
}

function Read-Json {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-Json {
    param([string]$Path, $Value)
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
    $temporary = "$Path.tmp"
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 40), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-Field {
    param($Value, [string]$Name, $Default = $null)
    if ($null -ne $Value -and $null -ne $Value.PSObject.Properties[$Name]) { return $Value.$Name }
    return $Default
}

function Set-Field {
    param($Value, [string]$Name, $Content)
    $Value | Add-Member -MemberType NoteProperty -Name $Name -Value $Content -Force
}

function Get-BinaryHash {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $null
}

function Get-CliLayout {
    param([string]$Root = $script:NpmRoot)
    $wrapper = Join-Path $Root '@openai/codex'
    $manifest = Join-Path $wrapper 'package.json'
    if (-not (Test-Path -LiteralPath $manifest)) { return $null }
    $package = Read-Json $manifest
    if ($package.name -ne '@openai/codex') { throw 'npm 目录中的包名称不符合预期。' }
    $platform = Join-Path $wrapper 'node_modules/@openai/codex-win32-x64'
    if (-not (Test-Path -LiteralPath (Join-Path $platform 'package.json'))) {
        $platform = Join-Path $Root $script:PlatformPackage
    }
    $binary = Join-Path $platform "vendor/$script:TargetTriple/bin/codex.exe"
    if (-not (Test-Path -LiteralPath $binary)) {
        # 兼容把 vendor 直接放在主包中的发行布局。
        $platform = $wrapper
        $binary = Join-Path $wrapper "vendor/$script:TargetTriple/bin/codex.exe"
    }
    if (-not (Test-Path -LiteralPath $binary)) { throw 'Codex npm 包不完整，找不到 Windows x64 codex.exe。' }
    [pscustomobject]@{ Wrapper = $wrapper; Platform = $platform; Binary = $binary; Version = $package.version }
}

function Get-DaemonInfo {
    param([string]$Binary)
    # version 是只读入口；输出字段由上游 serde camelCase 定义。
    $json = Invoke-Tool $Binary @('app-server', 'daemon', 'version')
    $info = $json | ConvertFrom-Json
    if (-not (Get-Field $info 'managedCodexPath')) { throw 'daemon version 没有返回 managedCodexPath。' }
    return $info
}

function Get-PackageDirectory {
    param([string]$Binary)
    $directory = Split-Path -Parent $Binary
    while ($directory) {
        if (Test-Path -LiteralPath (Join-Path $directory 'codex-package.json')) { return $directory }
        $parent = Split-Path -Parent $directory
        if ($parent -eq $directory) { break }
        $directory = $parent
    }
    throw 'daemon 缺少完整包清单，无法建立可还原备份。'
}

function Get-AutoUpdatePreference {
    if (-not (Test-Path -LiteralPath $script:SettingsFile)) { return $true }
    $settings = Read-Json $script:SettingsFile
    return [bool](Get-Field (Get-Field $settings 'updater') 'autoUpdateEnabled' $true)
}

function Set-AutoUpdatePreference {
    param([bool]$Enabled)
    $settings = if (Test-Path -LiteralPath $script:SettingsFile) { Read-Json $script:SettingsFile } else { [pscustomobject]@{} }
    $updater = Get-Field $settings 'updater'
    if ($null -eq $updater) { $updater = [pscustomobject]@{}; Set-Field $settings 'updater' $updater }
    Set-Field $updater 'autoUpdateEnabled' $Enabled
    Write-Json $script:SettingsFile $settings
}

function Get-KnownBinaries {
    $path = Join-Path $script:StateRoot 'known-binaries.json'
    if (Test-Path -LiteralPath $path) { return @(Read-Json $path) }
    return @()
}

function Register-Binary {
    param([string]$Binary, [string]$Kind, [string]$BinaryVersion, [string]$Source)
    $hash = Get-BinaryHash $Binary
    $entries = @(Get-KnownBinaries | Where-Object { $_.sha256 -ne $hash })
    $entries += [pscustomobject]@{ sha256 = $hash; kind = $Kind; version = $BinaryVersion; source = $Source }
    Write-Json (Join-Path $script:StateRoot 'known-binaries.json') $entries
}

function Get-BinaryKind {
    param([string]$Hash)
    if (-not $Hash) { return '未安装' }
    $known = @(Get-KnownBinaries | Where-Object { $_.sha256 -eq $Hash })
    if ($known.Count -eq 0) { return '未知（可用 Status -VerifyRelease 核对）' }
    if ($known[0].kind -eq 'patched') { return "已确认补丁版 $($known[0].version)" }
    return "已登记 npm 官方版 $($known[0].version)"
}

function Get-ReleasePackage {
    param([string]$RequestedVersion)
    if ($RequestedVersion -and $RequestedVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Version 应为正式版本号，例如 0.167.0。' }
    $suffix = if ($RequestedVersion) { "tags/rust-v$RequestedVersion" } else { 'latest' }
    $headers = @{ 'User-Agent' = 'codex-patch-manager'; Accept = 'application/vnd.github+json' }
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$script:Repository/releases/$suffix" -Headers $headers
    if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^rust-v(\d+\.\d+\.\d+)$') {
        throw 'Release 不是受支持的正式 Codex 版本。'
    }
    $releaseVersion = $Matches[1]
    if ($RequestedVersion -and $releaseVersion -ne $RequestedVersion) { throw 'GitHub 返回的 tag 与请求版本不一致。' }
    $assetName = "codex-$($release.tag_name)-windows-x64.zip"
    $assets = @($release.assets | Where-Object { $_.name -eq $assetName })
    if ($assets.Count -ne 1) { throw "Release 缺少唯一的 $assetName。" }
    $asset = $assets[0]
    $expectedUrl = "https://github.com/$script:Repository/releases/download/$($release.tag_name)/$assetName"
    if ($asset.browser_download_url -ne $expectedUrl) { throw 'Release 下载地址不符合预期。' }
    $directory = Join-Path $script:WorkRoot ([guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $directory
    $archive = Join-Path $directory $assetName
    Write-Host "下载补丁 $releaseVersion ..."
    Invoke-WebRequest -UseBasicParsing -Uri $expectedUrl -OutFile $archive
    $digest = Get-Field $asset 'digest'
    if ($digest -and $digest -match '^sha256:(.+)$' -and (Get-BinaryHash $archive) -ne $Matches[1].ToLowerInvariant()) {
        throw 'Release 下载文件的 SHA256 与 GitHub 提供的摘要不一致。'
    }
    $unpacked = Join-Path $directory 'package'
    Expand-Archive -LiteralPath $archive -DestinationPath $unpacked
    $binary = Join-Path $unpacked 'codex.exe'
    $buildInfo = Join-Path $unpacked 'BUILD-INFO.txt'
    if (-not (Test-Path -LiteralPath $binary) -or -not (Test-Path -LiteralPath $buildInfo)) { throw 'zip 缺少 codex.exe 或 BUILD-INFO.txt。' }
    $fields = @{}
    foreach ($line in [IO.File]::ReadAllLines($buildInfo)) {
        if ($line -match '^([^:]+):\s*(.*)$') { $fields[$Matches[1]] = $Matches[2] }
    }
    if ($fields['upstream_tag'] -ne $release.tag_name) { throw 'zip 中的 upstream_tag 与 Release 不一致。' }
    if ($fields.ContainsKey('patch_is_exact') -and $fields['patch_is_exact'] -ne 'true') { throw '该 Release 使用回退补丁，请等待目标版本的专属补丁构建。' }
    $actual = Invoke-Tool $binary @('--version')
    if ($actual -notmatch "^codex-cli $([regex]::Escape($releaseVersion))(\s|$)") { throw '下载二进制的版本与 Release 不一致。' }
    $help = Invoke-Tool $binary @('app-server', 'daemon', 'update', '--help')
    if ($help -notmatch '--from-cli') { throw '该版本不支持完整包同步；尚未修改安装。' }
    Register-Binary $binary 'patched' $releaseVersion $expectedUrl
    [pscustomobject]@{ Version = $releaseVersion; Binary = $binary; Source = $expectedUrl; Sha256 = Get-BinaryHash $binary }
}

function Get-OfficialPackage {
    param([string]$PackageVersion)
    # 每次在空前缀安装，避免 npm 把已被替换的同版本文件误认为无需更新。
    $prefix = Join-Path $script:WorkRoot ([guid]::NewGuid().ToString('N'))
    Write-Host "从 npm 准备完整官方包 $PackageVersion ..."
    $null = Invoke-Tool $script:Npm @('install', '--global', '--prefix', $prefix, "@openai/codex@$PackageVersion")
    $layout = Get-CliLayout (Join-Path $prefix 'node_modules')
    if (-not $layout -or $layout.Version -ne $PackageVersion) { throw 'npm 下载的完整包版本不符合预期。' }
    $actual = Invoke-Tool $layout.Binary @('--version')
    if ($actual -notmatch "^codex-cli $([regex]::Escape($PackageVersion))(\s|$)") { throw 'npm 包中二进制版本不匹配。' }
    $help = Invoke-Tool $layout.Binary @('app-server', 'daemon', 'update', '--help')
    if ($help -notmatch '--from-cli') { throw '该 npm 版本不支持 daemon 包同步，尚未修改安装。' }
    Register-Binary $layout.Binary 'official' $PackageVersion 'npm'
    [pscustomobject]@{ Prefix = $prefix; Layout = $layout }
}

function Publish-NpmPackage {
    param($Package)
    Restore-PackageDirectory $Package.Layout.Wrapper (Join-Path $script:NpmRoot '@openai/codex')
    if ($Package.Layout.Platform -ne $Package.Layout.Wrapper -and
        -not $Package.Layout.Platform.StartsWith($Package.Layout.Wrapper + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        Restore-PackageDirectory $Package.Layout.Platform (Join-Path $script:NpmRoot $script:PlatformPackage)
    }
    foreach ($name in @('codex', 'codex.cmd', 'codex.ps1')) {
        $source = Join-Path $Package.Prefix $name
        if (-not (Test-Path -LiteralPath $source)) { throw "npm 没有生成 $name 启动入口。" }
        Copy-Item -LiteralPath $source -Destination (Join-Path $script:NpmPrefix $name) -Force
    }
}

function Confirm-Change {
    param([string]$Description)
    Write-Host $Description
    Write-Host '将备份并修改当前 npm 安装、同步 daemon、关闭自动更新；运行中的 daemon 会重启。请先退出其他 Codex CLI 会话。'
    if ($Yes) { return }
    if ((Read-Host '确认执行？输入 YES') -cne 'YES') { throw '操作已取消。' }
}

function Copy-Directory {
    param([string]$Source, [string]$Destination)
    $null = New-Item -ItemType Directory -Path $Destination -Force
    Get-ChildItem -LiteralPath $Source -Force | Copy-Item -Destination $Destination -Recurse -Force
}

function New-Backup {
    param($Layout, $Daemon)
    $id = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $directory = Join-Path $script:BackupRoot $id
    $null = New-Item -ItemType Directory -Path $directory
    $manifest = [pscustomobject]@{
        id = $id; createdAt = [DateTime]::UtcNow.ToString('o'); npmRoot = $script:NpmRoot
        cliVersion = $null; externalPlatform = $false; daemonBinary = $null
        daemonRunning = $false; autoUpdateEnabled = Get-AutoUpdatePreference
    }
    if ($Layout) {
        $manifest.cliVersion = $Layout.Version
        Copy-Directory $Layout.Wrapper (Join-Path $directory 'cli')
        $manifest.externalPlatform = $Layout.Platform -ne $Layout.Wrapper -and -not $Layout.Platform.StartsWith($Layout.Wrapper + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
        # npm 可能把平台依赖提升到全局 @openai 目录，需要单独保存。
        if ($manifest.externalPlatform) { Copy-Directory $Layout.Platform (Join-Path $directory 'platform') }
        $shimDirectory = Join-Path $directory 'shims'
        $null = New-Item -ItemType Directory -Path $shimDirectory
        foreach ($name in @('codex', 'codex.cmd', 'codex.ps1')) {
            $shim = Join-Path $script:NpmPrefix $name
            if (Test-Path -LiteralPath $shim) { Copy-Item -LiteralPath $shim -Destination $shimDirectory }
        }
    }
    if ($Daemon) {
        $manifest.daemonRunning = (Get-Field $Daemon 'status') -in @('running', 'alreadyRunning', 'started', 'restarted')
        $daemonBinary = Get-Field $Daemon 'managedCodexPath'
        if (Test-Path -LiteralPath $daemonBinary -PathType Leaf) {
            $packageDirectory = Get-PackageDirectory $daemonBinary
            Copy-Directory $packageDirectory (Join-Path $directory 'daemon')
            $manifest.daemonBinary = $daemonBinary.Substring($packageDirectory.Length).TrimStart('\', '/')
        }
    }
    # 清单最后写入；未完成的备份不会出现在可恢复列表中。
    Write-Json (Join-Path $directory 'backup.json') $manifest
    Write-Host "备份：$id"
    [pscustomobject]@{ Directory = $directory; Manifest = $manifest }
}

function Get-Backups {
    if (-not (Test-Path -LiteralPath $script:BackupRoot)) { return @() }
    @(Get-ChildItem -LiteralPath $script:BackupRoot -Directory | ForEach-Object {
        $manifest = Join-Path $_.FullName 'backup.json'
        if (Test-Path -LiteralPath $manifest) {
            $entry = Read-Json $manifest
            if ($_.Name -match '^\d{8}-\d{6}-[a-f0-9]{8}$' -and $entry.id -eq $_.Name) { $entry }
        }
    } | Sort-Object createdAt -Descending)
}

function Assert-ClosedCli {
    param($Layout, $Daemon)
    if (-not $Layout) { return }
    $daemonPid = Get-Field $Daemon 'pid' 0
    $active = @(Get-Process -Name codex -ErrorAction SilentlyContinue | Where-Object {
        $_.Id -ne $daemonPid -and $_.Path -and $_.Path.Equals($Layout.Binary, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($active.Count) { throw "当前 npm Codex 文件正在被进程 $($active.Id -join ', ') 使用。请从外部终端运行，先退出这些 CLI 会话。" }
}

function Stop-Daemon {
    param($Layout)
    if ($Layout) { $null = Invoke-Tool $Layout.Binary @('app-server', 'daemon', 'stop') }
}

function Sync-Daemon {
    param([string]$Binary, [bool]$WasRunning)
    Set-AutoUpdatePreference $false
    $info = Get-DaemonInfo $Binary
    try {
        if (-not (Test-Path -LiteralPath $info.managedCodexPath -PathType Leaf)) {
            # 首次安装先让上游建立管理目录，然后用显式同步固定本地包。
            $null = Invoke-Tool $Binary @('app-server', 'daemon', 'start')
        }
        $null = Invoke-Tool $Binary @('app-server', 'daemon', 'update', '--from-cli', '--yes')
        if ($WasRunning) { $null = Invoke-Tool $Binary @('app-server', 'daemon', 'start') }
    } finally {
        if (-not $WasRunning) { $null = Invoke-Tool $Binary @('app-server', 'daemon', 'stop') }
    }
}

function Restore-PackageDirectory {
    param([string]$Source, [string]$Destination)
    # 仅能替换本次 npm root 下两个明确的 Codex 包，避免递归删除计算错目标。
    $allowed = @((Join-Path $script:NpmRoot '@openai/codex'), (Join-Path $script:NpmRoot $script:PlatformPackage))
    $target = [IO.Path]::GetFullPath($Destination).TrimEnd('\', '/')
    if (-not ($allowed | Where-Object { [IO.Path]::GetFullPath($_).TrimEnd('\', '/') -eq $target })) { throw '拒绝替换 npm Codex 包目录以外的路径。' }
    if (-not (Test-Path -LiteralPath (Join-Path $Source 'package.json'))) { throw '备份包清单丢失。' }
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    Copy-Directory $Source $target
}

function Restore-Backup {
    param($Backup)
    $manifest = $Backup.Manifest
    if (-not $manifest.cliVersion) { throw '该备份之前未安装 CLI，无法恢复软件包。可使用 Official 安装官方版。' }
    if ($manifest.npmRoot -ne $script:NpmRoot) { throw '备份属于另一 npm root，请切回原 Node/npm 环境再还原。' }
    $daemonSource = $null
    if ($manifest.daemonBinary) {
        $savedDaemon = [IO.Path]::GetFullPath((Join-Path $Backup.Directory 'daemon'))
        $daemonSource = [IO.Path]::GetFullPath((Join-Path $savedDaemon $manifest.daemonBinary))
        if (-not $daemonSource.StartsWith($savedDaemon + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $daemonSource -PathType Leaf)) { throw 'daemon 备份路径无效或文件丢失。' }
    }
    if ($manifest.externalPlatform -and -not (Test-Path -LiteralPath (Join-Path $Backup.Directory 'platform/package.json'))) { throw '平台包备份丢失，尚未修改安装。' }
    Restore-PackageDirectory (Join-Path $Backup.Directory 'cli') (Join-Path $script:NpmRoot '@openai/codex')
    if ($manifest.externalPlatform) { Restore-PackageDirectory (Join-Path $Backup.Directory 'platform') (Join-Path $script:NpmRoot $script:PlatformPackage) }
    foreach ($name in @('codex', 'codex.cmd', 'codex.ps1')) {
        $shim = Join-Path (Join-Path $Backup.Directory 'shims') $name
        if (Test-Path -LiteralPath $shim) { Copy-Item -LiteralPath $shim -Destination (Join-Path $script:NpmPrefix $name) -Force }
    }
    $layout = Get-CliLayout
    $source = $layout.Binary
    if ($daemonSource) { $source = $daemonSource }
    # 用原 daemon 完整包恢复，允许备份时 CLI 与 daemon 本来就不同。
    Sync-Daemon $source ([bool]$manifest.daemonRunning)
    Write-Host '已还原 CLI 与 daemon 文件；恢复的 daemon 继续固定使用本地包，自动更新保持关闭。'
}

function Show-Status {
    $layout = Get-CliLayout
    if (-not $layout) { Write-Host '当前 npm 环境未安装 Codex。'; return }
    $daemon = Get-DaemonInfo $layout.Binary
    $daemonPath = $daemon.managedCodexPath
    if ($VerifyRelease) {
        $versions = @($layout.Version, (Get-Field $daemon 'managedCodexVersion')) | Where-Object { $_ } | Select-Object -Unique
        foreach ($candidate in $versions) {
            try { $null = Get-ReleasePackage $candidate } catch { Write-Warning "无法核验版本 $candidate 的 Release：$($_.Exception.Message)" }
        }
    }
    $cliHash = Get-BinaryHash $layout.Binary
    $daemonHash = Get-BinaryHash $daemonPath
    [pscustomobject]@{
        'CLI 包版本' = $layout.Version; 'CLI 实际版本' = Invoke-Tool $layout.Binary @('--version')
        'CLI 文件' = $layout.Binary; 'CLI 来源' = Get-BinaryKind $cliHash
        'daemon 安装版本' = Get-Field $daemon 'managedCodexVersion'
        'daemon 运行版本' = Get-Field $daemon 'appServerVersion'; 'daemon 状态' = $daemon.status
        'daemon 文件' = $daemonPath; 'daemon 来源' = Get-BinaryKind $daemonHash
        '磁盘文件一致' = [bool]($cliHash -and $daemonHash -and $cliHash -eq $daemonHash)
        '自动更新开关' = Get-AutoUpdatePreference
    } | Format-List | Out-Host
    Write-Host '文件一致性指磁盘内容；运行中的进程是否已加载新文件，还需结合运行版本和最近一次同步/重启结果。'
}

function Invoke-Change {
    param([string]$Operation)
    $package = $null
    $targetVersion = $Version
    if ($Operation -eq 'Install') {
        $package = Get-ReleasePackage $Version
        $targetVersion = $package.Version
    } elseif ($Operation -in @('Official', 'Uninstall')) {
        if (-not $targetVersion) { $targetVersion = Invoke-Tool $script:Npm @('view', '@openai/codex', 'version') }
        if ($targetVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'npm 未返回正式版本号。' }
    }
    $layout = Get-CliLayout
    $daemon = if ($layout) { Get-DaemonInfo $layout.Binary } else { $null }
    Assert-ClosedCli $layout $daemon
    $restore = $null
    if ($Operation -eq 'Restore') {
        $backups = @(Get-Backups | Where-Object { $_.cliVersion })
        if ($BackupId) { $backups = @($backups | Where-Object { $_.id -eq $BackupId }) }
        if (-not $backups.Count) { throw '没有匹配的完整 CLI 备份。' }
        $restore = [pscustomobject]@{ Directory = Join-Path $script:BackupRoot $backups[0].id; Manifest = $backups[0] }
        if ($restore.Manifest.npmRoot -ne $script:NpmRoot) { throw '备份属于另一 npm root，请切回原 Node/npm 环境。' }
        $targetVersion = $restore.Manifest.cliVersion
    }
    if ($Operation -eq 'Sync' -and -not $layout) { throw '请先安装 CLI。' }
    $activeCommand = Get-Command codex -ErrorAction SilentlyContinue
    if ($activeCommand -and $activeCommand.Source -notin @((Join-Path $script:NpmPrefix 'codex.cmd'), (Join-Path $script:NpmPrefix 'codex.ps1'))) {
        throw 'PATH 中的 codex 不属于当前 npm 前缀。请切换到对应 Node/npm 环境，避免修改错误的安装。'
    }
    # 下载与兼容性检查均在接触现有安装之前完成。
    $official = if ($Operation -in @('Install', 'Official', 'Uninstall')) { Get-OfficialPackage $targetVersion } else { $null }
    Confirm-Change "操作：$Operation；当前 CLI：$(if ($layout) { $layout.Version } else { '未安装' })；目标：$targetVersion"
    $backup = New-Backup $layout $daemon
    $stopped = $false
    try {
        # 先关闭更新偏好，再停止 daemon，避免 npm/补丁替换期间 updater 重新选包。
        Set-AutoUpdatePreference $false
        Stop-Daemon $layout
        $stopped = $true
        if ($Operation -eq 'Restore') {
            Restore-Backup $restore
        } else {
            if ($Operation -ne 'Sync') {
                Publish-NpmPackage $official
                $layout = Get-CliLayout
                if ($layout.Version -ne $targetVersion) { throw 'npm 安装后的版本不符合目标。' }
                if ($package) { Copy-Item -LiteralPath $package.Binary -Destination $layout.Binary -Force }
            }
            Sync-Daemon $layout.Binary ([bool]$backup.Manifest.daemonRunning)
            $updated = Get-DaemonInfo $layout.Binary
            if ((Get-BinaryHash $layout.Binary) -ne (Get-BinaryHash $updated.managedCodexPath)) { throw 'CLI 与 daemon 文件内容不一致。' }
        }
        Write-Host '操作成功。'
    } catch {
        $failure = $_
        Write-Warning "操作失败；保留备份 $($backup.Manifest.id)。"
        if ($stopped -and $backup.Manifest.cliVersion) {
            try {
                try { $current = Get-CliLayout; Stop-Daemon $current } catch { Write-Warning '当前包不完整，直接从完整备份恢复。' }
                Restore-Backup $backup
                Set-AutoUpdatePreference ([bool]$backup.Manifest.autoUpdateEnabled)
                Write-Warning '已回滚原文件。daemon 使用本地固定包；原自动更新开关已恢复。'
            } catch { Write-Warning "自动回滚未完成：$($_.Exception.Message)。请用 Restore -BackupId $($backup.Manifest.id) 恢复。" }
        }
        throw $failure
    }
    Show-Status
}

function Initialize-Manager {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '本脚本用于 Windows x64 npm 安装。' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw '请用普通用户终端运行；Codex daemon 不接受提升权限的管理命令。' }
    $script:Npm = (Get-Command npm.cmd -ErrorAction Stop).Source
    $node = (Get-Command node.exe -ErrorAction Stop).Source
    if ((Invoke-Tool $node @('-p', 'process.arch')) -ne 'x64') { throw 'Release 仅提供 Windows x64，请使用 x64 Node.js。' }
    $script:NpmRoot = [IO.Path]::GetFullPath((Invoke-Tool $script:Npm @('root', '--global')))
    $script:NpmPrefix = [IO.Path]::GetFullPath((Invoke-Tool $script:Npm @('prefix', '--global')))
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    $script:SettingsFile = Join-Path $codexHome 'app-server-daemon/settings.json'
    $script:StateRoot = if ($StateDirectory) { [IO.Path]::GetFullPath($StateDirectory) } else { Join-Path $codexHome 'patch-manager' }
    $script:StateRoot = [IO.Path]::GetFullPath($script:StateRoot)
    if ($script:StateRoot.StartsWith($script:NpmRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        $script:StateRoot -eq $script:NpmRoot) { throw '备份目录必须位于 npm root 之外。' }
    $script:BackupRoot = Join-Path $script:StateRoot 'backups'
    $script:WorkRoot = Join-Path (Join-Path $script:StateRoot 'downloads') ([guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $script:WorkRoot -Force
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

function Show-Menu {
    Write-Host "`nCodex 补丁管理"
    Write-Host '1 安装/更新 GitHub 最新补丁   2 恢复最近备份   3 卸载补丁/安装 npm 官方最新版'
    Write-Host '4 查看状态   5 列出备份   6 将当前 CLI 同步给 daemon   7 下载同版本 Release 核验来源   0 退出'
    switch (Read-Host '选择') {
        '1' { Invoke-Change 'Install' }
        '2' { Invoke-Change 'Restore' }
        '3' { Invoke-Change 'Official' }
        '4' { Show-Status }
        '5' { Get-Backups | Select-Object id, cliVersion, daemonRunning, createdAt | Format-Table -AutoSize | Out-Host }
        '6' { Invoke-Change 'Sync' }
        '7' { $script:VerifyRelease = $true; Show-Status }
        '0' { return }
        default { throw '无效选项。' }
    }
}

# 点加载仅定义函数，测试可用隔离目录和替身命令验证流程。
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Initialize-Manager
        switch ($Action) {
            'Menu' { Show-Menu }
            'Status' { Show-Status }
            'Backups' { Get-Backups | Select-Object id, cliVersion, daemonRunning, createdAt | Format-Table -AutoSize | Out-Host }
            default { Invoke-Change $Action }
        }
    } catch {
        Write-Error $_ -ErrorAction Continue
        exit 1
    } finally {
        # 只清理本次生成的下载目录，备份和来源登记长期保留。
        if ($script:WorkRoot -and (Test-Path -LiteralPath $script:WorkRoot)) {
            $downloadRoot = [IO.Path]::GetFullPath((Join-Path $script:StateRoot 'downloads'))
            $workPath = [IO.Path]::GetFullPath($script:WorkRoot)
            if ((Split-Path -Parent $workPath) -eq $downloadRoot -and (Split-Path -Leaf $workPath) -match '^[a-f0-9]{32}$') {
                Remove-Item -LiteralPath $workPath -Recurse -Force
            }
        }
    }
}
