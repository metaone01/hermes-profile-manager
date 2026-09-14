"""pmgr test —— 连通性测试，执行前警告 token 消耗，执行后报告消耗。"""

import json
import time
from pathlib import Path

from .core import (
    profile_config_path, profile_env_path, load_yaml, load_env,
    provider_env_key, read_model_config, get_providers_block,
    list_profiles,
)
from .i18n import t


_DEFAULT_BASE_URLS = {
    "openrouter": "https://openrouter.ai/api/v1",
    "openai": "https://api.openai.com/v1",
    "nous": "https://inference-api.nousresearch.com/v1",
    "zai": "https://api.z.ai/api/paas/v4",
    "kimi-coding": "https://api.moonshot.cn/v1",
    "minimax": "https://api.minimax.io/v1",
    "minimax-cn": "https://api.minimaxi.com/v1",
    "huggingface": "https://api-inference.huggingface.co/v1",
    "alibaba": "https://dashscope.aliyuncs.com/compatible-mode/v1",
}


def _http_post_json(url, headers, payload, timeout=20):
    """三层回退：httpx → requests → urllib。"""
    try:
        import httpx
        with httpx.Client(timeout=timeout) as client:
            r = client.post(url, headers=headers, json=payload)
            try:
                return r.status_code, r.json() if r.content else {}
            except Exception:
                return r.status_code, {"raw": r.text[:200]}
    except ImportError:
        pass
    try:
        import requests
        r = requests.post(url, headers=headers, json=payload, timeout=timeout)
        try:
            return r.status_code, r.json() if r.content else {}
        except Exception:
            return r.status_code, {"raw": r.text[:200]}
    except ImportError:
        pass
    import urllib.request
    import urllib.error
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(),
        headers={**headers, "Content-Type": "application/json"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode()
            return resp.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            return e.code, json.loads(body) if body else {}
        except Exception:
            return e.code, {"raw": body[:200]}
    except Exception as e:
        return 0, {"error": str(e)}


def _build_request(slug: str, model: str, api_key: str,
                   base_url: str = None, context_length: int = None):
    """返回 (url, headers, payload)。"""
    # Anthropic 特殊处理
    if slug == "anthropic":
        url = "https://api.anthropic.com/v1/messages"
        headers = {
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        }
        payload = {
            "model": model,
            "max_tokens": 1,
            "messages": [{"role": "user", "content": "hi"}],
        }
        return url, headers, payload

    # OpenAI 兼容
    base = base_url or _DEFAULT_BASE_URLS.get(slug)
    if not base:
        return None, None, None
    url = f"{base.rstrip('/')}/chat/completions"
    headers = {"Authorization": f"Bearer {api_key}"}
    payload = {
        "model": model,
        "max_tokens": 1,
        "messages": [{"role": "user", "content": "hi"}],
    }
    return url, headers, payload


def _collect_targets(patterns: list) -> list:
    from .core import match_profiles
    names = match_profiles(patterns) if patterns else list_profiles()
    targets = []
    for p in names:
        mc = read_model_config(p)
        slug = mc.get("provider")
        model = mc.get("default")
        if not slug:
            targets.append({"profile": p, "skip": t("test_no_provider")})
            continue
        if not model:
            targets.append({"profile": p, "skip": t("test_no_model")})
            continue
        env = load_env(profile_env_path(p))
        env_key = provider_env_key(slug)
        api_key = env.get(env_key)
        if not api_key:
            targets.append({"profile": p, "skip": t("test_no_key")})
            continue
        block = get_providers_block(p).get(slug, {}) or {}
        targets.append({
            "profile": p, "provider": slug, "model": model,
            "api_key": api_key, "env_key": env_key,
            "base_url": block.get("base_url"),
        })
    return targets


def _test_one(target: dict) -> dict:
    url, headers, payload = _build_request(
        target["provider"], target["model"],
        target["api_key"], target.get("base_url"))
    if not url:
        return {"ok": False, "error": "no base_url known",
                "status": 0, "tokens": 0, "latency_ms": 0}

    t0 = time.time()
    status, body = _http_post_json(url, headers, payload)
    latency = int((time.time() - t0) * 1000)

    if status != 200:
        err = body.get("error") if isinstance(body, dict) else body
        if isinstance(err, dict):
            err = err.get("message") or err.get("type") or str(err)
        return {"ok": False, "status": status,
                "error": str(err)[:160] if err else "unknown error",
                "tokens": 0, "latency_ms": latency}

    usage = (body.get("usage") or {}) if isinstance(body, dict) else {}
    tokens = (usage.get("total_tokens")
              or (usage.get("input_tokens", 0) + usage.get("output_tokens", 0))
              or (usage.get("prompt_tokens", 0) + usage.get("completion_tokens", 0)))
    return {"ok": True, "status": 200, "error": None,
            "tokens": tokens or 0, "latency_ms": latency}


def cmd_test(patterns: list, auto_yes: bool = False) -> int:
    targets = _collect_targets(patterns)
    if not targets:
        print(t("no_providers"))
        return 1

    # 分拣：可测试 vs 跳过
    runnable = [t_ for t_ in targets if "skip" not in t_]
    skipped = [t_ for t_ in targets if "skip" in t_]

    for s in skipped:
        print(t("test_skipped", profile=s["profile"], reason=s["skip"]))

    if not runnable:
        return 1

    # ── 警告 + 确认 ──
    if not auto_yes:
        target_lines = "\n".join(
            f"    • {t_['profile']}  ({t_['provider']} / {t_['model']})"
            for t_ in runnable)
        print(t("test_warning", n=len(runnable), targets=target_lines))
        raw = input(t("test_warning_confirm")).strip().lower()
        if raw not in ("y", "yes", "是"):
            print(t("cancelled"))
            return 1

    # ── 执行 ──
    total_tokens = 0
    failed = 0
    for t_ in runnable:
        print(t("test_running",
                profile=t_["profile"],
                provider=t_["provider"],
                model=t_["model"]))
        result = _test_one(t_)
        if result["ok"]:
            total_tokens += result["tokens"]
            print(t("test_ok",
                    profile=t_["profile"],
                    latency=result["latency_ms"],
                    tokens=result["tokens"]))
        else:
            failed += 1
            print(t("test_fail",
                    profile=t_["profile"],
                    status=result["status"],
                    error=result["error"]))

    # ── Token 汇总 ──
    print(t("test_token_summary", tokens=total_tokens, n=len(runnable)))
    return 1 if failed else 0