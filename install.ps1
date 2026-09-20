# pmgr installer for Windows (PowerShell 5.1+ / PowerShell 7+)
#
# Usage:
#   .\install.ps1
#   .\install.ps1 -Force
#   .\install.ps1 -Uninstall
#   .\install.ps1 -NoDeps
#
# If execution policy blocks the script, run:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Uninstall,
    [switch]$NoDeps,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# ── 输出辅助 ────────────────────────────────────────────────────────
function Write-Log   { param($m) Write-Host "[pmgr] $m" -ForegroundColor Cyan }
function Write-Ok    { param($m) Write-Host "[pmgr] $m" -ForegroundColor Green }
function Write-Warn2 { param($m) Write-Host "[pmgr] $m" -ForegroundColor Yellow }
function Write-Err   { param($m) Write-Host "[pmgr] $m" -ForegroundColor Red }

function Die {
    param($m)
    Write-Err $m
    exit 1
}

if ($Help) {
    @"
pmgr installer for Windows

Usage: .\install.ps1 [options]

Options:
  -Force       Overwrite existing installation
  -Uninstall   Remove the plugin
  -NoDeps      Skip Python dependency installation
  -Help        Show this help
"@ | Write-Host
    exit 0
}

# ── 定位源目录 ──────────────────────────────────────────────────────
# 直接运行（.\install.ps1）时源码就在脚本旁边；
# 管道执行（iwr ... | iex）时没有脚本路径，改为下载源码包。
$RepoSlug = if ($env:PMGR_REPO) { $env:PMGR_REPO } else { 'metaone01/hermes-profile-manager' }
$RepoRef  = if ($env:PMGR_REF)  { $env:PMGR_REF }  else { 'main' }
$TarballUrl = if ($env:PMGR_TARBALL_URL) {
    $env:PMGR_TARBALL_URL
} else {
    # GitHub zipball：Expand-Archive 只支持 zip，不能用 .tar.gz
    "https://codeload.github.com/$RepoSlug/zip/refs/heads/$RepoRef"
}
$PluginFiles = @('plugin.yaml', '__init__.py', 'i18n.py', 'core.py',
                 'commands.py', 'test_conn.py', 'cli.py')

$TmpDir = $null
$ScriptDir = $null
if ($MyInvocation.MyCommand.Path) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

if ($ScriptDir -and (Test-Path (Join-Path $ScriptDir 'pmgr'))) {
    $SrcDir = Join-Path $ScriptDir 'pmgr'
    Write-Log "Using local source: $SrcDir"
} else {
    Write-Log "Downloading source: $RepoSlug@$RepoRef"
    $TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pmgr-install-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null
    $zip = Join-Path $TmpDir 'src.zip'
    try {
        Invoke-WebRequest -Uri $TarballUrl -OutFile $zip -UseBasicParsing
    } catch {
        Die "Download failed: $TarballUrl ($($_.Exception.Message))"
    }
    try {
        Expand-Archive -Path $zip -DestinationPath $TmpDir -Force
    } catch {
        Die "Extract failed: $TarballUrl ($($_.Exception.Message))"
    }
    $root = @(Get-ChildItem -Path $TmpDir -Directory)
    if ($root.Count -ne 1) { Die "Unexpected archive layout in $TarballUrl" }
    $SrcDir = Join-Path $root[0].FullName 'pmgr'
    if (-not (Test-Path $SrcDir)) { Die "pmgr/ not found in downloaded archive" }
    Write-Ok "Source ready: $SrcDir"
}

# ── 定位 Hermes 插件目录 ────────────────────────────────────────────
if ($env:HERMES_HOME) {
    $HermesHome = $env:HERMES_HOME
} else {
    $HermesHome = Join-Path $env:USERPROFILE '.hermes'
}
$PluginDir = Join-Path $HermesHome 'plugins'
$DestDir   = Join-Path $PluginDir 'pmgr'

# hermes 可执行文件（用于写/读 config.yaml 的 plugins.enabled）；找不到时静默跳过
$HermesCmd = Get-Command hermes -ErrorAction SilentlyContinue

