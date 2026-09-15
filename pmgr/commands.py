"""pmgr 所有非 test 命令实现。"""

import re
import shutil
import sys
from pathlib import Path

import yaml

from .core import (
    HERMES_HOME, CONFIG_PATH, ENV_PATH, PROFILES_DIR,
    profile_config_path, profile_env_path,
    load_yaml, save_yaml, load_env, save_env,
    list_profiles, match_profiles,
    provider_env_key, parse_provider_id, provider_exists,
    get_providers_block, get_custom_providers,
    collect_providers, collect_models_for_provider,
    read_model_config, mask_secret, backup_profile,
)
from .i18n import t


# ═════════════════════════════════════════════════════════════════
#  通用预览 / 确认
# ═════════════════════════════════════════════════════════════════

def confirm(prompt_key: str = "confirm_write") -> bool:
    raw = input(t(prompt_key)).strip().lower()
    return raw in ("y", "yes", "是")


def dry_run_then_apply(changes: list, apply_fn,
                       line_renderer=None,
                       confirm_key: str = "confirm_write") -> None:
    """通用 dry-run → 确认 → 应用。"""
    if not changes:
        print(t("preview_empty"))
        print(t("no_op_done"))
        return
    print(t("preview_header"))
    for c in changes:
        if line_renderer:
            line_renderer(c)
        else:
            print(f"  • {c}")
    print(t("preview_footer"))
    if not confirm(confirm_key):
        print(t("cancelled"))
        return
    for c in changes:
        apply_fn(c)
    print(t("done_count", n=len(changes)))


# ═════════════════════════════════════════════════════════════════
#  交互式选择器
# ═════════════════════════════════════════════════════════════════

def prompt_choice(prompt: str, options: list, default_index: int = 0) -> str:
    print(f"\n{prompt}")
    for i, opt in enumerate(options):
        marker = "▸" if i == default_index else " "
        print(f"  {marker} [{i + 1}] {opt}")
    raw = input(t("prompt_choice")).strip()
    if not raw:
        return options[default_index]
    if raw.isdigit():
        idx = int(raw) - 1
        if 0 <= idx < len(options):
            return options[idx]
    for opt in options:
        if opt.lower() == raw.lower():
            return opt
    print(t("invalid_choice", raw=raw, default=options[default_index]))
    return options[default_index]


def prompt_multi_choice(prompt: str, options: list, defaults: list = None) -> list:
    defaults = [d for d in (defaults or []) if d in options]
    print(f"\n{prompt}")
    for i, opt in enumerate(options):
        mark = "x" if opt in defaults else " "
        print(f"  [{mark}] [{i + 1}] {opt}")
    print(f"        [a] {t('select_all')}")
    raw = input(t("prompt_multi")).strip()
    if not raw:
        return defaults
    if raw.lower() in ("a", "all", "*"):
        return list(options)
    selected = []
    for tok in re.split(r"[,\s]+", raw):
        if not tok:
            continue
        if tok.isdigit():
            idx = int(tok) - 1
            if 0 <= idx < len(options) and options[idx] not in selected:
                selected.append(options[idx])
        else:
            for opt in options:
                if opt.lower() == tok.lower() and opt not in selected:
                    selected.append(opt)
                    break
    if not selected:
        print(t("invalid_multi"))
    return selected


def prompt_text(prompt: str, default: str = "") -> str:
    if default:
        raw = input(t("prompt_text_default", prompt=prompt, default=default)).strip()
        return raw or default
    return input(t("prompt_text", prompt=prompt)).strip()


# ═════════════════════════════════════════════════════════════════
#  provider 元数据 upsert / 删除
# ═════════════════════════════════════════════════════════════════

def upsert_provider_meta(profile: str, slug: str, model: str,
                         base_url: str = None, context_length: int = None,
                         remove: bool = False) -> None:
    path = profile_config_path(profile)
    cfg = load_yaml(path)
    providers = cfg.setdefault("providers", {})

    if remove:
        providers.pop(slug, None)
        cp = cfg.get("custom_providers")
        if isinstance(cp, list):
            cfg["custom_providers"] = [
                e for e in cp
                if e.get("name") != slug and e.get("slug") != slug
            ]
    else:
        block = providers.setdefault(slug, {})
        block.setdefault("name", slug)
        if base_url:
            block["base_url"] = base_url
        block["api_key"] = f"${{{provider_env_key(slug)}}}"
        block.setdefault("default_model", model)
        models = block.setdefault("models", {})
        entry = models.setdefault(model, {})
        if context_length:
            entry["context_length"] = context_length
    save_yaml(path, cfg)


