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
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SrcDir = Join-Path $ScriptDir 'pmgr'
if (-not (Test-Path $SrcDir)) {
    Die "Source directory not found: $SrcDir"
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
if (-not $NoDeps) {
    Write-Log "Checking Python dependencies..."
    $missing = & $PythonExe -c @"
import importlib.util as u
missing = []
for mod, pkg in (('yaml', 'PyYAML'), ('httpx', 'httpx')):
    if u.find_spec(mod) is None:
        missing.append(pkg)
print(' '.join(missing))
"@

    if ($missing -and $missing.Trim().Length -gt 0) {
        Write-Warn2 "Missing packages: $missing"
        $ans = Read-Host "Install now with pip? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($ans)) { $ans = 'Y' }
        if ($ans -match '^[Yy]') {
            & $PythonExe -m pip install --user $missing.Split(' ')
            if ($LASTEXITCODE -ne 0) {
                Die "pip install failed. Try manually: $PythonExe -m pip install $missing"
            }
            Write-Ok "Dependencies installed"
        } else {
            Write-Warn2 "Skipped. Some pmgr commands may fail (e.g. ``pmgr test``)."
        }
    } else {
        Write-Ok "All Python dependencies present"
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
$required = @('plugin.yaml', '__init__.py', 'i18n.py', 'core.py',
              'commands.py', 'test_conn.py', 'cli.py')
$missingFiles = @()
foreach ($f in $required) {
    if (-not (Test-Path (Join-Path $DestDir $f))) {
        $missingFiles += $f
    }
}
if ($missingFiles.Count -gt 0) {
    Die "Installation incomplete; missing: $($missingFiles -join ', ')"
}
Write-Ok "All files present"

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