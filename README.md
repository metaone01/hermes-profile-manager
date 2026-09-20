<div align="center">
<h1>📦 pmgr — Hermes Profile 管理器</h1>

<p>
  <img src="https://img.shields.io/badge/version-2.0.1-blue.svg" alt="version">
  <img src="https://img.shields.io/badge/python-3.9%2B-blue.svg" alt="python">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="license">
  <img src="https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg" alt="platform">
  <img src="https://img.shields.io/badge/Hermes-Plugin-purple.svg" alt="hermes-plugin">
  <img src="https://img.shields.io/badge/i18n-中文%20%7C%20English-orange.svg" alt="i18n">
</p>

<p>
  <b>一个面向 <a href="https://github.com/NousResearch/hermes">Hermes</a> 的完整 profile / provider / model 生命周期管理插件。</b><br>
  交互式菜单 · Dry-run 预览 · 多语言 · 全生命周期覆盖
</p>

[中文](./README.md) | [English](./README.en.md)

<p>
  <a href="#-特性">特性</a> ·
  <a href="#-安装">安装</a> ·
  <a href="#-快速开始">快速开始</a> ·
  <a href="#-命令一览">命令一览</a> ·
  <a href="#-数据结构">数据结构</a> ·
  <a href="#-开发">开发</a> ·
  <a href="#-faq">FAQ</a>
</p>
</div>

---

## ✨ 特性

- 🎯 **全生命周期管理** — 从 `create` 到 `delete`，覆盖 profile 的每一个阶段
- 🖱️ **交互式菜单** — 无需记忆参数，编号 / 名称 / 多选 / 全选 / 正则匹配
- 🛡️ **Dry-run 优先** — 任何写操作都先预览，`y/N` 二次确认才落盘
- 🔐 **密钥隔离** — API Key 只写入 `.env`，绝不进入 `config.yaml`
- 🌐 **多语言** — 中文 / English 自动检测（`HERMES_LANG` > `LANG` > 默认英文）
- 🩺 **健康检查** — `doctor` 静态扫描，`test` 运行时连通性验证
- 💾 **备份与迁移** — `export` / `import` / `backup`，换机器零成本
- 🔍 **可观测** — `list` / `show` / `diff` / `scan`，一切皆可见
- 🧩 **零硬编码 provider** — 所有 provider 从现有配置动态收集
- 📦 **无侵入** — 纯插件，不改 Hermes 任何一行代码

---

## 📥 安装

### 自动安装

```bash
# Linux / macOS：一行安装，无需克隆仓库
curl -fsSL https://raw.githubusercontent.com/metaone01/hermes-profile-manager/main/install.sh | bash

# macOS 专用（Homebrew 感知）
curl -fsSL https://raw.githubusercontent.com/metaone01/hermes-profile-manager/main/install-macos.sh | bash

# 传参：用 `bash -s --` 把选项交给脚本
curl -fsSL https://raw.githubusercontent.com/metaone01/hermes-profile-manager/main/install.sh | bash -s -- --force
```

> 管道安装会自动下载源码压缩包到临时目录，装完即清理；也可先克隆仓库再执行 `./install.sh`（使用仓库内源码，不联网下载）。

```pwsh
# Windows
iwr -useb https://raw.githubusercontent.com/metaone01/hermes-profile-manager/main/install.ps1 | iex
```

### 手动安装

#### 从 GitHub 克隆

```bash
git clone https://github.com/metaone01/hermes-profile-manager.git
mkdir -p ~/.hermes/plugins
cp -r hermes-profile-manager/pmgr ~/.hermes/plugins/
hermes plugins enable pmgr
```

#### 手动放置

将 `pmgr/` 目录放到 Hermes 的插件目录下：

```text
~/.hermes/plugins/
└── pmgr/
    ├── plugin.yaml
    ├── __init__.py
    ├── i18n.py
    ├── core.py
    ├── commands.py
    ├── test_conn.py
    └── cli.py
```

