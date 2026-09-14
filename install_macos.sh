#!/usr/bin/env bash
# pmgr installer for macOS (Homebrew-aware)
# Usage: ./install-macos.sh [--force] [--uninstall] [--no-deps]

set -euo pipefail

# ── 颜色 ────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
    BLUE=$'\033[34m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
fi

log()   { printf "%s[pmgr]%s %s\n" "$BLUE"   "$RESET" "$*"; }
ok()    { printf "%s[pmgr]%s %s\n" "$GREEN"  "$RESET" "$*"; }
warn()  { printf "%s[pmgr]%s %s\n" "$YELLOW" "$RESET" "$*" >&2; }
err()   { printf "%s[pmgr]%s %s\n" "$RED"    "$RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }

# ── macOS 检测 ──────────────────────────────────────────────────────
if [ "$(uname -s)" != "Darwin" ]; then
    die "This script is for macOS only. Use install.sh on Linux."
fi

MACOS_VERSION=$(sw_vers -productVersion)
ARCH=$(uname -m)
ok "Detected macOS $MACOS_VERSION ($ARCH)"

# ── 参数解析 ────────────────────────────────────────────────────────
FORCE=0
UNINSTALL=0
NO_DEPS=0
for arg in "$@"; do
    case "$arg" in
        --force|-f)     FORCE=1 ;;
        --uninstall)    UNINSTALL=1 ;;
        --no-deps)      NO_DEPS=1 ;;
        --help|-h)
            cat <<EOF
pmgr installer for macOS

Usage: ./install-macos.sh [options]

Options:
  -f, --force       Overwrite existing installation
      --uninstall   Remove the plugin
      --no-deps     Skip Python dependency installation
  -h, --help        Show this help
EOF
            exit 0
            ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

# ── 路径 ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/pmgr"
[ -d "$SRC_DIR" ] || die "Source directory not found: $SRC_DIR"

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
PLUGIN_DIR="$HERMES_HOME/plugins"
DEST_DIR="$PLUGIN_DIR/pmgr"

# ── 卸载 ────────────────────────────────────────────────────────────
if [ "$UNINSTALL" -eq 1 ]; then
    if [ -d "$DEST_DIR" ]; then
        rm -rf "$DEST_DIR"
        ok "Uninstalled: $DEST_DIR"
    else
        warn "Not installed: $DEST_DIR"
    fi
    exit 0
fi

# ── Homebrew 检测（可选）────────────────────────────────────────────
if command -v brew >/dev/null 2>&1; then
    BREW_PREFIX="$(brew --prefix)"
    ok "Homebrew found at $BREW_PREFIX"
else
    warn "Homebrew not found. Some installs may fall back to pip --user."
fi

# ── Python 检测（macOS 特有：优先 Homebrew Python）───────────────────
PYTHON_BIN=""

# 1) 若 PATH 中有 brew python3 则优先
if command -v brew >/dev/null 2>&1; then
    for candidate in \
        "$(brew --prefix 2>/dev/null)/bin/python3" \
        "/opt/homebrew/bin/python3" \
        "/usr/local/bin/python3"; do
        if [ -x "$candidate" ]; then
            PYTHON_BIN="$candidate"
            break
        fi
    done
fi

# 2) 回退到 PATH
if [ -z "$PYTHON_BIN" ]; then
    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1; then
            PYTHON_BIN="$candidate"
            break
        fi
    done
fi

[ -n "$PYTHON_BIN" ] || {
    err "Python 3.9+ not found."
    cat <<EOF

Install Python first:
  brew install python@3.11

Or download from https://www.python.org/downloads/macos/
EOF
    exit 1
}

PY_VER=$("$PYTHON_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])')
PY_MAJOR=${PY_VER%%.*}
PY_MINOR=${PY_VER##*.}
if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 9 ]; }; then
    die "Python 3.9+ required, found $PY_VER at $PYTHON_BIN"
fi
ok "Python $PY_VER detected ($PYTHON_BIN)"