# 在指定的 HERMES_HOME 下执行 `hermes <args>` 并返回退出码（不影响调用者环境）
function Invoke-Hermes {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    if (-not $HermesCmd) { return 127 }
    $prevHome = $env:HERMES_HOME
    $env:HERMES_HOME = $HermesHome
    try {
        & $HermesCmd @Args *> $null
        return $LASTEXITCODE
    } finally {
        if ($null -eq $prevHome) { Remove-Item Env:\HERMES_HOME -ErrorAction SilentlyContinue }
        else { $env:HERMES_HOME = $prevHome }
    }
}

# ── 卸载 ────────────────────────────────────────────────────────────
if ($Uninstall) {
    # 安装时会把插件写进 config.yaml 的 plugins.enabled，卸载时对应清掉
    # （先用插件仍在的时机 disable；失败不阻断卸载本身）。
    if ($HermesCmd) {
        $rc = Invoke-Hermes plugins disable pmgr
        if ($rc -eq 0) { Write-Ok "Disabled in $HermesHome\config.yaml" }
        else { Write-Warn2 "Could not disable automatically; remove 'pmgr' from plugins.enabled by hand." }
    }
    if (Test-Path $DestDir) {
        Remove-Item -Recurse -Force $DestDir
        Write-Ok "Uninstalled: $DestDir"
    } else {
        Write-Warn2 "Not installed: $DestDir"
    }
    exit 0
}

# ── Python 检测 ─────────────────────────────────────────────────────
$PythonExe = $null
foreach ($candidate in @('python', 'python3', 'py')) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($cmd) {
        try {
            $ver = & $candidate -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
            if ($LASTEXITCODE -eq 0 -and $ver) {
                $PythonExe = $candidate
                $PyVer = $ver.Trim()
                break
            }
        } catch { }
    }
}
if (-not $PythonExe) {
    Die "Python 3.9+ not found. Install from https://www.python.org/downloads/windows/ or the Microsoft Store."
}

$parts = $PyVer.Split('.')
if ([int]$parts[0] -lt 3 -or ([int]$parts[0] -eq 3 -and [int]$parts[1] -lt 9)) {
    Die "Python 3.9+ required, found $PyVer"
}
Write-Ok "Python $PyVer detected ($PythonExe)"

