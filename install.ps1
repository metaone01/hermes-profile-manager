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

# ── 卸载 ────────────────────────────────────────────────────────────
if ($Uninstall) {
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

if (Test-Path $DestDir) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$DestDir.backup.$timestamp"

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
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Restart Hermes"
Write-Host "  2. Run:  hermes pmgr list"
Write-Host "  3. Run:  hermes pmgr doctor"
Write-Host ""
Write-Host "Docs:  https://github.com/metaone01/hermes-profile-manager"