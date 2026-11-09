param(
    [Parameter(Mandatory)]
    [ValidateSet('Start', 'Watch', 'Finish')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
$diagnosticsDir = Join-Path $env:RUNNER_TEMP 'cache-diagnostics'
$stopFile = Join-Path $diagnosticsDir 'stop'
$samplesFile = Join-Path $diagnosticsDir 'resources.jsonl'

function Write-ResourceSample {
    $os = Get-CimInstance Win32_OperatingSystem
    $memory = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
    $sample = [ordered]@{
        timeUtc = [DateTime]::UtcNow.ToString('o')
        totalMemoryBytes = [long]$os.TotalVisibleMemorySize * 1KB
        freeMemoryBytes = [long]$os.FreePhysicalMemory * 1KB
        committedBytes = $memory.CommittedBytes
        commitLimitBytes = $memory.CommitLimit
        cpuCount = [Environment]::ProcessorCount
        disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
            Select-Object DeviceID, Size, FreeSpace)
        processes = @(Get-Process -Name sccache, cargo, rustc, link, lld-link -ErrorAction SilentlyContinue |
            Select-Object Id, ProcessName, StartTime, CPU, WorkingSet64, PrivateMemorySize64, PeakWorkingSet64)
    }
    $sample | ConvertTo-Json -Depth 4 -Compress | Add-Content -LiteralPath $samplesFile -Encoding utf8
}

if ($Action -eq 'Start') {
    New-Item -ItemType Directory -Path $diagnosticsDir -Force | Out-Null
    "SCCACHE_ERROR_LOG=$diagnosticsDir/sccache-server.log" | Add-Content -LiteralPath $env:GITHUB_ENV -Encoding utf8
    [DateTime]::UtcNow.ToString('o') | Set-Content (Join-Path $diagnosticsDir 'started-at.txt')
    Write-ResourceSample
    # 在 CI 校验实际采样结果，再启动后台采样；本机不运行此脚本。
    $sample = Get-Content -LiteralPath $samplesFile -Tail 1 | ConvertFrom-Json
    if ($sample.totalMemoryBytes -le 0 -or $sample.commitLimitBytes -le 0 -or $sample.disks.Count -eq 0) {
        throw '资源采样缺少内存或磁盘信息'
    }
    $monitor = Start-Process -FilePath (Get-Process -Id $PID).Path -WindowStyle Hidden -PassThru `
        -ArgumentList @('-NoProfile', '-File', "`"$PSCommandPath`"", '-Action', 'Watch') `
        -RedirectStandardOutput (Join-Path $diagnosticsDir 'monitor-output.log') `
        -RedirectStandardError (Join-Path $diagnosticsDir 'monitor-error.log')
    $monitor.Id | Set-Content (Join-Path $diagnosticsDir 'monitor.pid')
    Write-Host "资源采样校验通过；后台采样 PID=$($monitor.Id)，间隔 30 秒"
    return
}

if ($Action -eq 'Watch') {
    while (-not (Test-Path -LiteralPath $stopFile)) {
        Write-ResourceSample
        # 每 30 秒采样；每秒检查退出信号，避免结束 job 时额外等待半分钟。
        for ($second = 0; $second -lt 30 -and -not (Test-Path -LiteralPath $stopFile); $second++) {
            Start-Sleep -Seconds 1
        }
    }
    return
}

if (-not (Test-Path -LiteralPath $diagnosticsDir)) { return }
New-Item -ItemType File -Path $stopFile -Force | Out-Null
$pidFile = Join-Path $diagnosticsDir 'monitor.pid'
if (Test-Path -LiteralPath $pidFile) {
    $monitor = Get-Process -Id ([int](Get-Content -LiteralPath $pidFile)) -ErrorAction SilentlyContinue
    if ($monitor -and -not $monitor.WaitForExit(35000)) {
        Write-Warning '资源采样尚未退出，附件可能仍在写入'
    }
}
Write-ResourceSample
$startedAt = [datetime](Get-Content (Join-Path $diagnosticsDir 'started-at.txt'))
# 只收集本次任务的资源耗尽事件与编译相关崩溃，不导出环境变量或进程命令行。
$events = @(
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=2004; StartTime=$startedAt} -ErrorAction SilentlyContinue
    Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000,1001; StartTime=$startedAt} -ErrorAction SilentlyContinue |
        Where-Object Message -Match '(?i)\b(sccache|rustc|cargo|link|lld-link)\.exe\b'
)
ConvertTo-Json -InputObject @($events | Select-Object TimeCreated, Id, ProviderName, Message) -Depth 4 |
    Set-Content (Join-Path $diagnosticsDir 'windows-events.json') -Encoding utf8
$sampleCount = (Get-Content -LiteralPath $samplesFile | Measure-Object -Line).Lines
if ($sampleCount -lt 3) { throw '后台采样未产生记录，请检查 monitor-error.log' }
Write-Host "已保存 $sampleCount 条资源采样，$($events.Count) 条 Windows 事件"