> ⚠️ 只复制文件是不够的。用户级插件是 **opt-in**：不执行 `hermes plugins enable pmgr`，
> Hermes 就不会加载它，`hermes pmgr` 会报 `invalid choice: 'pmgr'`（看起来像"命令不存在"）。
> 三个安装脚本都会自动完成这一步并回读验证。

### 依赖

- Python **3.9+**
- `PyYAML`（必需）
- `httpx` 或 `requests`（`test` 命令必需，二选一；缺失时回退 `urllib`）

```bash
pip install pyyaml httpx
```

### 启用插件

用户级插件默认**不加载**，装完必须登记到 `plugins.enabled`：

```bash
hermes plugins enable pmgr        # 写 $HERMES_HOME/config.yaml
hermes plugins show pmgr          # 应显示 Status: enabled
```

`HERMES_HOME` 决定写到哪个 home：不设时用 `~/.hermes`（default），设了则写该 profile
的 `config.yaml`。**正在运行的 gateway 只在启动时扫描一次插件**，所以要让 gateway
里的会话用上 `hermes pmgr`，需要重启 gateway（或新起一个会话）。

### 验证安装

```bash
hermes pmgr list
```

---

## 🚀 快速开始

### 场景 1：看看我现在有什么

```bash
hermes pmgr list # 所有 profile + provider + model
hermes pmgr show work # 单个 profile 详情
hermes pmgr doctor # 健康检查
```

### 场景 2：把几个 profile 一起切到同一个 provider/model

```bash
hermes pmgr

# → 选 provider → 选 model → 多选 profiles → dry-run → 确认

```

### 场景 3：把某个 profile 重置回 default

```bash
hermes pmgr work --default
```

### 场景 4：一键同步所有 profile 到 default

```bash
hermes pmgr --default --all
```

### 场景 5：添加一个新 provider

```bash
hermes pmgr add \
 --id openrouter.anthropic/claude-opus-4.6 \
 --api-key sk-or-v1-xxxx \
 --profiles 'work|personal' default
```

---

## 📖 命令一览

### 🗂️ Profile 管理

| 命令                           | 说明                                               |
| :----------------------------- | :------------------------------------------------- |
| `hermes pmgr`                  | 完整交互式：选 provider → model → profiles（多选） |
| `hermes pmgr <name> [...]`     | 指定 profile，交互选 provider/model                |
| `hermes pmgr <name> --default` | 将 profile 对齐到 default                          |
| `hermes pmgr --default --all`  | 所有 profile 对齐到 default                        |

### 🔧 Provider / Model 增删改

| 命令                                                             | 说明                |
| :--------------------------------------------------------------- | :------------------ |
| `hermes pmgr add --id <p>.<m> [--api-key K] [--profiles ...]`    | 添加 provider/model |
| `hermes pmgr remove --id <p>.<m> [--profiles ...]`               | 删除 provider/model |
| `hermes pmgr modify --id <p>.<m> [--api-key K] [--profiles ...]` | 修改 provider/model |

`--profiles` 支持**正则**：`--profiles 'work|personal'`、`--profiles 'dev-*'`。

### 👁️ 可见性

| 命令                                       | 说明                                     |
| :----------------------------------------- | :--------------------------------------- |
| `hermes pmgr list [--providers\|--models]` | 一览所有 profile / provider / model      |
| `hermes pmgr show <profile>`               | 单个 profile 详情（含 .env 打码预览）    |
| `hermes pmgr diff <a> <b>`                 | 对比两个 profile                         |
| `hermes pmgr scan [path]`                  | 扫描磁盘上的 `.yaml`，寻找 provider 定义 |

### 🩺 诊断

| 命令                                     | 说明                                                 |
| :--------------------------------------- | :--------------------------------------------------- |
| `hermes pmgr doctor`                     | 静态健康检查（缺失 key、孤立 provider、空 model 等） |
| `hermes pmgr test [profiles...] [--yes]` | 连通性测试（**消耗 token**，执行前提示）             |

`test` 命令会在执行前告知消耗并请求确认，执行后汇报 token 总量：