# 检测是否为 Homebrew Python（避免 PEP 668 externally-managed 错误）
IS_BREW_PY=0
if [[ "$PYTHON_BIN" == /opt/homebrew/* || "$PYTHON_BIN" == /usr/local/Cellar/* || \
      "$PYTHON_BIN" == /usr/local/opt/* || "$PYTHON_BIN" == /opt/homebrew/Cellar/* ]]; then
    IS_BREW_PY=1
fi

# ── 依赖安装 ────────────────────────────────────────────────────────
if [ "$NO_DEPS" -eq 0 ]; then
    log "Checking Python dependencies..."
    MISSING=$("$PYTHON_BIN" - <<'PY'
import importlib.util as u
missing = []
for mod, pkg in (("yaml", "PyYAML"), ("httpx", "httpx")):
    if u.find_spec(mod) is None:
        missing.append(pkg)
print(" ".join(missing))
PY
)
    if [ -n "$MISSING" ]; then
        warn "Missing packages: $MISSING"
        if [ "$IS_BREW_PY" -eq 1 ]; then
            warn "Homebrew Python detected; PEP 668 may block pip install."
            cat <<EOF

Recommended (isolated install via pipx):
  brew install pipx
  pipx install pyyaml
  pipx inject pyyaml httpx

Or, install directly with pip using --break-system-packages:
  $PYTHON_BIN -m pip install --break-system-packages $MISSING

EOF
        fi

        read -r -p "Install now with pip --user? [Y/n]: " ans
        ans=${ans:-Y}
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            if "$PYTHON_BIN" -m pip install --user $MISSING 2>/dev/null; then
                ok "Dependencies installed"
            else
                warn "pip --user failed (likely PEP 668). Retrying with --break-system-packages..."
                "$PYTHON_BIN" -m pip install --user --break-system-packages $MISSING \
                    || die "pip install failed. Try: brew install pipx && pipx install pyyaml"
                ok "Dependencies installed (with --break-system-packages)"
            fi
        else
            warn "Skipped. Some pmgr commands may fail (e.g. \`pmgr test\`)."
        fi
    else
        ok "All Python dependencies present"
    fi
else
    warn "Skipping dependency check (--no-deps)"
fi

# ── 备份已存在的安装 ────────────────────────────────────────────────
mkdir -p "$PLUGIN_DIR"

if [ -d "$DEST_DIR" ]; then
    if [ "$FORCE" -eq 1 ]; then
        BACKUP="$DEST_DIR.backup.$(date +%Y%m%d-%H%M%S)"
        mv "$DEST_DIR" "$BACKUP"
        ok "Existing installation backed up to: $BACKUP"
    else
        warn "pmgr is already installed at: $DEST_DIR"
        read -r -p "Overwrite? Existing files will be backed up. [y/N]: " ans
        if [[ ! "$ans" =~ ^[Yy]$ ]]; then
            die "Aborted by user"
        fi
        BACKUP="$DEST_DIR.backup.$(date +%Y%m%d-%H%M%S)"
        mv "$DEST_DIR" "$BACKUP"
        ok "Existing installation backed up to: $BACKUP"
    fi
fi

# ── 复制插件 ────────────────────────────────────────────────────────
log "Installing plugin to: $DEST_DIR"
cp -R "$SRC_DIR" "$DEST_DIR"
ok "Files copied"

# ── 验证 ────────────────────────────────────────────────────────────
log "Verifying installation..."
MISSING_FILES=()
for f in plugin.yaml __init__.py i18n.py core.py commands.py test_conn.py cli.py; do
    [ -f "$DEST_DIR/$f" ] || MISSING_FILES+=("$f")
done
if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    die "Installation incomplete; missing: ${MISSING_FILES[*]}"
fi
ok "All files present"

# ── Gatekeeper 提示（若插件位于下载目录）───────────────────────────
case "$SCRIPT_DIR" in
    "$HOME/Downloads"*|"$HOME/Desktop"*)
        warn "You installed from $SCRIPT_DIR."
        warn "macOS Gatekeeper may quarantine files in Downloads/Desktop."
        warn "If Hermes fails to load the plugin, run:"
        warn "  xattr -dr com.apple.quarantine \"$DEST_DIR\""
        ;;
esac

# ── 完成 ────────────────────────────────────────────────────────────
cat <<EOF

${BOLD}${GREEN}✓ pmgr installed successfully on macOS${RESET}

  Plugin dir:  $DEST_DIR
  Hermes home: $HERMES_HOME
  Python:      $PYTHON_BIN ($PY_VER)

Next steps:
  1. Restart Hermes
  2. Run:  hermes pmgr list
  3. Run:  hermes pmgr doctor

Docs:  https://github.com/metaone01/hermes-profile-manager
EOF