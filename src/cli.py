"""pmgr argparse 分发。"""

import argparse
import sys
from pathlib import Path

from .core import (
    collect_providers,
    collect_models_for_provider,
    match_profiles,
    read_model_config,
    list_profiles,
    parse_provider_id,
)
from . import commands as C
from . import test_conn as T
from .i18n import t

# ═════════════════════════════════════════════════════════════════
#  渲染器（用于 dry-run 展示）
# ═════════════════════════════════════════════════════════════════


def _render_add(c):
    print(t("preview_add", slug=c["slug"], model=c["model"], profile=c["profile"]))
    print(t("preview_env", env_key=c["env_key"]))
    print(t("preview_config", slug=c["slug"]))
    print(t("preview_model_switch", slug=c["slug"], model=c["model"]))


def _render_remove(c):
    print(t("preview_remove", slug=c["slug"], model=c["model"], profile=c["profile"]))


def _render_modify(c):
    print(t("preview_modify", slug=c["slug"], model=c["model"], profile=c["profile"]))
    if c.get("env_key"):
        print(t("preview_env", env_key=c["env_key"]))
    print(t("preview_config", slug=c["slug"]))


def _render_set(c):
    print(
        t("preview_set", profile=c["profile"], key=c["key"], old=c["old"], new=c["new"])
    )


def _render_create(c):
    print(
        t("preview_create", profile=c["profile"], source=c.get("source") or t("none"))
    )


def _render_rename(c):
    print(t("preview_rename", old=c["old"], new=c["new"]))


def _render_delete(c):
    print(t("preview_delete", profile=c["profile"], keep_env=c["keep_env"]))


def _render_copy(c):
    print(t("preview_copy", src=c["src"], dst=c["dst"], with_env=c["with_env"]))


def _render_import(c):
    print(t("preview_import", profile=c["profile"], source="file"))


def _render_env_set(c):
    print(t("preview_env_set", profile=c["profile"], key=c["key"]))


def _render_env_unset(c):
    print(t("preview_env_unset", profile=c["profile"], key=c["key"]))


# ═════════════════════════════════════════════════════════════════
#  交互式补齐
# ═════════════════════════════════════════════════════════════════


def _pick_provider_and_model() -> tuple:
    provs = collect_providers()
    if not provs:
        print(t("no_providers"))
        return None, None
    provider = C.prompt_choice(t("select_provider"), provs, 0)
    models = collect_models_for_provider(provider) + [t("custom_input")]
    choice = C.prompt_choice(t("select_model"), models, 0)
    if choice == t("custom_input"):
        return provider, C.prompt_text(t("enter_model"))
    return provider, choice


# ═════════════════════════════════════════════════════════════════
#  子命令处理
# ═════════════════════════════════════════════════════════════════


def _handle_list(args):
    C.cmd_list(show_providers=args.providers, show_models=args.models)


def _handle_show(args):
    C.cmd_show(args.profile)


def _handle_doctor(args):
    sys.exit(C.cmd_doctor())


def _handle_test(args):
    patterns = args.profiles or []
    sys.exit(T.cmd_test(patterns, auto_yes=args.yes))


def _handle_diff(args):
    C.cmd_diff(args.a, args.b)


def _handle_set(args):
    changes = C.plan_set(args.profile, args.key, args.value)
    if not changes:
        return
    C.dry_run_then_apply(changes, C.apply_set, _render_set)


def _handle_add(args):
    if not args.id:
        slug, model = _pick_provider_and_model()
        if not slug:
            return
        api_key = C.prompt_text(t("enter_api_key"))
    else:
        try:
            slug, model = parse_provider_id(args.id)
        except ValueError as e:
            print(str(e))
            return
        api_key = args.api_key or C.prompt_text(t("enter_api_key"))

    changes = C.plan_add(
        slug,
        model,
        api_key,
        args.profiles or [],
        base_url=args.base_url,
        context_length=args.context_length,
    )
    C.dry_run_then_apply(changes, C.apply_add, _render_add, confirm_key="confirm_apply")


def _handle_remove(args):
    if not args.id:
        slug, model = _pick_provider_and_model()
        if not slug:
            return
    else:
        try:
            slug, model = parse_provider_id(args.id)
        except ValueError as e:
            print(str(e))
            return

    changes = C.plan_remove(slug, model, args.profiles or [])
    C.dry_run_then_apply(
        changes, C.apply_remove, _render_remove, confirm_key="confirm_apply"
    )


def _handle_modify(args):
    if not args.id:
        slug, model = _pick_provider_and_model()
        if not slug:
            return
    else:
        try:
            slug, model = parse_provider_id(args.id)
        except ValueError as e:
            print(str(e))
            return

    changes = C.plan_modify(
        slug,
        model,
        api_key=args.api_key,
        profiles=args.profiles or [],
        base_url=args.base_url,
        context_length=args.context_length,
    )
    C.dry_run_then_apply(
        changes, C.apply_modify, _render_modify, confirm_key="confirm_apply"
    )