# ── 依赖安装 ────────────────────────────────────────────────────────
# PyYAML 必需；httpx 可选（缺失时 `pmgr test` 回退 urllib）。
# 可选依赖装不上不应该中断安装本身。
if (-not $NoDeps) {
    Write-Log "Checking Python dependencies..."
    $missingMods = @(& $PythonExe -c @"
import importlib.util as u
print(' '.join(m for m in ('yaml', 'httpx') if u.find_spec(m) is None))
"@)
    $missingText = ($missingMods | Out-String).Trim()
    $missReq = $missingText -match '\byaml\b'
    $missOpt = $missingText -match '\bhttpx\b'

    if ($missReq) {
        Write-Warn2 "Missing required package: PyYAML"
        $ans = Read-Host "Install now with pip? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($ans)) { $ans = 'Y' }
        if ($ans -match '^[Yy]') {
            & $PythonExe -m pip install --user PyYAML
            if ($LASTEXITCODE -ne 0) {
                Die "pip install failed. Try manually: $PythonExe -m pip install PyYAML"
            }
            Write-Ok "PyYAML installed"
        } else {
            Write-Warn2 "Skipped; pmgr requires PyYAML to run."
        }
    } else {
        Write-Ok "Required dependency present (PyYAML)"
    }

    if ($missOpt) {
        Write-Warn2 "Missing optional package: httpx (only 'pmgr test' needs it; falls back to urllib)"
        $ans = Read-Host "Install httpx now with pip? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($ans)) { $ans = 'Y' }
        if ($ans -match '^[Yy]') {
            # 可选依赖装不上只警告，不中断安装
            & $PythonExe -m pip install --user httpx
            if ($LASTEXITCODE -ne 0) {
                Write-Warn2 "Could not install httpx; continuing anyway."
                Write-Warn2 "Install manually if needed: $PythonExe -m pip install httpx"
            } else {
                Write-Ok "httpx installed"
            }
        } else {
            Write-Warn2 "Skipped httpx."
        }
    } else {
        Write-Ok "Optional dependency present (httpx)"
    }
} else {
    Write-Warn2 "Skipping dependency check (-NoDeps)"
}

# ── 备份已存在的安装 ────────────────────────────────────────────────
if (-not (Test-Path $PluginDir)) {
    New-Item -ItemType Directory -Path $PluginDir -Force | Out-Null
}

# 备份放到 $HermesHome\backups\plugins\ 而不是 plugins\ 之内：插件目录下每个含
# plugin.yaml 的子目录都会被当成插件扫描，旧副本的 manifest name 同样是 pmgr，
# 会和刚装好的版本争同一个 key——实测旧副本赢，升级后加载的仍是旧代码。
$BackupRoot = Join-Path (Join-Path (Join-Path $HermesHome 'backups') 'plugins') 'pmgr'

# 老版本安装器把备份留在 plugins\ 里：那份副本会被当成**独立插件**扫描，与正式副本
# 按 manifest name 争同一个 key，实测旧副本胜出，于是新装的代码根本没被加载——表现
# 就是"装好了也重启了，命令还是崩/还是旧行为"。
# 因此直接移走，而不是只警告：留着这一份，本次安装等于没生效。
# 需要保留原地时设 $env:PMGR_KEEP_LEGACY='1'（自担风险，只会告警）。
$LegacyMoved = 0
Get-ChildItem -Path $PluginDir -Directory -Filter 'pmgr.backup.*' -ErrorAction SilentlyContinue |
    ForEach-Object {
        if ($env:PMGR_KEEP_LEGACY -eq '1') {
            Write-Warn2 "Legacy copy inside the plugin dir competes for plugin key 'pmgr':"
            Write-Warn2 "  $($_.FullName)"
            Write-Warn2 "  Move it out yourself:  Move-Item '$($_.FullName)' '$BackupRoot\'"
        } else {
            if (-not (Test-Path $BackupRoot)) {
                New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
            }
            $legacyDest = Join-Path $BackupRoot "legacy-$($_.Name)"
            while (Test-Path $legacyDest) { $legacyDest = "${legacyDest}_" }
            Move-Item -Path $_.FullName -Destination $legacyDest -Force
            $LegacyMoved++
            Write-Ok "Moved competing legacy copy out of the plugin dir: $legacyDest"
        }
    }
if ($LegacyMoved -gt 0) {
    Write-Ok "Isolated $LegacyMoved legacy copy/copies (they would have shadowed the new install)"
}

if (Test-Path $DestDir) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    if (-not (Test-Path $BackupRoot)) {
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    }
    $backup = Join-Path $BackupRoot "$timestamp-$PID"
    while (Test-Path $backup) {
        $backup = "${backup}_"
    }

    if (-not $Force) {
        Write-Warn2 "pmgr is already installed at: $DestDir"
        $ans = Read-Host "Overwrite? Existing files will be backed up. [y/N]"
        if ($ans -notmatch '^[Yy]') {
            Die "Aborted by user"
        }
    }

    Move-Item -Path $DestDir -Destination $backup -Force
    Write-Ok "Existing installation backed up to: $backup"
}

# ── 复制插件 ────────────────────────────────────────────────────────
Write-Log "Installing plugin to: $DestDir"
Copy-Item -Path $SrcDir -Destination $DestDir -Recurse -Force
Write-Ok "Files copied"

# ── 验证 ────────────────────────────────────────────────────────────
Write-Log "Verifying installation..."
$missingFiles = @()
foreach ($f in $PluginFiles) {
    if (-not (Test-Path (Join-Path $DestDir $f))) {
        $missingFiles += $f
    }
}
if ($missingFiles.Count -gt 0) {
    Die "Installation incomplete; missing: $($missingFiles -join ', ')"
}
Write-Ok "All files present"

