# runnerctl

[English](README.md)

![CI](https://github.com/AdemKao/runners-self-host-management/actions/workflows/ci.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

`runnerctl` 是一個開源 CLI，用來在單一 macOS 或 Linux 主機上管理多個 GitHub Actions self-hosted runner。

它會自動處理 runner 下載、註冊、背景 service、logs 與多 GitHub 帳號。從 v0.3 開始，CLI 也提供給 AI coding agent 與自動化工具使用的正式 contract。

## 特色

- 為單一 repository 註冊一個或多個 self-hosted runner。
- 同一台主機可執行多個 runner instance，讓多個 jobs 並行。
- macOS 使用 `launchd`，Linux 使用 `systemd`。
- 支援多個 GitHub CLI 帳號，不自行保存 runner registration token。
- 可將 repository owner 或個別 repository 對應到指定 GitHub 帳號。
- 統一管理 start、stop、restart、status、remove。
- 查看 runner 與 workflow worker diagnostic logs。
- 類似 Stripe CLI 的可探索 help：`COMMAND --help` 與 `help COMMAND`。
- AI agent contract：`runnerctl agent` 與 `runnerctl agent --json`。
- Read-only discovery 指令支援 machine-readable JSON。
- 支援 Bash、Zsh、Fish completion 產生器。
- 支援 shell、npm/pnpm、Homebrew/Linuxbrew 安裝，不需要手動 clone repository。
- GitHub Release 提供 SHA-256 checksum。

## 系統需求

- macOS（Apple Silicon / Intel）或 Linux（x64 / arm64）
- Bash
- `curl`
- `tar`
- GitHub CLI (`gh`)
- 對要註冊 runner 的 repository 具備 admin 權限

只有使用 npm / pnpm 安裝時需要 Node.js。Linux service 操作可能需要 `sudo`，因為官方 GitHub runner service script 會使用 systemd。

## 安裝

### macOS / Linux shell installer

安裝目前 `main` 版本：

```bash
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh | bash
```

預設會安裝到：

```text
~/.local/bin/runnerctl
~/.local/libexec/runnerctl/runnerctl-core
```

自訂 prefix：

```bash
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh \
  | PREFIX="$HOME/.local" bash
```

安裝 tagged release 並驗證 checksum：

```bash
VERSION="X.Y.Z"
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh \
  | RUNNERCTL_VERSION="$VERSION" bash
```

### npm / pnpm

不 clone repository，直接從 GitHub 安裝：

```bash
npm install -g github:AdemKao/runners-self-host-management
```

或：

```bash
pnpm add -g github:AdemKao/runners-self-host-management
```

Repository 已準備好 npm package `@ademkao/runnerctl`。正式發佈到 npm registry 後可使用：

```bash
npm install -g @ademkao/runnerctl
# 或
pnpm add -g @ademkao/runnerctl
```

### Homebrew / Linuxbrew

```bash
brew tap ademkao/runnerctl https://github.com/AdemKao/runners-self-host-management
brew install --HEAD ademkao/runnerctl/runnerctl
```

### 開發安裝

```bash
git clone https://github.com/AdemKao/runners-self-host-management.git
cd runners-self-host-management
bash install.sh
```

## 快速開始

先確認主機環境：

```bash
runnerctl doctor
```

如果尚未登入 GitHub CLI：

```bash
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

查看狀態：

```bash
runnerctl list
```

GitHub Actions workflow 可以使用相同 labels：

```yaml
jobs:
  test:
    runs-on: [self-hosted, local, ci]
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/test.sh
```

一個 runner process 同時間只能執行一個 job。兩個 idle runner instance 就能同時執行兩個符合條件的 jobs。

## 可探索的 Help

根層 help 依用途分組：

```bash
runnerctl --help
```

重要 command 都有自己的 help：

```bash
runnerctl add --help
runnerctl auth --help
runnerctl auth map --help
runnerctl remove --help
runnerctl help add
```

會改變狀態的 command help 會直接列出 `Side effects`，並提供 `AI AGENT` 注意事項，讓人與 agent 在執行前知道風險。

## AI Agent 與自動化

`runnerctl` 針對 Codex、Claude Code、OpenCode、Cursor 與其他 coding agent 提供可探索的操作 contract。

人類可讀：

```bash
runnerctl agent
```

Machine-readable：

```bash
runnerctl agent --json
```

Contract 會把 command 分成 read-only、mutating、destructive，並提供 exit code 與建議 discovery sequence。

典型的 agent-safe preflight：

```bash
runnerctl doctor --json
runnerctl auth list --json
runnerctl auth mappings --json
runnerctl list --json
runnerctl auth resolve example-org/example-repo --json
runnerctl add --help
```

Agent 讀 logs 時應使用有限輸出：

```bash
runnerctl logs example-runner-01 --no-follow
runnerctl job-logs example-runner-01 --no-follow
```

除非使用者明確要求移除指定 runner，否則不要使用 `remove --yes`。

Repository 層的 agent 規則放在 [AGENTS.md](AGENTS.md)，可攜式 skill 放在 [skills/runnerctl/SKILL.md](skills/runnerctl/SKILL.md)。`CLAUDE.md` 讓 Claude Code 指向相同的 canonical instructions。

## JSON Output

Read-only discovery command 支援穩定 JSON：

```bash
runnerctl doctor --json
runnerctl list --json
runnerctl status example-runner-01 --json
runnerctl auth list --json
runnerctl auth status --json
runnerctl auth doctor --json
runnerctl auth mappings --json
runnerctl auth resolve example-org/example-repo --json
```

例如：

```json
{
  "runners": [
    {
      "name": "example-runner-01",
      "repository": "example-org/example-repo",
      "account": "work-account",
      "status": "running",
      "labels": ["local", "ci"]
    }
  ]
}
```

預設仍是給人看的輸出，只有明確指定 `--json` 才使用 structured output。

## 多 GitHub 帳號

`runnerctl` 使用 GitHub CLI 已登入的帳號，不自行保存 GitHub access token。

```bash
runnerctl auth list
runnerctl auth status
```

建立 mapping：

```bash
runnerctl auth map 'example-org/*' work-account
runnerctl auth map example-user/example-repo personal-account
```

確認某個 repository 最後會使用哪個帳號：

```bash
runnerctl auth resolve example-org/example-repo
```

帳號解析順序：

1. command 明確指定的 `--account ACCOUNT`。
2. 完整 `OWNER/REPO` mapping。
3. `OWNER/*` mapping。
4. GitHub CLI 目前 active account。

仍可直接切換 global active account：

```bash
runnerctl auth use work-account
```

但這會改變 global `gh` state，所以 agent 或自動化流程應優先使用 mapping 或 `--account`。

### Git 認證是另一套機制

HTTPS remote 可以使用：

```bash
runnerctl auth setup-git
```

SSH remote 則由 `~/.ssh/config` 決定 SSH key。`runnerctl auth use` 不會切換 SSH key。

查看目前 context：

```bash
runnerctl auth doctor
```

## Runner Lifecycle

```bash
runnerctl list
runnerctl status example-runner-01
runnerctl start example-runner-01
runnerctl stop example-runner-01
runnerctl restart example-runner-01
runnerctl start-all
runnerctl stop-all
```

互動式移除：

```bash
runnerctl remove example-runner-01
```

只有確定要移除時才跳過 confirmation：

```bash
runnerctl remove example-runner-01 --yes
```

## Logs

Runner connection/service log：

```bash
runnerctl logs example-runner-01
```

Workflow worker log：

```bash
runnerctl job-logs example-runner-01
```

自動化與 AI agent 應使用 `--no-follow`。

## Shell Completion

產生 completion：

```bash
runnerctl completion bash
runnerctl completion zsh
runnerctl completion fish
```

例如 Zsh：

```bash
runnerctl completion zsh > ~/.zfunc/_runnerctl
```

再依照你原本的 shell completion 設定載入即可。

## 資料位置

預設 runner data：

```text
~/.local/share/runnerctl/
├── cache/
└── runners/
    └── example-runner-01/
        ├── .runnerctl-meta
        ├── _diag/
        ├── _work/
        └── svc.sh
```

Account mappings：

```text
~/.config/runnerctl/accounts.tsv
```

可自訂：

```bash
export RUNNERCTL_HOME="$HOME/github-runners"
export RUNNERCTL_CONFIG_HOME="$HOME/.config/runnerctl"
```

## 並行與隔離

同一台主機上的 runner instances 會共用 CPU、RAM、disk、Docker 與 network resources。

Docker Compose 建議每個 workflow run 使用不同 project name：

```bash
docker compose -p "ci-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" up -d
```

如果 jobs 可能並行，不要共用固定 host port 或 globally named resource。

## 安全性

Self-hosted runner 會直接在主機上執行 workflow code。只有可信任的 repositories 與 workflows 才應該連到含有重要 credentials 或資料的 runner host。

`runnerctl` 只會在需要時取得短效 registration/removal token，不會把 token 寫入 runnerctl mapping 或 metadata。

完整政策請見 [SECURITY.md](SECURITY.md)。

## Release 與發佈

新的 public CLI/package version merge 到 `main` 後，可由 release workflow 自動建立 release。流程會確認 public CLI version 與 `package.json` 一致、執行測試，並產生：

```text
runnerctl
runnerctl.sha256
runnerctl-core
runnerctl-core.sha256
runnerctl-X.Y.Z.tar.gz
runnerctl-X.Y.Z.tar.gz.sha256
```

如果有設定 `NPM_TOKEN`，同一次 release 也會 publish npm package；沒有設定時 GitHub Release 仍可完成，只跳過 npm publish。

## 開發

送出變更前：

```bash
bash tests/smoke.sh
npm pack --dry-run
ruby -c Formula/runnerctl.rb
```

請閱讀 [CONTRIBUTING.md](CONTRIBUTING.md) 與 [AGENTS.md](AGENTS.md)。

## Roadmap

- Organization-level runner pools 與 runner groups。
- GitHub-side online / busy health reporting。
- Host-level concurrency / resource limits。
- 從 release 自動產生 stable versioned Homebrew formula。
- Debian (`.deb`) 與 RPM package。
- 更完整的 runner/account name completion。

## License

MIT，詳見 [LICENSE](LICENSE)。