def _handle_create(args):
    changes = C.plan_create(args.name, source=args.from_profile, with_env=args.with_env)
    C.dry_run_then_apply(
        changes, C.apply_create, _render_create, confirm_key="confirm_apply"
    )


def _handle_rename(args):
    changes = C.plan_rename(args.old, args.new)
    C.dry_run_then_apply(
        changes, C.apply_rename, _render_rename, confirm_key="confirm_apply"
    )


def _handle_delete(args):
    changes = C.plan_delete(
        args.name, keep_env=args.keep_env, do_backup=not args.no_backup
    )
    if not changes:
        return
    # 二次确认：输入 profile 名
    _render_delete(changes[0])
    if not args.yes:
        raw = input(f"\nType '{args.name}' to confirm deletion: ").strip()
        if raw != args.name:
            print(t("delete_mismatch"))
            return
    for c in changes:
        C.apply_delete(c)
    print(t("done_count", n=len(changes)))


def _handle_copy(args):
    changes = C.plan_copy(args.src, args.dst, with_env=args.with_env)
    C.dry_run_then_apply(
        changes, C.apply_copy, _render_copy, confirm_key="confirm_apply"
    )


def _handle_export(args):
    if args.plaintext and not args.with_env:
        print("[warn] --plaintext has no effect without --with-env")
    if args.plaintext:
        print(t("export_plaintext_warning"))
        if not args.yes:
            if not C.confirm():
                print(t("cancelled"))
                return
    body = C.cmd_export(
        args.profiles or [], with_env=args.with_env, plaintext=args.plaintext
    )
    if args.output:
        Path(args.output).write_text(body, encoding="utf-8")
        print(f"[done] Written to {args.output}")
    else:
        print(body)


def _handle_import(args):
    changes = C.plan_import(Path(args.file), no_overwrite=args.no_overwrite)
    if not changes:
        return
    C.dry_run_then_apply(
        changes, C.apply_import, _render_import, confirm_key="confirm_apply"
    )


def _handle_env_list(args):
    C.cmd_env_list(args.profile)


def _handle_env_set(args):
    changes = C.plan_env_set(args.profile, args.key, args.value)
    C.dry_run_then_apply(
        changes, C.apply_env_set, _render_env_set, confirm_key="confirm_apply"
    )


def _handle_env_unset(args):
    changes = C.plan_env_unset(args.profile, args.key)
    C.dry_run_then_apply(
        changes, C.apply_env_unset, _render_env_unset, confirm_key="confirm_apply"
    )


def _handle_scan(args):
    C.cmd_scan(Path(args.path) if args.path else None)


# ── 顶层 profile 管理（沿用旧逻辑）──


def _handle_default(args):
    from .core import (
        match_profiles,
        read_model_config,
        profile_config_path,
        load_yaml,
        save_yaml,
        CONFIG_PATH,
    )
    from .. import commands as C2

    if args.default and args.all:
        profiles = [p for p in list_profiles() if p != "default"]
        if not profiles:
            print(t("no_other_profiles"))
            return
        default_mc = read_model_config("default")
        provider, model = default_mc.get("provider", ""), default_mc.get("default", "")
        if not model:
            print(t("err_default_no_model"))
            return
        changes = [
            {
                "profile": p,
                "old_provider": read_model_config(p).get("provider", ""),
                "old_model": read_model_config(p).get("default", ""),
                "new_provider": provider,
                "new_model": model,
            }
            for p in profiles
        ]
        C.dry_run_then_apply(
            changes,
            lambda c: C.switch_model_in_profile(
                c["profile"], c["new_provider"], c["new_model"]
            ),
            lambda c: (
                print(t("preview_profile", name=c["profile"])),
                print(
                    t("preview_provider", old=c["old_provider"], new=c["new_provider"])
                ),
                print(t("preview_model", old=c["old_model"], new=c["new_model"])),
            ),
        )
        return
    print(t("usage_header"))
    print(t("cmd_help"))


# ═════════════════════════════════════════════════════════════════
#  argparse 注册
# ═════════════════════════════════════════════════════════════════


