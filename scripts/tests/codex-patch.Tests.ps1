#requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../codex-patch.ps1') -Yes

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('codex-patch-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtureRoot
$script:StateRoot = Join-Path $fixtureRoot 'state'
$script:WorkRoot = Join-Path $script:StateRoot 'downloads'
$script:BackupRoot = Join-Path $script:StateRoot 'backups'
$script:SettingsFile = Join-Path $fixtureRoot 'codex-home/app-server-daemon/settings.json'
$script:NpmPrefix = Join-Path $fixtureRoot 'node-prefix'
$script:NpmRoot = Join-Path $script:NpmPrefix 'node_modules'
$script:Npm = 'fixture-npm.cmd'
$script:DaemonRoot = Join-Path $fixtureRoot 'managed-daemon'
$script:DaemonBinary = Join-Path $script:DaemonRoot 'bin/codex.exe'
$script:DaemonRunning = $true
$script:FailSyncCount = 0
$script:CallLog = New-Object 'Collections.Generic.List[string]'
$script:VersionByContent = @{ 'old-cli' = '0.166.0'; 'old-daemon' = '0.165.0'; 'official-new' = '0.167.0'; 'patched-new' = '0.167.0' }
$script:Assertions = 0

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -cne $Expected) { throw "$Message；实际：$Actual；预期：$Expected" }
    $script:Assertions++
}

function Assert-Throws([scriptblock]$Body, [string]$Pattern) {
    $caught = $null
    try { & $Body } catch { $caught = $_.Exception.Message }
    if (-not $caught -or $caught -notmatch $Pattern) { throw "没有得到预期错误：$Pattern；实际：$caught" }
    $script:Assertions++
}