def switch_model_in_profile(profile: str, slug: str, model: str) -> None:
    path = profile_config_path(profile)
    cfg = load_yaml(path)
    cfg.setdefault("model", {})
    cfg["model"]["provider"] = slug
    cfg["model"]["default"] = model
    save_yaml(path, cfg)


def write_api_key(profile: str, slug: str, api_key: str) -> None:
    env_path = profile_env_path(profile)
    env_data = load_env(env_path)
    env_data[provider_env_key(slug)] = api_key
    save_env(env_path, env_data)


def delete_api_key(profile: str, slug: str) -> None:
    env_path = profile_env_path(profile)
    if not env_path.exists():
        return
    env_data = load_env(env_path)
    key = provider_env_key(slug)
    if key in env_data:
        del env_data[key]
        save_env(env_path, env_data)


# ═════════════════════════════════════════════════════════════════
#  add / remove / modify
# ═════════════════════════════════════════════════════════════════

def plan_add(slug, model, api_key, profiles, base_url=None, context_length=None):
    matched = match_profiles(profiles)
    if not matched:
        print(t("err_no_profile_match", patterns=profiles))
        return []
    changes = []
    for p in matched:
        if provider_exists(p, slug):
            print(t("err_provider_exists", slug=slug))
            continue
        changes.append({"action": "add", "profile": p, "slug": slug,
                        "model": model, "api_key": api_key,
                        "env_key": provider_env_key(slug),
                        "base_url": base_url, "context_length": context_length})
    return changes


def apply_add(c: dict) -> None:
    upsert_provider_meta(c["profile"], c["slug"], c["model"],
                         base_url=c.get("base_url"),
                         context_length=c.get("context_length"))
    write_api_key(c["profile"], c["slug"], c["api_key"])
    switch_model_in_profile(c["profile"], c["slug"], c["model"])


def plan_remove(slug, model, profiles):
    matched = match_profiles(profiles)
    if not matched:
        print(t("err_no_profile_match", patterns=profiles))
        return []
    changes = []
    for p in matched:
        if not provider_exists(p, slug):
            print(t("err_provider_missing", slug=slug))
            continue
        changes.append({"action": "remove", "profile": p, "slug": slug, "model": model})
    return changes


def apply_remove(c: dict) -> None:
    p, slug, model = c["profile"], c["slug"], c["model"]
    upsert_provider_meta(p, slug, model, remove=True)
    # 回退 model 选择
    cfg = load_yaml(profile_config_path(p))
    mc = cfg.get("model", {})
    if mc.get("provider") == slug and mc.get("default") == model:
        default_cfg = load_yaml(CONFIG_PATH).get("model", {}) if p != "default" else {}
        mc["provider"] = default_cfg.get("provider", "auto")
        mc["default"] = default_cfg.get("default", "")
        cfg["model"] = mc
        save_yaml(profile_config_path(p), cfg)
    delete_api_key(p, slug)


def plan_modify(slug, model, api_key=None, profiles=None,
                base_url=None, context_length=None):
    matched = match_profiles(profiles or [])
    if not matched:
        print(t("err_no_profile_match", patterns=profiles or []))
        return []
    changes = []
    for p in matched:
        if not provider_exists(p, slug):
            print(t("err_provider_missing", slug=slug))
            continue
        changes.append({"action": "modify", "profile": p, "slug": slug,
                        "model": model, "api_key": api_key,
                        "env_key": provider_env_key(slug) if api_key else None,
                        "base_url": base_url, "context_length": context_length})
    return changes


def apply_modify(c: dict) -> None:
    upsert_provider_meta(c["profile"], c["slug"], c["model"],
                         base_url=c.get("base_url"),
                         context_length=c.get("context_length"))
    if c.get("api_key"):
        write_api_key(c["profile"], c["slug"], c["api_key"])
    switch_model_in_profile(c["profile"], c["slug"], c["model"])


# ═════════════════════════════════════════════════════════════════
#  set
# ═════════════════════════════════════════════════════════════════

_WRITABLE_PREFIXES = ("model.", "providers.", "custom_providers.")


def _path_get(cfg: dict, key: str):
    node = cfg
    for part in key.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def _path_set(cfg: dict, key: str, value) -> None:
    parts = key.split(".")
    node = cfg
    for part in parts[:-1]:
        node = node.setdefault(part, {})
    node[parts[-1]] = value