def register_cli(subparser: argparse.ArgumentParser) -> None:
    sub = subparser.add_subparsers(dest="pmgr_subcommand")

    # list
    p = sub.add_parser("list", help=t("cmd_list_help"))
    p.add_argument("--providers", action="store_true")
    p.add_argument("--models", action="store_true")
    p.set_defaults(func=_handle_list)

    # show
    p = sub.add_parser("show", help=t("cmd_show_help"))
    p.add_argument("profile")
    p.set_defaults(func=_handle_show)

    # doctor
    p = sub.add_parser("doctor", help=t("cmd_doctor_help"))
    p.set_defaults(func=_handle_doctor)

    # test
    p = sub.add_parser("test", help=t("cmd_test_help"))
    p.add_argument("profiles", nargs="*", default=[])
    p.add_argument(
        "--yes", "-y", action="store_true", help="Skip token-consumption confirmation"
    )
    p.set_defaults(func=_handle_test)

    # diff
    p = sub.add_parser("diff", help=t("cmd_diff_help"))
    p.add_argument("a")
    p.add_argument("b")
    p.set_defaults(func=_handle_diff)

    # set
    p = sub.add_parser("set", help=t("cmd_set_help"))
    p.add_argument("profile")
    p.add_argument("key")
    p.add_argument("value")
    p.set_defaults(func=_handle_set)

    # add
    p = sub.add_parser("add", help=t("cmd_add_help"))
    p.add_argument("--id")
    p.add_argument("--api-key")
    p.add_argument("--profiles", nargs="*", default=[])
    p.add_argument("--base-url")
    p.add_argument("--context-length", type=int)
    p.set_defaults(func=_handle_add)

    # remove
    p = sub.add_parser("remove", help=t("cmd_remove_help"))
    p.add_argument("--id")
    p.add_argument("--profiles", nargs="*", default=[])
    p.set_defaults(func=_handle_remove)

    # modify
    p = sub.add_parser("modify", help=t("cmd_modify_help"))
    p.add_argument("--id")
    p.add_argument("--api-key")
    p.add_argument("--profiles", nargs="*", default=[])
    p.add_argument("--base-url")
    p.add_argument("--context-length", type=int)
    p.set_defaults(func=_handle_modify)

    # create
    p = sub.add_parser("create", help=t("cmd_create_help"))
    p.add_argument("name")
    p.add_argument("--from", dest="from_profile", default=None)
    p.add_argument("--with-env", action="store_true")
    p.set_defaults(func=_handle_create)

    # rename
    p = sub.add_parser("rename", help=t("cmd_rename_help"))
    p.add_argument("old")
    p.add_argument("new")
    p.set_defaults(func=_handle_rename)

    # delete
    p = sub.add_parser("delete", help=t("cmd_delete_help"))
    p.add_argument("name")
    p.add_argument("--keep-env", action="store_true")
    p.add_argument("--no-backup", action="store_true")
    p.add_argument("--yes", "-y", action="store_true")
    p.set_defaults(func=_handle_delete)

    # copy
    p = sub.add_parser("copy", help=t("cmd_copy_help"))
    p.add_argument("src")
    p.add_argument("dst")
    p.add_argument("--with-env", action="store_true")
    p.set_defaults(func=_handle_copy)

    # export
    p = sub.add_parser("export", help=t("cmd_export_help"))
    p.add_argument("profiles", nargs="*", default=[])
    p.add_argument("--with-env", action="store_true")
    p.add_argument("--plaintext", action="store_true")
    p.add_argument("--output", "-o", default=None)
    p.add_argument("--yes", "-y", action="store_true")
    p.set_defaults(func=_handle_export)

    # import
    p = sub.add_parser("import", help=t("cmd_import_help"))
    p.add_argument("file")
    p.add_argument("--no-overwrite", action="store_true")
    p.set_defaults(func=_handle_import)

    # env
    p_env = sub.add_parser("env", help=t("cmd_env_help"))
    env_sub = p_env.add_subparsers(dest="env_subcommand")

    pe = env_sub.add_parser("list", help=t("cmd_env_list_help"))
    pe.add_argument("profile")
    pe.set_defaults(func=_handle_env_list)

    pe = env_sub.add_parser("set", help=t("cmd_env_set_help"))
    pe.add_argument("profile")
    pe.add_argument("key")
    pe.add_argument("value")
    pe.set_defaults(func=_handle_env_set)

    pe = env_sub.add_parser("unset", help=t("cmd_env_unset_help"))
    pe.add_argument("profile")
    pe.add_argument("key")
    pe.set_defaults(func=_handle_env_unset)

    # scan
    p = sub.add_parser("scan", help=t("cmd_scan_help"))
    p.add_argument("path", nargs="?", default=None)
    p.set_defaults(func=_handle_scan)

    # 顶层无子命令 → 旧版 profile 管理
    subparser.add_argument("profile_names", nargs="*", default=[])
    subparser.add_argument("--default", action="store_true", default=False)
    subparser.add_argument("--all", action="store_true", default=False)
    subparser.set_defaults(func=_handle_default)


def dispatch(args) -> None:
    """由 Hermes 或本插件的入口调用。"""
    if not hasattr(args, "func"):
        print(t("cmd_help"))
        return
    args.func(args)