function Write-FixtureFile([string]$Path, [string]$Content) {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

function New-NpmFixture([string]$Prefix, [string]$PackageVersion, [string]$Content, [bool]$Hoisted = $false) {
    $wrapper = Join-Path $Prefix 'node_modules/@openai/codex'
    Write-Json (Join-Path $wrapper 'package.json') @{ name = '@openai/codex'; version = $PackageVersion }
    $platform = if ($Hoisted) { Join-Path $Prefix 'node_modules/@openai/codex-win32-x64' } else { Join-Path $wrapper 'node_modules/@openai/codex-win32-x64' }
    Write-Json (Join-Path $platform 'package.json') @{ name = '@openai/codex'; version = "$PackageVersion-win32-x64" }
    $package = Join-Path $platform "vendor/$script:TargetTriple"
    Write-Json (Join-Path $package 'codex-package.json') @{ version = $PackageVersion; entrypoint = 'bin/codex.exe' }
    Write-FixtureFile (Join-Path $package 'bin/codex.exe') $Content
    Write-FixtureFile (Join-Path $package 'codex-resources/helper.exe') "helper-$PackageVersion"
    foreach ($name in @('codex', 'codex.cmd', 'codex.ps1')) { Write-FixtureFile (Join-Path $Prefix $name) 'relative npm shim' }
}

try {
    # 先检查原生命令退出码传播，再替换外部边界，测试不接触实际 npm 或 daemon。
    $failingTool = Join-Path $fixtureRoot 'fail.cmd'
    Write-FixtureFile $failingTool "@exit /b 7`r`n"
    Assert-Throws { Invoke-Tool $failingTool @() } '退出码 7'

    function Invoke-Tool {
        param([string]$File, [string[]]$Arguments)
        $script:CallLog.Add(($Arguments -join ' '))
        if ($File -eq $script:Npm) {
            if ($Arguments[0] -eq 'view') { return '0.167.0' }
            if ($Arguments[0] -ne 'install' -or $Arguments[2] -ne '--prefix') { throw '测试发现意外 npm 命令。' }
            New-NpmFixture $Arguments[3] '0.167.0' 'official-new'
            return ''
        }
        if ($Arguments[0] -eq '--version') { return 'codex-cli ' + $script:VersionByContent[[IO.File]::ReadAllText($File)] }
        if ($Arguments -contains '--help') { return 'update --from-cli --yes' }
        switch ($Arguments[2]) {
            'version' {
                $managedVersion = if (Test-Path -LiteralPath $script:DaemonBinary) { $script:VersionByContent[[IO.File]::ReadAllText($script:DaemonBinary)] } else { $null }
                return ([pscustomobject]@{
                    status = $(if ($script:DaemonRunning) { 'running' } else { 'notRunning' })
                    managedCodexPath = $script:DaemonBinary; managedCodexVersion = $managedVersion
                    appServerVersion = $(if ($script:DaemonRunning) { $managedVersion } else { $null }); pid = 0
                } | ConvertTo-Json -Compress)
            }
            'stop' { $script:DaemonRunning = $false; return '{}' }
            'start' { $script:DaemonRunning = $true; return '{}' }
            'update' {
                if ($Arguments -notcontains '--from-cli' -or $Arguments -notcontains '--yes') { throw '同步未使用完整包固定入口。' }
                if ($script:FailSyncCount -gt 0) { $script:FailSyncCount--; throw 'fixture sync failure' }
                $source = Get-PackageDirectory $File
                Copy-Directory $source $script:DaemonRoot
                return '{}'
            }
            default { throw "意外原生命令：$($Arguments -join ' ')" }
        }
    }

    function Get-Command {
        param([string]$Name)
        if ($Name -ne 'codex') { throw '测试发现意外命令发现请求。' }
        [pscustomobject]@{ Source = Join-Path $script:NpmPrefix 'codex.cmd' }
    }

    $showStatus = ${function:Show-Status}
    function Show-Status { }
    function Out-Host { $script:StatusText = $input | Out-String -Width 4096 }

    New-NpmFixture $script:NpmPrefix '0.166.0' 'old-cli' $true
    Write-Json (Join-Path $script:DaemonRoot 'codex-package.json') @{ version = '0.165.0'; entrypoint = 'bin/codex.exe' }
    Write-FixtureFile $script:DaemonBinary 'old-daemon'
    Write-FixtureFile (Join-Path $script:DaemonRoot 'codex-resources/helper.exe') 'daemon-helper-old'
    Write-Json $script:SettingsFile @{ remoteControlEnabled = $true; custom = 'preserve'; updater = @{ autoUpdateEnabled = $true; updateIntervalMinutes = 17 } }
    Set-AutoUpdatePreference $false
    $settings = Read-Json $script:SettingsFile
    Assert-Equal $settings.custom 'preserve' '更新偏好应保留未知设置'
    Assert-Equal $settings.updater.updateIntervalMinutes 17 '更新偏好应保留间隔'
    Assert-Equal $settings.remoteControlEnabled $true '更新偏好应保留远程设置'

    # 实际 zip 解包和摘要校验；HTTP 仅返回本地 fixture。
    $archiveSource = Join-Path $fixtureRoot 'release-content'
    Write-FixtureFile (Join-Path $archiveSource 'codex.exe') 'patched-new'
    Write-FixtureFile (Join-Path $archiveSource 'BUILD-INFO.txt') "upstream_tag: rust-v0.167.0`npatch_is_exact: true`n"
    $script:FixtureZip = Join-Path $fixtureRoot 'release.zip'
    Compress-Archive -Path (Join-Path $archiveSource '*') -DestinationPath $script:FixtureZip
    $script:ReleaseDigest = 'sha256:' + (Get-BinaryHash $script:FixtureZip)
    function Invoke-RestMethod {
        param($Uri, $Headers)
        [pscustomobject]@{
            draft = $false; prerelease = $false; tag_name = 'rust-v0.167.0'
            assets = @([pscustomobject]@{
                name = 'codex-rust-v0.167.0-windows-x64.zip'; digest = $script:ReleaseDigest
                browser_download_url = 'https://github.com/owwkmidream/codex/releases/download/rust-v0.167.0/codex-rust-v0.167.0-windows-x64.zip'
            })
        }
    }
    function Invoke-WebRequest {
        param($Uri, $OutFile, [switch]$UseBasicParsing)
        Copy-Item -LiteralPath $script:FixtureZip -Destination $OutFile
    }
    $null = New-Item -ItemType Directory -Path $script:WorkRoot -Force
    $release = Get-ReleasePackage '0.167.0'
    Assert-Equal $release.Version '0.167.0' 'Release 版本应来自目标 tag'
    Assert-Equal (Get-BinaryKind (Get-BinaryHash $release.Binary)) '已确认补丁版 0.167.0' '来源应按文件登记'
    $script:ReleaseDigest = 'sha256:' + ('0' * 64)
    Assert-Throws { Get-ReleasePackage '0.167.0' } 'SHA256'
    $script:ReleaseDigest = 'sha256:' + (Get-BinaryHash $script:FixtureZip)
    Assert-Throws { Get-ReleasePackage '../bad' } 'Version'
    Assert-Throws { Get-ReleasePackage '0.166.0' } 'tag 与请求版本'

    # 完整安装：旧版提升布局 -> 新版嵌套布局，两个独立旧版本都应保留备份。
    Invoke-Change 'Install'
    $installed = Get-CliLayout
    Assert-Equal $installed.Version '0.167.0' '安装应匹配 Release 版本'
    Assert-Equal ([IO.File]::ReadAllText($installed.Binary)) 'patched-new' 'CLI 应替换补丁'
    Assert-Equal ([IO.File]::ReadAllText($script:DaemonBinary)) 'patched-new' 'daemon 应复制补丁'
    Assert-Equal $script:DaemonRunning $true '原来运行的 daemon 应恢复运行'
    Assert-Equal (Get-AutoUpdatePreference) $false '补丁安装后自动更新应关闭'
    & $showStatus
    Assert-Equal ([bool]($script:StatusText -match 'CLI 来源\s*:\s*已确认补丁版 0\.167\.0')) $true '状态应识别实际补丁来源'
    Assert-Equal ([bool]($script:StatusText -match '磁盘文件一致\s*:\s*True')) $true '状态应显示文件一致'
    $initial = @(Get-Backups)[0]
    Assert-Equal $initial.externalPlatform $true '提升的平台依赖应独立备份'
    $backup = [pscustomobject]@{ Directory = Join-Path $script:BackupRoot $initial.id; Manifest = $initial }
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $backup.Directory 'daemon/bin/codex.exe'))) 'old-daemon' 'daemon 应保存自身旧版本'
    Assert-Throws { Restore-PackageDirectory (Join-Path $backup.Directory 'cli') $fixtureRoot } '以外的路径'

    $script:BackupId = $initial.id
    Invoke-Change 'Restore'
    $script:BackupId = $null
    Assert-Equal ([IO.File]::ReadAllText((Get-CliLayout).Binary)) 'old-cli' '恢复 CLI 备份'
    Assert-Equal ([IO.File]::ReadAllText($script:DaemonBinary)) 'old-daemon' '恢复独立 daemon 备份'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $script:DaemonRoot 'codex-resources/helper.exe'))) 'daemon-helper-old' '恢复 daemon 辅助程序'
    & $showStatus
    Assert-Equal ([bool]($script:StatusText -match '磁盘文件一致\s*:\s*False')) $true '状态应识别原本不同的 CLI 与 daemon'

    # 已打补丁的同版本包不能让 npm 的“已最新”判断阻止恢复官方文件。
    Invoke-Change 'Install'
    Invoke-Change 'Official'
    Assert-Equal ([IO.File]::ReadAllText((Get-CliLayout).Binary)) 'official-new' '官方恢复应覆盖同版本补丁'
    Assert-Equal ([IO.File]::ReadAllText($script:DaemonBinary)) 'official-new' '官方恢复应同步 daemon'
    Assert-Equal (Get-BinaryKind (Get-BinaryHash (Get-CliLayout).Binary)) '已登记 npm 官方版 0.167.0' '官方来源应正确登记'

    # 同步失败只失败一次，随后回滚应恢复两个包及原运行状态。
    $script:FailSyncCount = 1
    Assert-Throws { Invoke-Change 'Install' } 'fixture sync failure'
    Assert-Equal ([IO.File]::ReadAllText((Get-CliLayout).Binary)) 'official-new' '失败后恢复 CLI'
    Assert-Equal ([IO.File]::ReadAllText($script:DaemonBinary)) 'official-new' '失败后恢复 daemon'
    Assert-Equal $script:DaemonRunning $true '失败后恢复运行状态'

    $script:DaemonRunning = $false
    Invoke-Change 'Sync'
    Assert-Equal $script:DaemonRunning $false '原来停止的 daemon 应保持停止'
    Assert-Equal ((Get-Backups).Count -ge 5) $true '每次修改均保留备份'

    # 首次安装同样生成 daemon 包，但不擅自留下后台服务。
    $script:NpmPrefix = Join-Path $fixtureRoot 'fresh-node'
    $script:NpmRoot = Join-Path $script:NpmPrefix 'node_modules'
    $script:DaemonRoot = Join-Path $fixtureRoot 'fresh-daemon'
    $script:DaemonBinary = Join-Path $script:DaemonRoot 'bin/codex.exe'
    Invoke-Change 'Install'
    Assert-Equal ([IO.File]::ReadAllText((Get-CliLayout).Binary)) 'patched-new' '首次安装应建立 CLI'
    Assert-Equal ([IO.File]::ReadAllText($script:DaemonBinary)) 'patched-new' '首次安装应建立 daemon 包'
    Assert-Equal $script:DaemonRunning $false '首次安装后原先未运行的服务保持停止'

    # 同一秒产生的备份必须按清单时间排序，随机目录后缀不代表先后顺序。
    $script:BackupRoot = Join-Path $fixtureRoot 'ordering-backups'
    foreach ($entry in @(
        @{ id = '20260101-000000-ffffffff'; createdAt = '2026-01-01T00:00:00.1000000Z' },
        @{ id = '20260101-000000-00000000'; createdAt = '2026-01-01T00:00:00.2000000Z' }
    )) { Write-Json (Join-Path (Join-Path $script:BackupRoot $entry.id) 'backup.json') $entry }
    Assert-Equal (@(Get-Backups)[0].id) '20260101-000000-00000000' '最近备份应以实际创建时间判断'
    Write-Host "PASS: $script:Assertions assertions; fixture npm/daemon/HTTP only."
} finally {
    # 仅删除本测试创建、且已核对位于系统临时目录下的 fixture。
    $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    if ((Split-Path -Parent $fixtureRoot) -eq $expectedParent -and (Split-Path -Leaf $fixtureRoot) -match '^codex-patch-test-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
