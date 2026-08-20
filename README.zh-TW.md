# runnerctl

[English](README.md)

![CI](https://github.com/AdemKao/runners-self-host-management/actions/workflows/ci.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

`runnerctl` 是一個開源 CLI，用來在單一 macOS 或 Linux 主機上管理多個 GitHub Actions self-hosted runner。

它會自動處理 runner 註冊、背景 service、logs、多 GitHub 帳號、自我升級，以及 AI Agent 友善的 CLI discovery。

## 特色

- 為單一 repository 註冊一個或多個 self-hosted runner。
- 同一台主機執行多個 runner instance，支援 jobs 並行。
- macOS 使用 `launchd`、Linux 使用 `systemd`。
- 支援多個 GitHub CLI 帳號與 repository-to-account mapping。
- 統一管理 start、stop、restart、status、remove。
- 查看 runner 與 workflow worker logs。
- 類似 Stripe CLI 的 `COMMAND --help` 可探索介面。
- `runnerctl agent` / `runnerctl agent --json` AI Agent contract。
- Read-only discovery command 支援穩定 JSON。
- Bash、Zsh、Fish completion。
- 支援 Homebrew、npm/pnpm 與 shell installer 自我升級。
- GitHub Release 提供 SHA-256 checksum。

## 系統需求

- macOS（Apple Silicon / Intel）或 Linux（x64 / arm64）
- Bash
- `curl`
- `tar`
- GitHub CLI (`gh`)
- 對要註冊 runner 的 repository 具備 admin 權限

只有使用 npm / pnpm 安裝時需要 Node.js。Linux service 操作可能需要 `sudo`。

## 安裝

### Homebrew / Linuxbrew

```bash
brew tap ademkao/runnerctl https://github.com/AdemKao/runners-self-host-management
brew install --HEAD ademkao/runnerctl/runnerctl
```

### macOS / Linux shell installer

```bash
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh | bash
```

預設位置：

```text
~/.local/bin/runnerctl
~/.local/libexec/runnerctl/runnerctl-core
```

安裝 tagged release 並驗證 SHA-256：

```bash
VERSION="X.Y.Z"
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh \
  | RUNNERCTL_VERSION="$VERSION" bash
```

### npm / pnpm

```bash
npm install -g github:AdemKao/runners-self-host-management
# 或
pnpm add -g github:AdemKao/runners-self-host-management
```

npm registry package 發佈後也可使用：

```bash
npm install -g @ademkao/runnerctl
# 或
pnpm add -g @ademkao/runnerctl
```

## 升級

只檢查是否有新版，不修改系統：

```bash
runnerctl upgrade --check
```

AI Agent / script 可使用 JSON：

```bash
runnerctl upgrade --check --json
```

自動依目前安裝方式升級：

```bash
runnerctl upgrade
```

`self-update` 是 alias：

```bash
runnerctl self-update
```

CLI 會自動判斷安裝來源：

- Homebrew HEAD：`brew update` + `brew upgrade --fetch-HEAD runnerctl`
- Homebrew stable：`brew update` + `brew upgrade runnerctl`
- npm/pnpm：全域安裝最新 tagged GitHub Release
- shell installer：下載最新 Release，驗證 SHA-256，再更新 frontend/core

### v0.3.0 Homebrew 安裝修復

`v0.3.0` 的 Homebrew formula 使用 `write_env_script` API 方式錯誤，可能讓 `/opt/homebrew/Cellar/runnerctl/.../bin` 變成錯誤的 wrapper path，並在 completion generation 出現 `ENOTDIR`。

因為舊版 `runnerctl` 本身可能已無法正常執行，升到 `v0.3.1` 時需要做一次手動修復：

```bash
brew update
brew reinstall --HEAD runnerctl
runnerctl version
```

修復後，之後版本直接使用：

```bash
runnerctl upgrade
```

## 快速開始

```bash
runnerctl doctor
runnerctl auth login
runnerctl auth list
```

多 GitHub 帳號可以建立 mapping：

```bash
runnerctl auth map 'example-org/*' work-account
runnerctl auth map 'example-user/*' personal-account
```

建立兩個 runner：

```bash
runnerctl add example-org/example-repo \
  --count 2 \
  --labels local,ci
```

查看：

```bash
runnerctl list
```

Workflow example：

```yaml
jobs:
  test:
    runs-on: [self-hosted, local, ci]
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/test.sh
```

一個 runner process 同時處理一個 job；兩個 idle runner 可同時處理兩個符合條件的 jobs。

## 可探索 Help

```bash
runnerctl --help
runnerctl add --help
runnerctl auth --help
runnerctl upgrade --help
runnerctl remove --help
runnerctl help add
```

會改變狀態的 command help 會列出 `Side effects` 與 `AI AGENT` 注意事項。

## AI Agent 與自動化

人類可讀 contract：

```bash
runnerctl agent
```

Machine-readable contract：

```bash
runnerctl agent --json
```

建議 agent preflight：

```bash
runnerctl doctor --json
runnerctl auth list --json
runnerctl auth mappings --json
runnerctl list --json
runnerctl upgrade --check --json
runnerctl auth resolve example-org/example-repo --json
runnerctl add --help
```

Agent 讀 logs 時使用有限輸出：

```bash
runnerctl logs example-runner-01 --no-follow
runnerctl job-logs example-runner-01 --no-follow
```

除非使用者明確要求移除指定 runner，否則不要使用 `remove --yes`。

Repository Agent 規則放在 [AGENTS.md](AGENTS.md)，可攜式 skill 在 [skills/runnerctl/SKILL.md](skills/runnerctl/SKILL.md)。

## JSON Output

```bash
runnerctl doctor --json
runnerctl list --json
runnerctl status example-runner-01 --json
runnerctl auth list --json
runnerctl auth status --json
runnerctl auth doctor --json
runnerctl auth mappings --json
runnerctl auth resolve example-org/example-repo --json
runnerctl upgrade --check --json
```

預設仍是 human-readable output。

## 多 GitHub 帳號

`runnerctl` 使用 GitHub CLI 已登入的帳號，不自行保存 GitHub access token。

```bash
runnerctl auth list
runnerctl auth status
runnerctl auth map 'example-org/*' work-account
runnerctl auth resolve example-org/example-repo
```

帳號解析順序：

1. command 明確指定的 `--account ACCOUNT`
2. 完整 `OWNER/REPO` mapping
3. `OWNER/*` mapping
4. GitHub CLI active account

仍可以切換 global active account：

```bash
runnerctl auth use work-account
```

但自動化流程優先使用 mapping 或 `--account`。

HTTPS Git remote：

```bash
runnerctl auth setup-git
```

SSH key 仍由 `~/.ssh/config` 控制。

## Runner Lifecycle

```bash
runnerctl list
runnerctl status example-runner-01
runnerctl start example-runner-01
runnerctl stop example-runner-01
runnerctl restart example-runner-01
runnerctl start-all
runnerctl stop-all
runnerctl remove example-runner-01
```

只有確定要移除時才跳過 confirmation：

```bash
runnerctl remove example-runner-01 --yes
```

## Logs

```bash
runnerctl logs example-runner-01
runnerctl job-logs example-runner-01
```

Agent / automation 請使用 `--no-follow`。

## Shell Completion

```bash
runnerctl completion bash
runnerctl completion zsh
runnerctl completion fish
```

Homebrew 會自動安裝產生的 Bash、Zsh、Fish completion。

## 資料位置

```text
~/.local/share/runnerctl/
├── cache/
└── runners/
    └── example-runner-01/
        ├── .runnerctl-meta
        ├── _diag/
        ├── _work/
        └── svc.sh

~/.config/runnerctl/accounts.tsv
```

## 並行與隔離

同一台主機上的 runner instances 會共用 CPU、RAM、disk、Docker 與 network resources。

Docker Compose 建議每個 workflow run 使用不同 project name：

```bash
docker compose -p "ci-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" up -d
```

如果 jobs 可能並行，不要共用固定 host port 或 global named resource。

## 安全性

Self-hosted runner 會直接在主機上執行 workflow code。只有可信任的 repository 與 workflow 才應連到含有重要 credentials 或資料的 runner host。

Registration/removal token 只在需要時取得，不會持久化到 runnerctl mapping 或 metadata。

詳見 [SECURITY.md](SECURITY.md)。

## Release 與發佈

新的 CLI/package version merge 到 `main` 後，在該版本尚未存在 Release 時會觸發 release workflow，驗證版本一致、跑 tests，並產生：

```text
runnerctl
runnerctl.sha256
runnerctl-core
runnerctl-core.sha256
runnerctl-X.Y.Z.tar.gz
runnerctl-X.Y.Z.tar.gz.sha256
```

有設定 `NPM_TOKEN` 時也會 publish npm package。

## 開發

```bash
bash tests/smoke.sh
npm pack --dry-run
ruby -c Formula/runnerctl.rb
```

請閱讀 [CONTRIBUTING.md](CONTRIBUTING.md) 與 [AGENTS.md](AGENTS.md)。

## Roadmap

- Organization-level runner pools / runner groups
- GitHub-side online / busy health reporting
- Host-level concurrency / resource limits
- 從 Release 自動產生 stable versioned Homebrew formula
- Debian (`.deb`) 與 RPM package
- 更完整的 runner/account completion

## License

MIT，詳見 [LICENSE](LICENSE)。
