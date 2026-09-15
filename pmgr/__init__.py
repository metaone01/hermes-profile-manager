"""pmgr —— Hermes profile 全生命周期管理插件。"""

from .cli import register_cli
from .i18n import t


def register(ctx):
    ctx.register_cli_command(
        name="pmgr",
        help=t("cmd_help"),
        setup_fn=register_cli,
    )