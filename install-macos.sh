#!/usr/bin/env bash
# pmgr installer for macOS (Homebrew-aware)
# Usage: ./install-macos.sh [--force] [--uninstall] [--no-deps]
#        curl -fsSL .../install-macos.sh | bash
#
# 从 stdin 执行（curl | bash）时会自动下载源码压缩包，因此无需本地仓库。

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
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
PLUGIN_DIR="$HERMES_HOME/plugins"
DEST_DIR="$PLUGIN_DIR/pmgr"

# ── 卸载 ────────────────────────────────────────────────────────────
if [ "$UNINSTALL" -eq 1 ]; then
    # 安装时会写 plugins.enabled，卸载时对应清掉（先用插件仍在的时机 disable，
    # 否则 key 解析不到；失败不阻断卸载本身）。
    if command -v hermes >/dev/null 2>&1; then
        HERMES_HOME="$HERMES_HOME" hermes plugins disable pmgr </dev/null >/dev/null 2>&1 \
            && ok "Disabled in $HERMES_HOME/config.yaml" || true
    fi
    if [ -d "$DEST_DIR" ]; then
        rm -rf "$DEST_DIR"
        ok "Uninstalled: $DEST_DIR"
    else
        warn "Not installed: $DEST_DIR"
    fi
    exit 0
fi

# ── 定位源码 ────────────────────────────────────────────────────────
# 直接执行时源码就在脚本旁边；管道执行（curl | bash）时 $BASH_SOURCE 为空，
# 改为下载源码包。
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
# PyYAML 必需；httpx 可选（缺失时 `pmgr test` 回退 urllib）。
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

    if [ "$IS_BREW_PY" -eq 1 ] && { [ -n "$MISSING_REQ" ] || [ -n "$MISSING_OPT" ]; }; then
        warn "Homebrew Python detected; PEP 668 may block pip install."
        cat <<EOF

Recommended (isolated install via pipx):
  brew install pipx
  pipx install pyyaml
  pipx inject pyyaml httpx

Or, install directly with pip using --break-system-packages:
  $PYTHON_BIN -m pip install --break-system-packages PyYAML httpx

EOF
    fi

    pip_install() {  # pip_install <pkg>... ; returns non-zero if all attempts fail
        "$PYTHON_BIN" -m pip install --user "$@" 2>/dev/null && return 0
        "$PYTHON_BIN" -m pip install --user --break-system-packages "$@" 2>/dev/null
    }

    if [ -n "$MISSING_REQ" ]; then
        warn "Missing required package(s): PyYAML"
        ans="$(ask "Install now with pip --user? [Y/n]: " Y)"
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            pip_install PyYAML \
                || die "pip install failed. Try: brew install pipx && pipx install pyyaml"
            ok "PyYAML installed"
        else
            warn "Skipped; pmgr requires PyYAML to run."
        fi
    else
        ok "Required dependency present (PyYAML)"
    fi

    if [ -n "$MISSING_OPT" ]; then
        warn "Missing optional package: httpx (only 'pmgr test' needs it; falls back to urllib)"
        ans="$(ask "Install httpx now with pip --user? [Y/n]: " Y)"
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            # 可选依赖装不上只警告，不中断安装（如 PEP 668 externally-managed 环境）
            if pip_install httpx; then
                ok "httpx installed"
            else
                warn "Could not install httpx; continuing anyway."
                warn "Install manually if needed: brew install pipx && pipx install httpx"
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

# 备份放到 $HERMES_HOME/backups/plugins/ 而不是 plugins/ 之内：插件目录下每个
# 含 plugin.yaml 的子目录都会被当成插件扫描，旧副本的 manifest name 同样是
# pmgr，会和刚装好的版本争同一个 key——实测是旧副本赢，升级后加载的仍是旧代码。
BACKUP_ROOT="$HERMES_HOME/backups/plugins/pmgr"

backup_existing() {
    mkdir -p "$BACKUP_ROOT"
    BACKUP="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-$$"
    while [ -e "$BACKUP" ]; do
        BACKUP="${BACKUP}_"
    done
    mv "$DEST_DIR" "$BACKUP"
    ok "Existing installation backed up to: $BACKUP"
}

# 老版本安装器把备份留在 plugins/ 里，那份副本会被当成**独立插件**扫描。实测两份
# manifest name 都是 pmgr 时同 key 竞争，旧副本胜出，于是新装的代码根本没被加载——
# 表现就是"装好了也重启了，命令还是崩/还是旧行为"。
# 因此这里直接移走，而不是只警告：留着这一份，本次安装等于没生效。
# 需要保留原地时用 PMGR_KEEP_LEGACY=1（自担风险，只会告警）。
LEGACY_MOVED=0
for stale in "$PLUGIN_DIR"/pmgr.backup.*; do
    [ -d "$stale" ] || continue
    if [ "${PMGR_KEEP_LEGACY:-0}" = "1" ]; then
        warn "Legacy copy inside the plugin dir competes for plugin key 'pmgr':"
        warn "  $stale"
        warn "  Move it out yourself:  mv \"$stale\" \"$BACKUP_ROOT/\""
        continue
    fi
    mkdir -p "$BACKUP_ROOT"
    LEGACY_DEST="$BACKUP_ROOT/legacy-$(basename "$stale")"
    while [ -e "$LEGACY_DEST" ]; do
        LEGACY_DEST="${LEGACY_DEST}_"
    done
    mv "$stale" "$LEGACY_DEST"
    LEGACY_MOVED=$((LEGACY_MOVED + 1))
    ok "Moved competing legacy copy out of the plugin dir: $LEGACY_DEST"