# ── 竞争副本自查 ────────────────────────────────────────────────────
# plugins\ 下每个含 plugin.yaml 的子目录都是一个独立插件，按 manifest name 抢占同一个
# key。同名的旧副本会覆盖注册，`hermes pmgr` 实际执行的是那份旧代码，而响应测试仍然
# "能跑"，于是误报成功。
$Competing = ''
Get-ChildItem -Path $PluginDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.FullName -eq $DestDir) { return }
    $mf = Join-Path $_.FullName 'plugin.yaml'
    if (-not (Test-Path $mf)) { return }
    $nameLine = Select-String -Path $mf -Pattern '^\s*name:\s*["'']?pmgr["'']?\s*$' -ErrorAction SilentlyContinue
    if ($nameLine) { $Competing = $_.FullName }
}
if ($Competing) {
    Write-Warn2 "Another copy in the plugin dir registers the same plugin name 'pmgr':"
    Write-Warn2 "  $Competing"
    Write-Warn2 "  It wins the key and shadows this installation; remove or move it out."
} else {
    Write-Ok "No competing copy of 'pmgr' in $PluginDir"
}

# ── 启用插件 ────────────────────────────────────────────────────────
# 用户级插件是 opt-in：只把文件放进 plugins/ 不会加载，必须在 config.yaml 的
# plugins.enabled 里登记（否则 `hermes pmgr` 命令不存在）。pmgr 只提供 CLI
# 子命令，不需要内建工具替换权限，故显式拒绝该授权。
$Enabled = $false
if ($env:PMGR_NO_ENABLE -eq '1') {
    Write-Warn2 "Skipping 'hermes plugins enable' (PMGR_NO_ENABLE=1)"
} elseif (-not $HermesCmd) {
    Write-Warn2 "'hermes' not found on PATH; skipping plugin activation"
} else {
    if ((Invoke-Hermes plugins enable pmgr --no-allow-tool-override) -eq 0) {
        Write-Ok "Plugin enabled in $HermesHome\config.yaml"
        $Enabled = $true
    } else {
        Write-Warn2 "Could not enable the plugin automatically."
    }
}

# 回读真实状态：确认 enable 之后 `hermes pmgr` 真的能响应。
# 注意被同名副本遮蔽时它仍然"能跑"，所以先看竞争副本自查的结论。
if ($Enabled -and $Competing) {
    Write-Warn2 "Activation NOT verified: '$Competing' still registers the name 'pmgr'."
    $Enabled = $false
    $VerifyNote = 'blocked by competing copy'
} elseif ($Enabled) {
    if ((Invoke-Hermes pmgr list) -eq 0) {
        Write-Ok "Verified: 'hermes pmgr' responds"
    } else {
        Write-Warn2 "'hermes pmgr' did not respond; check 'hermes pmgr --help' manually"
        $Enabled = $false
    }
}

# ── 清理临时目录 ────────────────────────────────────────────────────
if ($TmpDir -and (Test-Path $TmpDir)) {
    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
}

# ── 完成 ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "OK  pmgr installed successfully" -ForegroundColor Green
Write-Host ""
Write-Host "  Plugin dir:  $DestDir"
Write-Host "  Hermes home: $HermesHome"
Write-Host "  Activated:   $(if ($Enabled) { 'yes' } else { 'NO (see warnings above)' })$(if ($VerifyNote) { " ($VerifyNote)" } else { '' })"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Run:  hermes pmgr list"
Write-Host "  2. Run:  hermes pmgr doctor"
Write-Host ""
Write-Host "Docs:  https://github.com/metaone01/hermes-profile-manager"
if ($Enabled) {
    Write-Host ""
    Write-Host "Note: a running gateway loaded its plugins at startup; restart it (or start a new" -ForegroundColor DarkGray
    Write-Host "session) before ``hermes pmgr`` shows up there." -ForegroundColor DarkGray
}