"""pmgr 核心：路径、YAML/env IO、profile 匹配、provider 辅助。"""

import os
import re
from pathlib import Path

import yaml

from .i18n import t


# ═════════════════════════════════════════════════════════════════
#  路径
# ═════════════════════════════════════════════════════════════════

HERMES_HOME = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes"))
CONFIG_PATH = HERMES_HOME / "config.yaml"
ENV_PATH = HERMES_HOME / ".env"
PROFILES_DIR = HERMES_HOME / "profiles"
BACKUP_DIR = HERMES_HOME / ".backup"


def profile_config_path(name: str) -> Path:
    if name == "default":
        return CONFIG_PATH
    return PROFILES_DIR / name / "config.yaml"


def profile_env_path(name: str) -> Path:
    if name == "default":
        return ENV_PATH
    return PROFILES_DIR / name / ".env"


# ═════════════════════════════════════════════════════════════════
#  YAML / ENV IO
# ═════════════════════════════════════════════════════════════════

def load_yaml(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except Exception as exc:
        print(t("warn_parse", path=path, exc=exc))
        return {}


def save_yaml(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        yaml.dump(data, f, allow_unicode=True, sort_keys=False,
                  default_flow_style=False)


def load_env(path: Path) -> dict:
    result = {}
    if not path.exists():
        return result
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            result[k.strip()] = v.strip().strip('"').strip("'")
    return result


def save_env(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = []
    if path.exists():
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()

    keys_in_data = set(data.keys())
    new_lines, written = [], set()
    for line in lines:
        s = line.strip()
        if s and not s.startswith("#") and "=" in s:
            k = s.split("=", 1)[0].strip()
            if k in keys_in_data:
                new_lines.append(f"{k}={data[k]}\n")
                written.add(k)
                continue
        new_lines.append(line)
    for k, v in data.items():
        if k not in written:
            new_lines.append(f"{k}={v}\n")
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(new_lines)


# ═════════════════════════════════════════════════════════════════
#  Profile 列表与匹配
# ═════════════════════════════════════════════════════════════════

def list_profiles() -> list:
    profiles = {"default"}
    if PROFILES_DIR.is_dir():
        for entry in PROFILES_DIR.iterdir():
            if entry.is_dir() and (entry / "config.yaml").exists():
                profiles.add(entry.name)
    return sorted(profiles)


def match_profiles(patterns: list) -> list:
    """正则/精确匹配；空列表 → 全部。"""
    if not patterns:
        return list_profiles()
    all_names = list_profiles()
    matched = []
    for pat in patterns:
        if pat in all_names:
            if pat not in matched:
                matched.append(pat)
            continue
        try:
            rx = re.compile(pat)
        except re.error:
            continue
        for name in all_names:
            if rx.search(name) and name not in matched:
                matched.append(name)
    return matched


# ═════════════════════════════════════════════════════════════════
#  Provider 辅助
# ═════════════════════════════════════════════════════════════════

_PROVIDER_ENV_MAP = {
    "openrouter": "OPENROUTER_API_KEY",
    "openai": "OPENAI_API_KEY",
    "anthropic": "ANTHROPIC_API_KEY",
    "google": "GOOGLE_API_KEY",
    "gemini": "GEMINI_API_KEY",
    "nous": "NOUS_API_KEY",
    "zai": "GLM_API_KEY",
    "kimi-coding": "KIMI_API_KEY",
    "minimax": "MINIMAX_API_KEY",
    "minimax-cn": "MINIMAX_CN_API_KEY",
    "kilocode": "KILOCODE_API_KEY",
    "opencode-zen": "OPENCODE_ZEN_API_KEY",
    "opencode-go": "OPENCODE_GO_API_KEY",
    "ai-gateway": "AI_GATEWAY_API_KEY",
    "alibaba": "DASHSCOPE_API_KEY",
    "copilot": "COPILOT_GITHUB_TOKEN",
    "copilot-acp": "COPILOT_GITHUB_TOKEN",
    "huggingface": "HF_TOKEN",
}


def provider_env_key(slug: str) -> str:
    if slug in _PROVIDER_ENV_MAP:
        return _PROVIDER_ENV_MAP[slug]
    normalized = re.sub(r"[^A-Za-z0-9]+", "_", slug).upper().strip("_")
    return f"{normalized}_API_KEY"


def parse_provider_id(raw: str) -> tuple:
    if not raw or "." not in raw:
        raise ValueError(t("err_id_format"))
    slug, _, model = raw.partition(".")
    slug, model = slug.strip(), model.strip()
    if not slug or not model:
        raise ValueError(t("err_id_format"))
    return slug, model


def get_providers_block(profile: str) -> dict:
    return load_yaml(profile_config_path(profile)).get("providers", {}) or {}


def get_custom_providers(profile: str) -> list:
    cp = load_yaml(profile_config_path(profile)).get("custom_providers")
    return cp if isinstance(cp, list) else []


def provider_exists(profile: str, slug: str) -> bool:
    if slug in get_providers_block(profile):
        return True
    for entry in get_custom_providers(profile):
        if entry.get("name") == slug or entry.get("slug") == slug:
            return True
    return False


def collect_providers() -> list:
    """收集所有 profile 中出现的 provider slug。"""
    seen = set()
    for name in list_profiles():
        p = (load_yaml(profile_config_path(name)).get("model", {}) or {}).get("provider")
        if p:
            seen.add(p)
        for k in get_providers_block(name).keys():
            if isinstance(k, str) and k.strip():
                seen.add(k.strip())
    return sorted(seen)


def collect_models_for_provider(slug: str) -> list:
    seen = set()
    for name in list_profiles():
        cfg = load_yaml(profile_config_path(name))
        if (cfg.get("model", {}) or {}).get("provider") == slug:
            m = (cfg.get("model", {}) or {}).get("default")
            if m:
                seen.add(m)
        models = (get_providers_block(name).get(slug, {}) or {}).get("models", {})
        if isinstance(models, dict):
            seen.update(models.keys())
    return sorted(seen)


def read_model_config(profile: str) -> dict:
    return load_yaml(profile_config_path(profile)).get("model", {}) or {}


# ═════════════════════════════════════════════════════════════════
#  Masking & 通用工具
# ═════════════════════════════════════════════════════════════════

def mask_secret(s: str) -> str:
    if not s:
        return ""
    if len(s) <= 8:
        return "*" * len(s)
    return f"{s[:4]}...{s[-4:]}"


def backup_profile(name: str) -> Path:
    import shutil
    from datetime import datetime
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    dst = BACKUP_DIR / f"{name}-{ts}"
    if name == "default":
        src = HERMES_HOME
        # 只备份 config.yaml + .env，避免递归
        dst.mkdir(parents=True, exist_ok=True)
        for f in (CONFIG_PATH, ENV_PATH):
            if f.exists():
                shutil.copy2(f, dst / f.name)
    else:
        src = PROFILES_DIR / name
        if src.exists():
            shutil.copytree(src, dst)
    return dst