```console
$ hermes pmgr test

- personal: 已跳过（.env 中没有 API Key）

[!] 连通性测试将向每个 provider 发送一条最小请求。
这会消耗少量 token（通常每个 profile < 20）。
目标 profile（3 个）：
• default (openrouter / anthropic/claude-opus-4.6)
• research (openrouter / anthropic/claude-opus-4.6)
• work (openrouter / anthropic/claude-sonnet-4.6)

是否继续测试？[y/N]：y
→ 正在测试 default（openrouter / anthropic/claude-opus-4.6）...
✓ default: 412ms，消耗 8 tokens
→ 正在测试 research（openrouter / anthropic/claude-opus-4.6）...
✓ research: 380ms，消耗 7 tokens
→ 正在测试 work（openrouter / anthropic/claude-sonnet-4.6）...
✓ work: 395ms，消耗 7 tokens

[合计] 共 3 个 profile，消耗约 22 tokens。
```

使用 `--yes` / `-y` 跳过确认（适合脚本化）。

### ✏️ 单项修改

| 命令                                      | 说明                   |
| :---------------------------------------- | :--------------------- |
| `hermes pmgr set <profile> <key> <value>` | 用点分路径设置单个字段 |

白名单路径：`model.*` / `providers.*` / `custom_providers.*`

```bash
hermes pmgr set work model.default anthropic/claude-haiku-4.5
hermes pmgr set work providers.openrouter.base_url https://custom.proxy/v1
```

### 🌱 Profile 生命周期

| 命令                                                           | 说明                                   |
| :------------------------------------------------------------- | :------------------------------------- |
| `hermes pmgr create <name> [--from <src>] [--with-env]`        | 新建 profile                           |
| `hermes pmgr copy <src> <dst> [--with-env]`                    | 复制 profile                           |
| `hermes pmgr rename <old> <new>`                               | 重命名 profile                         |
| `hermes pmgr delete <name> [--keep-env] [--no-backup] [--yes]` | 删除 profile（**需二次输入名称确认**） |

`delete` 默认会先备份到 `~/.hermes/.backup/`。

### 💾 备份与迁移

| 命令                                                                    | 说明         |
| :---------------------------------------------------------------------- | :----------- |
| `hermes pmgr export [profiles...] [--with-env] [--plaintext] [-o FILE]` | 导出为 YAML  |
| `hermes pmgr import <file> [--no-overwrite]`                            | 从 YAML 导入 |

`--plaintext` 需二次确认；默认以 `***` 打码密钥。

### 🔑 环境变量

| 命令                                          | 说明                           |
| :-------------------------------------------- | :----------------------------- |
| `hermes pmgr env list <profile>`              | 列出 profile 的 `.env`（打码） |
| `hermes pmgr env set <profile> <KEY> <VALUE>` | 设置环境变量                   |
| `hermes pmgr env unset <profile> <KEY>`       | 删除环境变量                   |

---

## 🏗️ 数据结构

`pmgr` 严格遵循 Hermes 的真实存储结构，从不发明新字段。

### 📁 目录布局

```text
~/.hermes/
├── config.yaml # default profile 的 config
├── .env # default profile 的密钥
├── .backup/ # pmgr 自动备份
│ └── work-20260101-120000/
└── profiles/
├── work/
│ ├── config.yaml
│ └── .env
└── personal/
├── config.yaml
└── .env
```

### 🗂️ `config.yaml` 结构

```yaml
model:
provider: openrouter
default: anthropic/claude-opus-4.6

providers:
openrouter:
name: openrouter
base_url: https://openrouter.ai/api/v1
api_key: ${OPENROUTER_API_KEY} # 引用 .env，不写明文
default_model: anthropic/claude-opus-4.6
models:
anthropic/claude-opus-4.6: {}
anthropic/claude-sonnet-4.6:
context_length: 200000

custom_providers:
    - name: my-proxy
      provider: openai
      base_url: https://proxy.example.com/v1
```

### 🔐 `.env` 结构

```bash
OPENROUTER_API_KEY=sk-or-v1-xxxx
OPENAI_API_KEY=sk-xxxx
ANTHROPIC_API_KEY=sk-ant-xxxx
```