def plan_set(profile: str, key: str, value: str) -> list:
    if not any(key.startswith(p) for p in _WRITABLE_PREFIXES):
        print(t("set_invalid_path", path=key))
        return []
    cfg = load_yaml(profile_config_path(profile))
    old = _path_get(cfg, key)
    # 尝试把 value 解析为 int / bool / null
    v = value
    if value.lower() in ("true", "false"):
        v = value.lower() == "true"
    elif value.lower() in ("null", "none", "~"):
        v = None
    else:
        try:
            v = int(value)
        except ValueError:
            pass
    return [{"action": "set", "profile": profile, "key": key,
             "old": old, "new": v}]


def apply_set(c: dict) -> None:
    path = profile_config_path(c["profile"])
    cfg = load_yaml(path)
    _path_set(cfg, c["key"], c["new"])
    save_yaml(path, cfg)


# ═════════════════════════════════════════════════════════════════
#  list / show
# ═════════════════════════════════════════════════════════════════

def cmd_list(show_providers=False, show_models=False) -> None:
    profiles = list_profiles()
    if not profiles:
        print(t("list_empty"))
        return

    if show_providers:
        print(t("list_providers_header"))
        agg = {}
        for p in profiles:
            for slug in get_providers_block(p).keys():
                agg.setdefault(slug, []).append(p)
        for slug, users in sorted(agg.items()):
            print(f"{slug:<20} {', '.join(users)}")
        return

    if show_models:
        print(t("list_models_header"))
        seen = set()
        for p in profiles:
            mc = read_model_config(p)
            m, slug = mc.get("default", ""), mc.get("provider", "")
            if m and (m, slug) not in seen:
                seen.add((m, slug))
                print(f"{m:<34} {slug}")
        return

    print(t("list_header"))
    for p in profiles:
        mc = read_model_config(p)
        print(f"{p:<20} {mc.get('provider', ''):<20} {mc.get('default', '')}")


def cmd_show(profile: str) -> None:
    cfg_path = profile_config_path(profile)
    cfg = load_yaml(cfg_path)
    env_path = profile_env_path(profile)
    env = load_env(env_path)

    print(f"\nProfile:  {profile}")
    print(t("show_path", path=cfg_path))

    mc = cfg.get("model", {}) or {}
    print(t("show_model_section"))
    print(t("show_model_provider", value=mc.get("provider", t("none"))))
    print(t("show_model_default", value=mc.get("default", t("none"))))

    provs = cfg.get("providers", {}) or {}
    if provs:
        print(t("show_providers_section"))
        for slug, block in provs.items():
            print(t("show_provider_line", slug=slug))
            env_key = provider_env_key(slug)
            has_key = env_key in env
            marker = t("env_set_marker") if has_key else t("env_missing_marker")
            print(t("show_provider_api_key",
                    value=f"${{{env_key}}}  [{marker}]"))
            if block.get("base_url"):
                print(t("show_provider_base_url", value=block["base_url"]))
            models = block.get("models", {}) or {}
            print(t("show_provider_models", value=", ".join(models.keys()) or t("none")))

    if env:
        print(t("show_env_section", path=env_path))
        for k, v in env.items():
            print(f"  {k} = {mask_secret(v)}")


# ═════════════════════════════════════════════════════════════════
#  doctor
# ═════════════════════════════════════════════════════════════════

def cmd_doctor() -> int:
    print(t("doctor_header"))
    errors = warnings = 0
    profiles = list_profiles()

    # default 检查
    default_mc = read_model_config("default")
    if not default_mc.get("default"):
        print(t("doctor_error", msg=t("doctor_no_default")))
        errors += 1

    for p in profiles:
        mc = read_model_config(p)
        slug = mc.get("provider")
        model = mc.get("default")

        if not model:
            print(t("doctor_warn", msg=t("doctor_missing_model", profile=p)))
            warnings += 1
            continue
        if not slug:
            continue

        # provider 是否定义
        if slug != "auto" and not provider_exists(p, slug):
            print(t("doctor_error",
                    msg=t("doctor_missing_provider", profile=p, slug=slug)))
            errors += 1
            continue

        # API key
        env_key = provider_env_key(slug)
        if slug != "auto" and env_key not in load_env(profile_env_path(p)):
            print(t("doctor_error",
                    msg=t("doctor_missing_key", profile=p, env_key=env_key, slug=slug)))
            errors += 1

        # provider 无 model
        block = get_providers_block(p).get(slug, {})
        if isinstance(block, dict) and not block.get("models"):
            print(t("doctor_warn",
                    msg=t("doctor_orphan_provider", profile=p, slug=slug)))
            warnings += 1

    if errors == 0 and warnings == 0:
        print(t("doctor_all_ok"))
    else:
        print(t("doctor_summary", errors=errors, warnings=warnings))
    return 1 if errors else 0


