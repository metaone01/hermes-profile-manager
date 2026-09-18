<div align="center">

<h1>📦 pmgr — Hermes Profile Manager</h1>

<p>
  <img src="https://img.shields.io/badge/version-2.0.0-blue.svg" alt="version">
  <img src="https://img.shields.io/badge/python-3.9%2B-blue.svg" alt="python">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="license">
  <img src="https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg" alt="platform">
  <img src="https://img.shields.io/badge/Hermes-Plugin-purple.svg" alt="hermes-plugin">
  <img src="https://img.shields.io/badge/i18n-English%20%7C%20中文-orange.svg" alt="i18n">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs welcome">
</p>

<p>
  <b>A complete profile / provider / model lifecycle manager plugin for <a href="https://github.com/NousResearch/hermes">Hermes</a>.</b><br>
  Interactive menus · Dry-run previews · Multi-language · Full lifecycle coverage
</p>

[中文](./README.md) | [English](./README.en.md)

<p>
  <a href="#-features">Features</a> ·
  <a href="#-installation">Installation</a> ·
  <a href="#-quick-start">Quick Start</a> ·
  <a href="#-command-reference">Command Reference</a> ·
  <a href="#-data-structures">Data Structures</a> ·
  <a href="#-development">Development</a> ·
  <a href="#-faq">FAQ</a>
</p>
</div>

---

## ✨ Features

- 🎯 **Full lifecycle management** — from `create` to `delete`, every profile stage is covered
- 🖱️ **Interactive menus** — no need to memorize flags; number / name / multi-select / select-all / regex matching
- 🛡️ **Dry-run first** — every write operation is previewed, then confirmed with a `y/N` prompt
- 🔐 **Secret isolation** — API keys are written only to `.env`, never to `config.yaml`
- 🌐 **Multi-language** — Chinese / English auto-detection (`HERMES_LANG` > `LANG` > default English)
- 🩺 **Health checks** — `doctor` for static scans, `test` for runtime connectivity
- 💾 **Backup & migration** — `export` / `import` / `backup`, zero-cost machine migration
- 🔍 **Observability** — `list` / `show` / `diff` / `scan`, everything is visible
- 🧩 **Zero hardcoded providers** — all providers are dynamically collected from existing configs
- 📦 **Non-invasive** — pure plugin, does not modify a single line of Hermes

---

## 📥 Installation

### Install Script

```bash
# Linux / macOS: one-line install, no clone required
curl -fsSL https://raw.githubusercontent.com/metaone01/hermes-profile-manager/main/install.sh | bash

# macOS (Homebrew-aware)
curl -fsSL https://raw.githubusercontent.com/metaone01/hermes-profile-manager/main/install-macos.sh | bash

# Pass options through `bash -s --`
curl -fsSL https://raw.githubusercontent.com/metaone01/hermes-profile-manager/main/install.sh | bash -s -- --force
```

> A piped install downloads the source archive into a temp dir and cleans it up afterwards. Clone the repo and run `./install.sh` instead to install from the local source without downloading.

```pwsh
# Windows
iwr -useb https://raw.githubusercontent.com/metaone01/hermes-profile-manager/main/install.ps1 | iex
```

### Manual Install

#### Clone from GitHub

```bash
git clone https://github.com/metaone01/hermes-profile-manager.git
mkdir -p ~/.hermes/plugins
cp -r hermes-profile-manager/pmgr ~/.hermes/plugins/
```

#### Manual Placement

Place the `pmgr/` directory under Hermes' plugin directory:

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

### Dependencies

- Python **3.9+**
- `PyYAML` (required)
- `httpx` or `requests` (required for the `test` command; falls back to `urllib` if absent)

```bash
pip install pyyaml httpx
```

### Verify Installation

```bash
hermes pmgr list
```

---

## 🚀 Quick Start

### Scenario 1: See what you have

```bash
hermes pmgr list # all profiles + provider + model
hermes pmgr show work # details of a single profile
hermes pmgr doctor # health check
```

### Scenario 2: Switch several profiles to the same provider/model

```bash
hermes pmgr

# → pick provider → pick model → multi-select profiles → dry-run → confirm

```

### Scenario 3: Reset a profile back to default

```bash
hermes pmgr work --default
```

### Scenario 4: Sync all profiles to default in one go

```bash
hermes pmgr --default --all
```

### Scenario 5: Add a new provider

```bash
hermes pmgr add \
 --id openrouter.anthropic/claude-opus-4.6 \
 --api-key sk-or-v1-xxxx \
 --profiles 'work|personal' default
```

---

## 📖 Command Reference

### 🗂️ Profile Management

| Command                        | Description                                                       |
| :----------------------------- | :---------------------------------------------------------------- |
| `hermes pmgr`                  | Full interactive: pick provider → model → profiles (multi-select) |
| `hermes pmgr <name> [...]`     | Specify profiles, then interactively pick provider/model          |
| `hermes pmgr <name> --default` | Align a profile to default                                        |
| `hermes pmgr --default --all`  | Align all profiles to default                                     |