> **安全原则**：API Key 只写入 `.env`，`config.yaml` 中只保留 `${ENV_VAR}` 形式的引用。这与 Hermes 运行时解析层的读取方式一致。

---

## 🌐 多语言

`pmgr` 依据以下优先级自动选择语言：

1. `HERMES_LANG`（显式指定，`zh` / `en`）
2. `LANG` 或 `LC_ALL` 以 `zh` 开头 → 中文
3. 默认英文

```bash

# 强制中文

HERMES_LANG=zh hermes pmgr list

# 强制英文

HERMES_LANG=en hermes pmgr list
```

---

## 🛠️ 开发

### 目录结构

```text
hermes-profile-manager/
└── pmgr/
├── plugin.yaml # 插件清单
├── **init**.py # 注册入口
├── i18n.py # 中英文文案
├── core.py # 路径、IO、profile 匹配、provider 辅助
├── commands.py # 所有非 test 命令
├── test_conn.py # 连通性测试
└── cli.py # argparse 分发
```

### 本地开发

```bash
git clone https://github.com/metaone01/hermes-profile-manager.git
cd hermes-profile-manager

# 建立软链接便于迭代

ln -sf "$(pwd)/pmgr" ~/.hermes/plugins/pmgr

# 首次需要 enable 一次（之后改代码只需重启 Hermes）
hermes plugins enable pmgr

hermes pmgr list
```

### 新增一个命令

1. 在 `commands.py` 中实现 `plan_xxx()` 和 `apply_xxx()` 两个函数
2. 在 `cli.py` 中：
    - 写一个 `_handle_xxx(args)` 处理函数
    - 在 `register_cli()` 中通过 `sub.add_parser()` 注册
    - 用 `C.dry_run_then_apply(changes, apply_fn, render_fn)` 统一走 dry-run 流程
3. 在 `i18n.py` 的 `en` / `zh` 两段中补充文案

### 添加新语言

在 `i18n.py` 的 `MESSAGES` 中新增语言段，并扩展 `_detect_lang()`。

---

## 🧪 测试

```bash

# 查看状态

hermes pmgr list

# 健康检查

hermes pmgr doctor

# 连通性测试（会消耗 token）

hermes pmgr test work
```

由于插件直接操作真实 Hermes 配置，测试前建议先备份：

```bash
hermes pmgr export -o backup.yaml
```

---

## ❓ FAQ

<details>
<summary><b>Q: 插件会修改 Hermes 自身的代码吗？</b></summary>

不会。`pmgr` 是纯插件，只读写 `~/.hermes/` 下的配置文件。

</details>

<details>
<summary><b>Q: API Key 会进入 config.yaml 吗？</b></summary>

不会。密钥只写入 `.env`，`config.yaml` 中只保留 `${ENV_VAR}` 引用。

</details>

<details>
<summary><b>Q: `delete` 命令会永久删除数据吗？</b></summary>

默认会先备份到 `~/.hermes/.backup/`。如需跳过备份，使用 `--no-backup`。

</details>

<details>
<summary><b>Q: `test` 命令会消耗多少 token？</b></summary>

每个 profile 通常 < 20 tokens。执行前会展示目标 profile 列表并要求确认，执行后会汇报实际消耗总量。

</details>

<details>
<summary><b>Q: 安装成功、也重启了，但 `hermes pmgr` 报 `invalid choice: 'pmgr'`？</b></summary>

插件没被启用。用户级插件是 opt-in：文件放对位置还不够，必须登记进
`plugins.enabled`。

```bash
hermes plugins enable pmgr
hermes plugins show pmgr     # Status: enabled
```

还要确认 `HERMES_HOME` 指向的是你正在用的那个 home：`hermes plugins enable` 写的是
`$HERMES_HOME/config.yaml`，不设时是 `~/.hermes`。装到 A home、启用写在 B home
（或反过来）都会表现为"识别不到"。

</details>

<details>
<summary><b>Q: 为什么备份目录放在 `~/.hermes/backups/plugins/pmgr/` 而不是插件目录里？</b></summary>