done
if [ "$LEGACY_MOVED" -gt 0 ]; then
    ok "Isolated $LEGACY_MOVED legacy copy/copies (they would have shadowed the new install)"
fi

if [ -d "$DEST_DIR" ]; then
    if [ "$FORCE" -eq 1 ]; then
        backup_existing
    else
        warn "pmgr is already installed at: $DEST_DIR"
        ans="$(ask "Overwrite? Existing files will be backed up. [y/N]: " N)"
        if [[ ! "$ans" =~ ^[Yy]$ ]]; then
            die "Aborted by user"
        fi
        backup_existing
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

# ── 竞争副本自查 ────────────────────────────────────────────────────
# plugins/ 下每个含 plugin.yaml 的子目录都是一个独立插件，按 manifest name 抢占同一个
# key。实测：同名的旧副本（形如 pmgr.backup.*）会在扫描中覆盖注册——`hermes pmgr`
# 实际执行的是那份旧代码，而响应测试仍然"能跑"，于是误报成功。
COMPETING=""
for d in "$PLUGIN_DIR"/*/; do
    d="${d%/}"
    [ -d "$d" ] || continue
    [ "$d" = "$DEST_DIR" ] && continue
    [ -f "$d/plugin.yaml" ] || continue
    if grep -qE "^[[:space:]]*name:[[:space:]]*[\"']?pmgr[\"']?[[:space:]]*\$" "$d/plugin.yaml"; then
        COMPETING="$d"
    fi
done
if [ -n "$COMPETING" ]; then
    warn "Another copy in the plugin dir registers the same plugin name 'pmgr':"
    warn "  $COMPETING"
    warn "  It wins the key and shadows this installation; remove or move it out."
else
    ok "No competing copy of 'pmgr' in $PLUGIN_DIR"
fi

# ── 启用插件 ────────────────────────────────────────────────────────
# 用户级插件是 opt-in：只把文件放进 plugins/ 不会加载，必须在 config.yaml 的
# plugins.enabled 里登记（否则 `hermes pmgr` 报 invalid choice / 命令不存在）。
# 卸载时对应撤销。pmgr 只提供 CLI 子命令，不需要内建工具替换权限，故显式拒绝。
ENABLED=0
if [ "${PMGR_NO_ENABLE:-0}" = "1" ]; then
    warn "Skipping 'hermes plugins enable' (PMGR_NO_ENABLE=1)"
elif ! command -v hermes >/dev/null 2>&1; then
    warn "'hermes' not found on PATH; skipping plugin activation"
else
    if HERMES_HOME="$HERMES_HOME" hermes plugins enable pmgr --no-allow-tool-override \
            </dev/null >/dev/null 2>&1; then
        ok "Plugin enabled in $HERMES_HOME/config.yaml"
        ENABLED=1
    else
        warn "Could not enable the plugin automatically."
    fi
fi

# 回读真实状态：enable 写的是哪个 home，就用哪个 home 验证。
# 注意 `hermes plugins show pmgr` 被同名副本遮蔽时仍可能报出新版本号，所以不能只信
# 版本号——以竞争副本自查为准。
VERIFY_HOME="$HERMES_HOME"
VERIFY_NOTE=""
if [ "$ENABLED" -eq 1 ] && [ -n "$COMPETING" ]; then
    warn "Activation NOT verified: '$COMPETING' still registers the name 'pmgr'."
    ENABLED=0
    VERIFY_NOTE="blocked by competing copy"
elif [ "$ENABLED" -eq 1 ] && command -v hermes >/dev/null 2>&1; then
    if HERMES_HOME="$VERIFY_HOME" hermes pmgr list >/dev/null 2>&1; then
        ok "Verified: 'hermes pmgr' responds"
    else
        warn "'hermes pmgr' did not respond in $VERIFY_HOME; check 'hermes pmgr --help' manually"
        ENABLED=0
    fi
fi

# ── Gatekeeper 提示（若插件位于下载目录）───────────────────────────
case "$SELF_DIR" in
    "$HOME/Downloads"*|"$HOME/Desktop"*)
        warn "You installed from $SELF_DIR."
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
  Activated:   $([ "$ENABLED" -eq 1 ] && printf 'yes' || printf 'NO (see warnings above)')${VERIFY_NOTE:+ ($VERIFY_NOTE)}

Next steps:
  1. Restart Hermes
  2. Run:  hermes pmgr list
  3. Run:  hermes pmgr doctor

Docs:  https://github.com/metaone01/hermes-profile-manager
EOF