### 🔧 Provider / Model Add, Remove, Modify

| Command                                                          | Description             |
| :--------------------------------------------------------------- | :---------------------- |
| `hermes pmgr add --id <p>.<m> [--api-key K] [--profiles ...]`    | Add a provider/model    |
| `hermes pmgr remove --id <p>.<m> [--profiles ...]`               | Remove a provider/model |
| `hermes pmgr modify --id <p>.<m> [--api-key K] [--profiles ...]` | Modify a provider/model |

`--profiles` supports **regex**: `--profiles 'work|personal'`, `--profiles 'dev-*'`.

### 👁️ Observability

| Command                                    | Description                                            |
| :----------------------------------------- | :----------------------------------------------------- |
| `hermes pmgr list [--providers\|--models]` | List all profiles / providers / models                 |
| `hermes pmgr show <profile>`               | Details of a single profile (with masked .env preview) |
| `hermes pmgr diff <a> <b>`                 | Diff two profiles                                      |
| `hermes pmgr scan [path]`                  | Scan `.yaml` files on disk for provider definitions    |

### 🩺 Diagnostics

| Command                                  | Description                                                               |
| :--------------------------------------- | :------------------------------------------------------------------------ |
| `hermes pmgr doctor`                     | Static health checks (missing keys, orphan providers, empty models, etc.) |
| `hermes pmgr test [profiles...] [--yes]` | Connectivity test (**consumes tokens**, warns before running)             |

The `test` command warns about token consumption and asks for confirmation before running, then reports the total tokens consumed:

```console
$ hermes pmgr test

- personal: skipped (no API key in .env)

[!] Connectivity test will send a minimal request to each provider.
This CONSUMES a small amount of tokens (usually < 20 per profile).
Target profiles (3):
• default (openrouter / anthropic/claude-opus-4.6)
• research (openrouter / anthropic/claude-opus-4.6)
• work (openrouter / anthropic/claude-sonnet-4.6)

Proceed with test? [y/N]: y
→ testing default (openrouter / anthropic/claude-opus-4.6) ...
✓ default: 412ms, 8 tokens
→ testing research (openrouter / anthropic/claude-opus-4.6) ...
✓ research: 380ms, 7 tokens
→ testing work (openrouter / anthropic/claude-sonnet-4.6) ...
✓ work: 395ms, 7 tokens

[total] consumed ~22 token(s) across 3 profile(s).
```

Use `--yes` / `-y` to skip the confirmation (suitable for scripting).

### ✏️ Single-Field Modification

| Command                                   | Description                        |
| :---------------------------------------- | :--------------------------------- |
| `hermes pmgr set <profile> <key> <value>` | Set a single field via dotted path |

Whitelisted paths: `model.*` / `providers.*` / `custom_providers.*`

```bash
hermes pmgr set work model.default anthropic/claude-haiku-4.5
hermes pmgr set work providers.openrouter.base_url https://custom.proxy/v1
```

### 🌱 Profile Lifecycle

| Command                                                        | Description                                                |
| :------------------------------------------------------------- | :--------------------------------------------------------- |
| `hermes pmgr create <name> [--from <src>] [--with-env]`        | Create a new profile                                       |
| `hermes pmgr copy <src> <dst> [--with-env]`                    | Copy a profile                                             |
| `hermes pmgr rename <old> <new>`                               | Rename a profile                                           |
| `hermes pmgr delete <name> [--keep-env] [--no-backup] [--yes]` | Delete a profile (**requires typing the name to confirm**) |

`delete` backs up to `~/.hermes/.backup/` by default.

### 💾 Backup & Migration

| Command                                                                 | Description      |
| :---------------------------------------------------------------------- | :--------------- |
| `hermes pmgr export [profiles...] [--with-env] [--plaintext] [-o FILE]` | Export as YAML   |
| `hermes pmgr import <file> [--no-overwrite]`                            | Import from YAML |

`--plaintext` requires an extra confirmation; by default secrets are masked as `***`.

### 🔑 Environment Variables

| Command                                       | Description                      |
| :-------------------------------------------- | :------------------------------- |
| `hermes pmgr env list <profile>`              | List a profile's `.env` (masked) |
| `hermes pmgr env set <profile> <KEY> <VALUE>` | Set an env var                   |
| `hermes pmgr env unset <profile> <KEY>`       | Unset an env var                 |

---

## 🏗️ Data Structures

`pmgr` strictly follows Hermes' real storage layout and never invents new fields.

### 📁 Directory Layout

```text
~/.hermes/
├── config.yaml # default profile config
├── .env # default profile secrets
├── .backup/ # pmgr automatic backups
│ └── work-20260101-120000/
└── profiles/
├── work/
│ ├── config.yaml
│ └── .env
└── personal/
├── config.yaml
└── .env
```