插件目录下每个含 `plugin.yaml` 的子目录都会被当插件扫描。旧版本安装器把备份留在
`plugins/pmgr.backup.<时间戳>/`，那份副本的 manifest name 同样是 `pmgr`，会和刚装好的
版本争同一个 key——实测**旧副本赢**（按目录名排序，`pmgr.backup.*` 排在 `pmgr` 之后被
扫描，因而覆盖注册），于是升级后加载的仍是旧代码。现在备份统一放到
`$HERMES_HOME/backups/plugins/pmgr/`，安装器还会自动把已经留在插件目录里的
`plugins/pmgr.backup.*` 移到那里（要保留原地可设 `PMGR_KEEP_LEGACY=1`，此时它只告警）。

</details>

<details>
<summary><b>Q: 装好了、也重启了，命令不报"没有这个命令"却直接抛 Traceback？</b></summary>

两种不同的故障，症状很像：

1. **`ImportError: cannot import name 'commands' from 'hermes_plugins'`** —— 顶层
   `hermes pmgr` 路径有个残留的无效相对导入（`from .. import commands`），插件在
   Hermes 里是被加载成 `hermes_plugins.pmgr` 的，没有兄弟包可导入。已删除。
2. **`TypeError: t() got multiple values for argument 'key'`** —— `t()` 的形参名 `key`
   与文案模板里的 `{key}` 占位符撞名，凡是走 `env set`/`set` 预览的路径都会崩。已把
   `key` 改为仅位置参数。

修复后（v2.0.1 起）两种情况都不再出现。若仍见到 Traceback，先确认加载的确实是
新代码——被同名副本遮蔽时 `hermes plugins list` 会显示新版本号，但实际执行的是旧副本：

```bash
hermes plugins list --plain --no-bundled   # 看 pmgr 的版本
ls "$HERMES_HOME/plugins"                # 有 pmgr.backup.* 就是被遮蔽了
mv "$HERMES_HOME/plugins/pmgr.backup."* "$HERMES_HOME/backups/plugins/pmgr/"
```

安装器现在会自动做这一步，并在无法隔离时把 `Activated` 标成 `NO`，不再假报成功。

</details>

<details>
<summary><b>Q: 怎么卸载？会自动清理 `plugins.enabled` 吗？</b></summary>

```bash
./install.sh --uninstall     # 或 install-macos.sh / install.ps1 -Uninstall
```

会先把 `pmgr` 从 `plugins.enabled` 摘掉，再删插件目录。手动装的则自己执行
`hermes plugins disable pmgr`。

</details>

<details>
<summary><b>Q: 怎么从备份恢复？</b></summary>

`~/.hermes/.backup/<name>-<timestamp>/` 中包含当时的 `config.yaml` 和 `.env`，直接复制回 `profiles/<name>/` 即可。

</details>

<details>
<summary><b>Q: 支持哪些 provider？</b></summary>

所有 provider 从现有配置动态收集，无硬编码列表。内置环境变量名映射涵盖 OpenRouter / OpenAI / Anthropic / Google / Gemini / Nous / Z.AI / Kimi / MiniMax / KiloCode / OpenCode / Alibaba / Copilot / HuggingFace 等；其他 provider 会自动推导 `<SLUG>_API_KEY`。

</details>

---

## 🤝 贡献

欢迎提交 Issue 和 PR！

```bash
git checkout -b feature/my-feature
git commit -am "Add my feature"
git push origin feature/my-feature
```

请确保：

- 所有新增命令都走 `dry_run_then_apply()` 流程
- 所有用户可见文案都通过 `i18n.t()` 获取
- 新增写操作必须有 dry-run 预览 + 确认

---

## 🙏 致谢

- [Hermes](https://github.com/NousResearch/hermes) — 插件宿主
- [PyYAML](https://pyyaml.org/) — 配置解析
- 所有贡献者与使用者

---

<p align="center">
  如果这个项目对你有帮助，欢迎 ⭐️ Star！
</p>
