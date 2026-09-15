"""pmgr 全量 i18n 文案。"""

import os

MESSAGES = {
    "en": {
        # ── 顶层 ──
        "cmd_help": "Full profile / provider / model lifecycle manager for Hermes",

        # ── 子命令 help ──
        "cmd_list_help": "List all profiles and their provider/model",
        "cmd_show_help": "Show details of a profile",
        "cmd_doctor_help": "Run static health checks on all configs",
        "cmd_test_help": "Test connectivity (consumes tokens; warns before running)",
        "cmd_diff_help": "Diff two profiles",
        "cmd_set_help": "Set a single config field by dotted path",
        "cmd_add_help": "Add a provider/model and assign to profiles",
        "cmd_remove_help": "Remove a provider/model from profiles",
        "cmd_modify_help": "Modify a provider/model",
        "cmd_create_help": "Create a new profile",
        "cmd_rename_help": "Rename a profile",
        "cmd_delete_help": "Delete a profile",
        "cmd_copy_help": "Copy a profile",
        "cmd_export_help": "Export profile(s) as YAML to stdout or a file",
        "cmd_import_help": "Import profile(s) from a YAML file",
        "cmd_env_help": "Manage .env of a profile",
        "cmd_env_list_help": "List env vars of a profile (masked)",
        "cmd_env_set_help": "Set an env var in a profile's .env",
        "cmd_env_unset_help": "Unset an env var in a profile's .env",
        "cmd_scan_help": "Scan .yaml files for provider definitions",

        # ── 选择与输入 ──
        "select_provider": "Select Provider:",
        "select_model": "Select Model:",
        "select_profiles": "Select profiles to apply (multi-select):",
        "select_all": "Select all",
        "custom_input": "Custom input...",
        "enter_model": "Enter Model ID",
        "enter_api_key": "Enter API Key",
        "enter_new_value": "Enter new value",
        "prompt_choice": "Enter number or name: ",
        "prompt_multi": "Enter numbers (comma/space separated), 'a' for all, Enter for defaults: ",
        "prompt_text": "{prompt}: ",
        "prompt_text_default": "{prompt} [{default}]: ",
        "invalid_choice": "[warn] Unrecognized input '{raw}', using default '{default}'",
        "invalid_multi": "[warn] No valid selection.",

        # ── 通用预览 / 确认 ──
        "preview_header": "\n── Dry-run preview ─────────────────────────────────────────",
        "preview_footer": "─────────────────────────────────────────────────────────────",
        "preview_empty": "[info] No changes detected.",
        "no_op_done": "[info] No operation performed. Nothing was written.",
        "preview_profile": "\n  ── {name}",
        "preview_provider": "     provider: {old}  →  {new}",
        "preview_model": "     model:    {old}  →  {new}",
        "preview_add": "\n  + ADD  provider={slug}  model={model}  profile={profile}",
        "preview_remove": "\n  - DEL  provider={slug}  model={model}  profile={profile}",
        "preview_modify": "\n  ~ MOD  provider={slug}  model={model}  profile={profile}",
        "preview_env": "         .env: {env_key}=***",
        "preview_config": "         config.yaml: providers.{slug} updated",
        "preview_model_switch": "         model.provider={slug}, model.default={model}",
        "preview_create": "\n  + CREATE  profile={profile}  from={source}",
        "preview_rename": "\n  ~ RENAME  {old}  →  {new}",
        "preview_delete": "\n  - DELETE  profile={profile}  keep_env={keep_env}",
        "preview_copy": "\n  + COPY  {src}  →  {dst}  with_env={with_env}",
        "preview_set": "\n  ~ SET  profile={profile}  {key}: {old}  →  {new}",
        "preview_import": "\n  + IMPORT  profile={profile}  source={source}",
        "preview_env_set": "\n  ~ ENV SET  profile={profile}  {key}=***",
        "preview_env_unset": "\n  - ENV UNSET  profile={profile}  {key}",

        "confirm_write": "\nProceed with these changes? [y/N]: ",
        "confirm_apply": "\nApply these changes? [y/N]: ",
        "cancelled": "[info] Cancelled. Nothing was written.",
        "done_count": "\n[done] {n} item(s) applied.",
        "write_line": "  ✓ {name}: provider={provider}, model={model}",

        # ── 错误 / 警告 ──
        "warn_parse": "[warn] Cannot parse {path}: {exc}",
        "err_id_format": "[error] --id must be 'provider.model'",
        "err_provider_missing": "[error] Provider '{slug}' not found.",
        "err_provider_exists": "[error] Provider '{slug}' already exists.",
        "err_no_profile_match": "[warn] No profiles matched: {patterns}",
        "err_default_no_model": "[error] default profile has no model set.",
        "no_providers": "[error] No providers found in any profile.",
        "no_other_profiles": "[info] No other profiles to sync.",
        "create_exists": "[error] Profile '{name}' already exists.",
        "create_src_missing": "[error] Source profile '{name}' not found.",
        "rename_src_missing": "[error] Source profile '{name}' not found.",
        "rename_exists": "[error] Target profile '{name}' already exists.",
        "delete_mismatch": "[error] Input does not match. Aborted.",
        "set_invalid_path": "[error] Path '{path}' is not in the writable whitelist.",
        "import_conflict": "[warn] Profile '{name}' already exists; skipping (--no-overwrite).",
        "import_bad_format": "[error] Invalid import file format.",
        "env_not_found": "[warn] {key} not found in {profile}'s .env.",

        # ── list / show ──
        "list_header": "PROFILE              PROVIDER             MODEL",
        "list_empty": "[info] No profiles found.",
        "list_providers_header": "PROVIDER             PROFILES USED BY",
        "list_models_header": "MODEL                              PROVIDER",
        "show_path": "Path:     {path}",
        "show_model_section": "\nModel:",
        "show_providers_section": "\nProviders:",
        "show_env_section": "\nEnv ({path}):",
        "show_model_provider": "  provider: {value}",
        "show_model_default": "  default:  {value}",
        "show_provider_line": "  {slug}:",
        "show_provider_api_key": "    api_key:    {value}",
        "show_provider_base_url": "    base_url:   {value}",
        "show_provider_models": "    models:     {value}",
        "env_set_marker": "✓ set",
        "env_missing_marker": "✗ missing",
        "env_masked": "{head}...{tail}",

        # ── doctor ──
        "doctor_header": "── pmgr doctor ────────────────────────────────────────────",
        "doctor_ok": "  ✓ {msg}",
        "doctor_warn": "  ⚠ {msg}",
        "doctor_error": "  ✗ {msg}",
        "doctor_summary": "\n{errors} error(s), {warnings} warning(s).",
        "doctor_all_ok": "\nAll checks passed.",
        "doctor_missing_provider": "{profile}: model.provider='{slug}' not defined in providers",
        "doctor_missing_key": "{profile}: .env missing {env_key} for provider '{slug}'",
        "doctor_missing_model": "{profile}: model.default is empty",
        "doctor_no_default": "default profile has no model set",
        "doctor_orphan_provider": "{profile}: providers.{slug} has no models",

        # ── test ──
        "test_warning": "\n[!] Connectivity test will send a minimal request to each provider.\n    This CONSUMES a small amount of tokens (usually < 20 per profile).\n    Target profiles ({n}):\n{targets}",
        "test_warning_confirm": "\nProceed with test? [y/N]: ",
        "test_running": "  → testing {profile} ({provider} / {model}) ...",
        "test_ok": "  ✓ {profile}: {latency}ms, {tokens} tokens",
        "test_fail": "  ✗ {profile}: {status} {error}",
        "test_skipped": "  - {profile}: skipped ({reason})",
        "test_token_summary": "\n[total] consumed ~{tokens} token(s) across {n} profile(s).",
        "test_no_key": "no API key in .env",
        "test_no_model": "no model configured",
        "test_no_provider": "no provider configured",

        # ── diff ──
        "diff_header": "── diff {a}  vs  {b} ─────────────────────────────────────",
        "diff_identical": "  (identical)",

        # ── scan ──
        "scan_header": "── scan {root} ────────────────────────────────────────────",
        "scan_none": "[info] No provider definitions found.",
        "scan_found": "  {path}  →  {kind}: {slugs}",

        # ── export / import ──
        "export_header": "# pmgr export — generated file, do not edit manually",
        "export_plaintext_warning": "[warn] --plaintext will include API keys in cleartext.",
        "export_no_env_hint": "# .env not included (use --with-env)",
        "import_header": "── import from {path} ────────────────────────────────────",
        "import_done": "[done] Imported {n} profile(s).",
        "copy_done": "[done] Copied {src} → {dst}.",

        # ── usage ──
        "usage_header": "Usage:",
        "none": "(none)",
    },
    "zh": {
        "cmd_help": "Hermes profile / provider / model 全生命周期管理器",

        "cmd_list_help": "列出所有 profile 及其 provider/model",
        "cmd_show_help": "显示某个 profile 的详细信息",
        "cmd_doctor_help": "对所有配置做静态健康检查",
        "cmd_test_help": "连通性测试（消耗 token，执行前会提示）",
        "cmd_diff_help": "对比两个 profile",
        "cmd_set_help": "用点分路径设置单个配置项",
        "cmd_add_help": "添加 provider/model 并分配到 profile",
        "cmd_remove_help": "从 profile 中删除 provider/model",
        "cmd_modify_help": "修改 provider/model",
        "cmd_create_help": "新建 profile",
        "cmd_rename_help": "重命名 profile",
        "cmd_delete_help": "删除 profile",
        "cmd_copy_help": "复制 profile",
        "cmd_export_help": "导出 profile 为 YAML",
        "cmd_import_help": "从 YAML 文件导入 profile",
        "cmd_env_help": "管理某个 profile 的 .env",
        "cmd_env_list_help": "列出 profile 的环境变量（打码）",
        "cmd_env_set_help": "设置 profile .env 中的环境变量",
        "cmd_env_unset_help": "删除 profile .env 中的环境变量",
        "cmd_scan_help": "扫描磁盘上的 .yaml 文件，寻找 provider 定义",

        "select_provider": "请选择 Provider：",
        "select_model": "请选择 Model：",
        "select_profiles": "请选择要应用的 profiles（可多选）：",
        "select_all": "全选",
        "custom_input": "手动输入...",
        "enter_model": "请输入 Model ID",
        "enter_api_key": "请输入 API Key",
        "enter_new_value": "请输入新值",
        "prompt_choice": "请输入编号或名称：",
        "prompt_multi": "请输入编号（逗号或空格分隔），a 全选，直接回车使用默认：",
        "prompt_text": "{prompt}：",
        "prompt_text_default": "{prompt} [{default}]：",
        "invalid_choice": "[warn] 无法识别 '{raw}'，使用默认值 '{default}'",
        "invalid_multi": "[warn] 未选择任何有效项。",

        "preview_header": "\n── Dry-run 预览 ────────────────────────────────────────────",
        "preview_footer": "─────────────────────────────────────────────────────────────",
        "preview_empty": "[info] 未检测到任何变更。",
        "no_op_done": "[info] 未进行任何操作，未写入任何内容。",
        "preview_profile": "\n  ── {name}",
        "preview_provider": "     provider: {old}  →  {new}",
        "preview_model": "     model:    {old}  →  {new}",
        "preview_add": "\n  + 新增  provider={slug}  model={model}  profile={profile}",
        "preview_remove": "\n  - 删除  provider={slug}  model={model}  profile={profile}",
        "preview_modify": "\n  ~ 修改  provider={slug}  model={model}  profile={profile}",
        "preview_env": "         .env: {env_key}=***",
        "preview_config": "         config.yaml: providers.{slug} 已更新",
        "preview_model_switch": "         model.provider={slug}, model.default={model}",
        "preview_create": "\n  + 新建  profile={profile}  from={source}",
        "preview_rename": "\n  ~ 重命名  {old}  →  {new}",
        "preview_delete": "\n  - 删除  profile={profile}  keep_env={keep_env}",
        "preview_copy": "\n  + 复制  {src}  →  {dst}  with_env={with_env}",
        "preview_set": "\n  ~ 设置  profile={profile}  {key}: {old}  →  {new}",
        "preview_import": "\n  + 导入  profile={profile}  source={source}",
        "preview_env_set": "\n  ~ ENV 设置  profile={profile}  {key}=***",
        "preview_env_unset": "\n  - ENV 删除  profile={profile}  {key}",

        "confirm_write": "\n确认写入以上变更？[y/N]：",
        "confirm_apply": "\n确认应用以上变更？[y/N]：",
        "cancelled": "[info] 已取消，未写入任何内容。",
        "done_count": "\n[done] 已应用 {n} 项变更。",
        "write_line": "  ✓ {name}: provider={provider}, model={model}",

        "warn_parse": "[warn] 无法解析 {path}：{exc}",
        "err_id_format": "[error] --id 必须为 'provider.model' 格式",
        "err_provider_missing": "[error] 未找到 provider '{slug}'。",
        "err_provider_exists": "[error] provider '{slug}' 已存在。",
        "err_no_profile_match": "[warn] 没有 profile 匹配：{patterns}",
        "err_default_no_model": "[error] default profile 未设置 model。",
        "no_providers": "[error] 未在任何 profile 中找到 provider。",
        "no_other_profiles": "[info] 没有其他 profile 需要同步。",
        "create_exists": "[error] profile '{name}' 已存在。",
        "create_src_missing": "[error] 源 profile '{name}' 不存在。",
        "rename_src_missing": "[error] 源 profile '{name}' 不存在。",
        "rename_exists": "[error] 目标 profile '{name}' 已存在。",
        "delete_mismatch": "[error] 输入不匹配，已终止。",
        "set_invalid_path": "[error] 路径 '{path}' 不在可写白名单内。",
        "import_conflict": "[warn] profile '{name}' 已存在，跳过（--no-overwrite）。",
        "import_bad_format": "[error] 导入文件格式不正确。",
        "env_not_found": "[warn] {profile} 的 .env 中未找到 {key}。",

        "list_header": "PROFILE              PROVIDER             MODEL",
        "list_empty": "[info] 未找到任何 profile。",
        "list_providers_header": "PROVIDER             被哪些 profile 使用",
        "list_models_header": "MODEL                              PROVIDER",
        "show_path": "路径：    {path}",
        "show_model_section": "\nModel:",
        "show_providers_section": "\nProviders:",
        "show_env_section": "\nEnv（{path}）：",
        "show_model_provider": "  provider: {value}",
        "show_model_default": "  default:  {value}",
        "show_provider_line": "  {slug}:",
        "show_provider_api_key": "    api_key:    {value}",
        "show_provider_base_url": "    base_url:   {value}",
        "show_provider_models": "    models:     {value}",
        "env_set_marker": "✓ 已设置",
        "env_missing_marker": "✗ 缺失",
        "env_masked": "{head}...{tail}",

        "doctor_header": "── pmgr doctor ────────────────────────────────────────────",
        "doctor_ok": "  ✓ {msg}",
        "doctor_warn": "  ⚠ {msg}",
        "doctor_error": "  ✗ {msg}",
        "doctor_summary": "\n{errors} 个错误，{warnings} 个警告。",
        "doctor_all_ok": "\n所有检查通过。",
        "doctor_missing_provider": "{profile}: model.provider='{slug}' 未在 providers 中定义",
        "doctor_missing_key": "{profile}: .env 缺少 provider '{slug}' 的 {env_key}",
        "doctor_missing_model": "{profile}: model.default 为空",
        "doctor_no_default": "default profile 未设置 model",
        "doctor_orphan_provider": "{profile}: providers.{slug} 没有任何 model",

        "test_warning": "\n[!] 连通性测试将向每个 provider 发送一条最小请求。\n    这会消耗少量 token（通常每个 profile < 20）。\n    目标 profile（{n} 个）：\n{targets}",
        "test_warning_confirm": "\n是否继续测试？[y/N]：",
        "test_running": "  → 正在测试 {profile}（{provider} / {model}）...",
        "test_ok": "  ✓ {profile}: {latency}ms，消耗 {tokens} tokens",
        "test_fail": "  ✗ {profile}: {status} {error}",
        "test_skipped": "  - {profile}: 已跳过（{reason}）",
        "test_token_summary": "\n[合计] 共 {n} 个 profile，消耗约 {tokens} tokens。",
        "test_no_key": ".env 中没有 API Key",
        "test_no_model": "未配置 model",
        "test_no_provider": "未配置 provider",

        "diff_header": "── diff {a}  vs  {b} ─────────────────────────────────────",
        "diff_identical": "  （完全相同）",

        "scan_header": "── scan {root} ────────────────────────────────────────────",
        "scan_none": "[info] 未找到任何 provider 定义。",
        "scan_found": "  {path}  →  {kind}: {slugs}",

        "export_header": "# pmgr 导出文件 — 请勿手动编辑",
        "export_plaintext_warning": "[warn] --plaintext 将以明文包含 API Key。",
        "export_no_env_hint": "# 未包含 .env（如需请加 --with-env）",
        "import_header": "── 从 {path} 导入 ──────────────────────────────────────",
        "import_done": "[done] 已导入 {n} 个 profile。",
        "copy_done": "[done] 已复制 {src} → {dst}。",

        "usage_header": "用法：",
        "none": "（未设置）",
    },
}


def _detect_lang() -> str:
    explicit = (os.environ.get("HERMES_LANG") or "").lower()
    if explicit.startswith("zh"):
        return "zh"
    if explicit.startswith("en"):
        return "en"
    lang = (os.environ.get("LANG") or os.environ.get("LC_ALL") or "").lower()
    return "zh" if lang.startswith("zh") else "en"


_LANG = _detect_lang()


def t(key: str, **kwargs) -> str:
    table = MESSAGES.get(_LANG, MESSAGES["en"])
    msg = table.get(key) or MESSAGES["en"].get(key, key)
    return msg.format(**kwargs) if kwargs else msg


def current_lang() -> str:
    return _LANG