### 🗂️ `config.yaml` Structure

```yaml
model:
provider: openrouter
default: anthropic/claude-opus-4.6

providers:
openrouter:
name: openrouter
base_url: https://openrouter.ai/api/v1
api_key: ${OPENROUTER_API_KEY} # references .env, never plaintext
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

### 🔐 `.env` Structure

```bash
OPENROUTER_API_KEY=sk-or-v1-xxxx
OPENAI_API_KEY=sk-xxxx
ANTHROPIC_API_KEY=sk-ant-xxxx
```

> **Security principle**: API keys are written only to `.env`; `config.yaml` keeps only `${ENV_VAR}` references. This matches how Hermes' runtime resolution layer reads them.

---

## 🌐 Multi-language

`pmgr` selects the language in the following priority order:

1. `HERMES_LANG` (explicit, `zh` / `en`)
2. `LANG` or `LC_ALL` starting with `zh` → Chinese
3. Default: English

```bash

# Force Chinese

HERMES_LANG=zh hermes pmgr list

# Force English

HERMES_LANG=en hermes pmgr list
```

---

## 🛠️ Development

### Directory Structure

```text
hermes-profile-manager/
└── pmgr/
├── plugin.yaml # plugin manifest
├── **init**.py # registration entry point
├── i18n.py # Chinese / English strings
├── core.py # paths, IO, profile matching, provider helpers
├── commands.py # all non-test commands
├── test_conn.py # connectivity test
└── cli.py # argparse dispatch
```

### Local Development

```bash
git clone https://github.com/metaone01/hermes-profile-manager.git
cd hermes-profile-manager

# Symlink for easy iteration

ln -sf "$(pwd)/pmgr" ~/.hermes/plugins/pmgr

# Restart Hermes after each change

hermes pmgr list
```

### Adding a New Command

1. Implement `plan_xxx()` and `apply_xxx()` in `commands.py`
2. In `cli.py`:
    - Write a `_handle_xxx(args)` handler
    - Register it via `sub.add_parser()` in `register_cli()`
    - Route it through `C.dry_run_then_apply(changes, apply_fn, render_fn)`
3. Add strings to both the `en` and `zh` sections of `i18n.py`

### Adding a New Language

Add a new language block to `MESSAGES` in `i18n.py` and extend `_detect_lang()`.

---

## 🧪 Testing

```bash

# Check state

hermes pmgr list

# Health check

hermes pmgr doctor

# Connectivity test (consumes tokens)

hermes pmgr test work
```

Because the plugin operates on real Hermes configs, back up before testing:

```bash
hermes pmgr export -o backup.yaml
```

---

## ❓ FAQ

<details>
<summary><b>Q: Does the plugin modify Hermes itself?</b></summary>

No. `pmgr` is a pure plugin that only reads and writes files under `~/.hermes/`.

</details>

<details>
<summary><b>Q: Will API keys end up in config.yaml?</b></summary>

No. Secrets are written only to `.env`; `config.yaml` keeps only `${ENV_VAR}` references.

</details>

<details>
<summary><b>Q: Does `delete` permanently remove data?</b></summary>

By default it backs up to `~/.hermes/.backup/` first. Use `--no-backup` to skip.

</details>

<details>
<summary><b>Q: How many tokens does `test` consume?</b></summary>

Usually fewer than 20 tokens per profile. It lists the target profiles and asks for confirmation before running, then reports the actual total consumed.

</details>

<details>
<summary><b>Q: How do I restore from a backup?</b></summary>

Each `~/.hermes/.backup/<name>-<timestamp>/` contains the `config.yaml` and `.env` from that moment; copy them back into `profiles/<name>/`.

</details>

<details>
<summary><b>Q: Which providers are supported?</b></summary>

All providers are dynamically collected from existing configs — there is no hardcoded list. Built-in env var mappings cover OpenRouter / OpenAI / Anthropic / Google / Gemini / Nous / Z.AI / Kimi / MiniMax / KiloCode / OpenCode / Alibaba / Copilot / HuggingFace, etc.; other providers automatically derive `<SLUG>_API_KEY`.

</details>

---

## 🤝 Contributing

Issues and PRs are welcome!

```bash
git checkout -b feature/my-feature
git commit -am "Add my feature"
git push origin feature/my-feature
```

Please make sure:

- Every new command goes through `dry_run_then_apply()`
- Every user-visible string is fetched via `i18n.t()`
- Every write operation has a dry-run preview + confirmation

---

## 🙏 Acknowledgements

- [Hermes](https://github.com/NousResearch/hermes) — the plugin host
- [PyYAML](https://pyyaml.org/) — config parsing
- All contributors and users

---

<p align="center">
  If this project helps you, please consider giving it a ⭐️ Star!
</p>
