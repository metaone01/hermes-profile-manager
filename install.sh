#!/usr/bin/env bash
# pmgr installer for Linux / macOS
# Usage: ./install.sh [--force] [--uninstall] [--no-deps]
#        curl -fsSL .../install.sh | bash
#        curl -fsSL .../install.sh | bash -s -- --force
#
# 从 stdin 执行（curl | bash）时没有脚本路径，会改为下载源码压缩包。

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

# 交互提问：curl | bash 时 stdin 是脚本本身，直接 read 会吞掉后续脚本内容，
# 因此优先从 /dev/tty 读取；没有控制终端时退回非交互默认值。
# 注意：prompt 不能用 `read -p`（bash 仅在 fd 0 是终端时才打印它），改为自己写 stderr。
# 用法：ask "<prompt with default hint>" <tty-default> [<non-tty-default>]
ask() {
    local prompt="$1" def="$2" fallback="${3:-$2}" ans=""
    # 会话没有控制终端时 /dev/tty 打开失败；把整组重定向包起来才能在打开前静默报错
    if { exec 3</dev/tty; } 2>/dev/null; then
        printf '%s' "$prompt" >&2
        read -r ans <&3 || ans=""
        exec 3<&-
        printf '%s' "${ans:-$def}"
    else
        warn "No controlling terminal; using default '${fallback}' for: ${prompt}"
        printf '%s' "$fallback"
    fi
}

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
pmgr installer

Usage: ./install.sh [options]

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

# ── 定位 Hermes 插件目录 ────────────────────────────────────────────
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

# ── 定位源码 ────────────────────────────────────────────────────────
# 直接执行（./install.sh）时源码就在脚本旁边；
# 管道执行（curl | bash）时 $BASH_SOURCE 为空、也没有本地仓库，改为下载源码包。
REPO_SLUG="${PMGR_REPO:-metaone01/hermes-profile-manager}"
REPO_REF="${PMGR_REF:-main}"
TARBALL_URL="${PMGR_TARBALL_URL:-https://codeload.github.com/$REPO_SLUG/tar.gz/refs/heads/$REPO_REF}"
PLUGIN_FILES=(plugin.yaml __init__.py i18n.py core.py commands.py test_conn.py cli.py)

TMP_DIR=""
cleanup() { if [ -n "$TMP_DIR" ]; then rm -rf "$TMP_DIR"; fi; }
trap cleanup EXIT INT TERM

download() {  # download <url> <dest>
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1"
    else
        die "curl or wget is required to download the plugin source"
    fi
}

SELF="${BASH_SOURCE[0]:-}"
SELF_DIR=""
if [ -n "$SELF" ]; then
    SELF_DIR="$(cd "$(dirname "$SELF")" && pwd)"
fi

if [ -n "$SELF_DIR" ] && [ -d "$SELF_DIR/pmgr" ]; then
    SRC_DIR="$SELF_DIR/pmgr"
    log "Using local source: $SRC_DIR"
else
    log "Downloading source: $REPO_SLUG@$REPO_REF"
    command -v tar >/dev/null 2>&1 || die "tar is required for piped installation"
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pmgr-install.XXXXXX")"
    download "$TARBALL_URL" "$TMP_DIR/src.tar.gz" || die "Download failed: $TARBALL_URL"
    tar -xzf "$TMP_DIR/src.tar.gz" -C "$TMP_DIR" || die "Extract failed: $TARBALL_URL"
    # 压缩包解出单个顶层目录（<repo>-<ref>/），用 glob 循环取它：
    # 空匹配时更可预期，也避开 bash 3.2（macOS 自带）对数组展开的差异
    SRC_DIR=""
    for d in "$TMP_DIR"/*/; do
        if [ -d "${d}pmgr" ]; then
            SRC_DIR="${d}pmgr"
            break
        fi
    done
    [ -n "$SRC_DIR" ] || die "pmgr/ not found in downloaded archive from $TARBALL_URL"
    ok "Source ready: $SRC_DIR"
fi

# ── Python 检测 ─────────────────────────────────────────────────────
PYTHON_BIN=""
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
        PYTHON_BIN="$candidate"
        break
    fi
done
[ -n "$PYTHON_BIN" ] || die "Python 3.9+ is required but not found in PATH"

PY_VER=$("$PYTHON_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])')
PY_MAJOR=${PY_VER%%.*}
PY_MINOR=${PY_VER##*.}
if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 9 ]; }; then
    die "Python 3.9+ required, found $PY_VER"
fi
ok "Python $PY_VER detected ($PYTHON_BIN)"

# ── 依赖安装 ────────────────────────────────────────────────────────
# PyYAML 必需（缺失则安装无意义）；httpx 可选（README 中 test 命令缺失时回退 urllib）。
# 可选依赖装不上不应该中断安装本身。
if [ "$NO_DEPS" -eq 0 ]; then
    log "Checking Python dependencies..."
    check_deps() {  # check_deps <module>... -> prints missing module names
        "$PYTHON_BIN" - "$@" <<'PY'
import importlib.util as u, sys
print(" ".join(m for m in sys.argv[1:] if u.find_spec(m) is None))
PY
    }

    MISSING_REQ=$(check_deps yaml)
    MISSING_OPT=$(check_deps httpx)

    if [ -n "$MISSING_REQ" ]; then
        warn "Missing required package(s): PyYAML"
        ans="$(ask "Install now with pip? [Y/n]: " Y)"
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            "$PYTHON_BIN" -m pip install --user PyYAML \
                || die "pip install failed; run manually: $PYTHON_BIN -m pip install PyYAML"
            ok "PyYAML installed"
        else
            warn "Skipped; pmgr requires PyYAML to run."
        fi
    else
        ok "Required dependency present (PyYAML)"
    fi

    if [ -n "$MISSING_OPT" ]; then
        warn "Missing optional package: httpx (only 'pmgr test' needs it; falls back to urllib)"
        ans="$(ask "Install httpx now with pip? [Y/n]: " Y)"
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            # 可选依赖装不上只警告，不中断安装（如 PEP 668 externally-managed 环境）
            if "$PYTHON_BIN" -m pip install --user httpx; then
                ok "httpx installed"
            else
                warn "Could not install httpx; continuing anyway."
                warn "Install manually if needed: $PYTHON_BIN -m pip install httpx"
            fi
        else
            warn "Skipped httpx."
        fi
    else
        ok "Optional dependency present (httpx)"
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
        ans="$(ask "Overwrite? Existing files will be backed up. [y/N]: " N)"
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
for f in "${PLUGIN_FILES[@]}"; do
    [ -f "$DEST_DIR/$f" ] || MISSING_FILES+=("$f")
done
if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    die "Installation incomplete; missing: ${MISSING_FILES[*]}"
fi
ok "All files present"

# ── 完成 ────────────────────────────────────────────────────────────
cat <<EOF

${BOLD}${GREEN}✓ pmgr installed successfully${RESET}

  Plugin dir:  $DEST_DIR
  Hermes home: $HERMES_HOME

Next steps:
  1. Restart Hermes
  2. Run:  hermes pmgr list
  3. Run:  hermes pmgr doctor

Docs:  https://github.com/metaone01/hermes-profile-manager
EOF