# ═════════════════════════════════════════════════════════════════
#  diff
# ═════════════════════════════════════════════════════════════════

def _flatten(d: dict, prefix: str = "") -> dict:
    out = {}
    for k, v in (d or {}).items():
        key = f"{prefix}{k}"
        if isinstance(v, dict):
            out.update(_flatten(v, f"{key}."))
        else:
            out[key] = v
    return out


def cmd_diff(a: str, b: str) -> None:
    print(t("diff_header", a=a, b=b))
    fa = _flatten(load_yaml(profile_config_path(a)))
    fb = _flatten(load_yaml(profile_config_path(b)))

    keys = sorted(set(fa) | set(fb))
    diffs = 0
    for k in keys:
        va, vb = fa.get(k), fb.get(k)
        if va == vb:
            continue
        diffs += 1
        if va is None:
            print(f"  + {k}: {vb}")
        elif vb is None:
            print(f"  - {k}: {va}")
        else:
            print(f"  ~ {k}: {va}  →  {vb}")
    if not diffs:
        print(t("diff_identical"))


# ═════════════════════════════════════════════════════════════════
#  scan
# ═════════════════════════════════════════════════════════════════

def cmd_scan(root: Path = None) -> None:
    root = Path(root) if root else HERMES_HOME
    print(t("scan_header", root=root))
    found = False
    for path in root.rglob("*.yaml"):
        try:
            cfg = load_yaml(path)
        except Exception:
            continue
        provs = cfg.get("providers")
        if isinstance(provs, dict) and provs:
            found = True
            print(t("scan_found", path=path, kind="providers",
                    slugs=", ".join(provs.keys())))
        cp = cfg.get("custom_providers")
        if isinstance(cp, list) and cp:
            names = [e.get("name", "?") for e in cp if isinstance(e, dict)]
            found = True
            print(t("scan_found", path=path, kind="custom_providers",
                    slugs=", ".join(names)))
    # yml
    for path in root.rglob("*.yml"):
        try:
            cfg = load_yaml(path)
        except Exception:
            continue
        provs = cfg.get("providers")
        if isinstance(provs, dict) and provs:
            found = True
            print(t("scan_found", path=path, kind="providers",
                    slugs=", ".join(provs.keys())))
    if not found:
        print(t("scan_none"))


# ═════════════════════════════════════════════════════════════════
#  create / rename / delete / copy
# ═════════════════════════════════════════════════════════════════

def plan_create(name: str, source: str = None, with_env: bool = False) -> list:
    if name == "default":
        print(t("create_exists", name=name))
        return []
    if (PROFILES_DIR / name).exists():
        print(t("create_exists", name=name))
        return []
    if source and source != "default" and not (PROFILES_DIR / source).exists():
        print(t("create_src_missing", name=source))
        return []
    return [{"action": "create", "profile": name,
             "source": source, "with_env": with_env}]


def apply_create(c: dict) -> None:
    name = c["profile"]
    dst = PROFILES_DIR / name
    dst.mkdir(parents=True, exist_ok=True)
    src = c.get("source")
    if src:
        src_cfg = profile_config_path(src)
        if src_cfg.exists():
            save_yaml(dst / "config.yaml", load_yaml(src_cfg))
        if c.get("with_env"):
            src_env = profile_env_path(src)
            if src_env.exists():
                save_env(dst / ".env", load_env(src_env))
    else:
        save_yaml(dst / "config.yaml", {"model": {"provider": "auto", "default": ""}})


def plan_rename(old: str, new: str) -> list:
    if old == "default":
        print("[error] Cannot rename 'default'.")
        return []
    if not (PROFILES_DIR / old).exists():
        print(t("rename_src_missing", name=old))
        return []
    if (PROFILES_DIR / new).exists():
        print(t("rename_exists", name=new))
        return []
    return [{"action": "rename", "old": old, "new": new}]


def apply_rename(c: dict) -> None:
    src = PROFILES_DIR / c["old"]
    dst = PROFILES_DIR / c["new"]
    if src.exists():
        src.rename(dst)


def plan_delete(name: str, keep_env: bool = False, do_backup: bool = True) -> list:
    if name == "default":
        print("[error] Cannot delete 'default'.")
        return []
    if not (PROFILES_DIR / name).exists():
        print(t("rename_src_missing", name=name))
        return []
    return [{"action": "delete", "profile": name,
             "keep_env": keep_env, "backup": do_backup}]


def apply_delete(c: dict) -> None:
    name = c["profile"]
    path = PROFILES_DIR / name
    if c.get("backup"):
        backup_profile(name)
    if c.get("keep_env"):
        # 删除除 .env 之外的所有内容
        for child in path.iterdir():
            if child.name == ".env":
                continue
            if child.is_dir():
                shutil.rmtree(child)
            else:
                child.unlink()
    else:
        shutil.rmtree(path, ignore_errors=True)


def plan_copy(src: str, dst: str, with_env: bool = False) -> list:
    if not (PROFILES_DIR / src).exists() and src != "default":
        print(t("create_src_missing", name=src))
        return []
    if (PROFILES_DIR / dst).exists():
        print(t("create_exists", name=dst))
        return []
    return [{"action": "copy", "src": src, "dst": dst, "with_env": with_env}]


def apply_copy(c: dict) -> None:
    src_path = (CONFIG_PATH if c["src"] == "default"
                else PROFILES_DIR / c["src"] / "config.yaml")
    dst_dir = PROFILES_DIR / c["dst"]
    dst_dir.mkdir(parents=True, exist_ok=True)
    if src_path.exists():
        save_yaml(dst_dir / "config.yaml", load_yaml(src_path))
    if c.get("with_env"):
        src_env = (ENV_PATH if c["src"] == "default"
                   else PROFILES_DIR / c["src"] / ".env")
        if src_env.exists():
            save_env(dst_dir / ".env", load_env(src_env))
    print(t("copy_done", src=c["src"], dst=c["dst"]))


# ═════════════════════════════════════════════════════════════════
#  export / import
# ═════════════════════════════════════════════════════════════════

def cmd_export(patterns: list, with_env: bool = False,
               plaintext: bool = False) -> str:
    profiles = match_profiles(patterns) if patterns else list_profiles()
    out = {"version": 1, "profiles": {}}
    for p in profiles:
        cfg = load_yaml(profile_config_path(p))
        entry = {"config": cfg}
        if with_env:
            env = load_env(profile_env_path(p))
            if plaintext:
                entry["env"] = env
            else:
                entry["env"] = {k: "***" for k in env}
        out["profiles"][p] = entry
    return yaml.dump(out, allow_unicode=True, sort_keys=False,
                     default_flow_style=False)


def plan_import(path: Path, no_overwrite: bool = False) -> list:
    if not path.exists():
        print(f"[error] File not found: {path}")
        return []
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception:
        print(t("import_bad_format"))
        return []
    if "profiles" not in data or not isinstance(data["profiles"], dict):
        print(t("import_bad_format"))
        return []
    changes = []
    for name, entry in data["profiles"].items():
        if no_overwrite and (name == "default" or (PROFILES_DIR / name).exists()):
            print(t("import_conflict", name=name))
            continue
        changes.append({"action": "import", "profile": name,
                        "config": entry.get("config", {}),
                        "env": entry.get("env")})
    return changes


def apply_import(c: dict) -> None:
    name = c["profile"]
    if name == "default":
        save_yaml(CONFIG_PATH, c["config"])
        if c.get("env") is not None:
            env = load_env(ENV_PATH)
            for k, v in c["env"].items():
                if v != "***":
                    env[k] = v
            save_env(ENV_PATH, env)
        return
    dst = PROFILES_DIR / name
    dst.mkdir(parents=True, exist_ok=True)
    save_yaml(dst / "config.yaml", c["config"])
    if c.get("env") is not None:
        env = load_env(dst / ".env")
        for k, v in c["env"].items():
            if v != "***":
                env[k] = v
        save_env(dst / ".env", env)


# ═════════════════════════════════════════════════════════════════
#  env list / set / unset
# ═════════════════════════════════════════════════════════════════

def cmd_env_list(profile: str) -> None:
    env_path = profile_env_path(profile)
    env = load_env(env_path)
    print(t("show_env_section", path=env_path))
    if not env:
        print(f"  {t('none')}")
        return
    for k, v in env.items():
        print(f"  {k} = {mask_secret(v)}")


def plan_env_set(profile: str, key: str, value: str) -> list:
    return [{"action": "env_set", "profile": profile, "key": key, "value": value}]


def apply_env_set(c: dict) -> None:
    p = profile_env_path(c["profile"])
    env = load_env(p)
    env[c["key"]] = c["value"]
    save_env(p, env)


def plan_env_unset(profile: str, key: str) -> list:
    env = load_env(profile_env_path(profile))
    if key not in env:
        print(t("env_not_found", key=key, profile=profile))
        return []
    return [{"action": "env_unset", "profile": profile, "key": key}]


def apply_env_unset(c: dict) -> None:
    p = profile_env_path(c["profile"])
    env = load_env(p)
    env.pop(c["key"], None)
    save_env(p, env)