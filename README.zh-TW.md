# runnerctl

[English](README.md)

![CI](https://github.com/AdemKao/runners-self-host-management/actions/workflows/ci.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

`runnerctl` 是一個開源 CLI，用來在單一 macOS 或 Linux 主機上管理多個 GitHub Actions self-hosted runner。

它會自動處理 runner 註冊、背景 service、logs、多 GitHub 帳號、自我升級、GitHub-native scheduling、通知，以及 AI Agent 友善的 CLI discovery。

## 特色

- 為單一 repository 註冊一個或多個 self-hosted runner。
- 同一台主機執行多個 runner instance，支援 jobs 並行。
- macOS 使用 `launchd`、Linux 使用 `systemd`。
- 支援多個 GitHub CLI 帳號與 repository-to-account mapping。
- 統一管理 start、stop、restart、status、remove。
- GitHub-native queue scheduler 與 host concurrency 控制。
- Telegram、LINE、generic webhook 與自訂 executable notification provider。
- 選配的 read-only Telegram / LINE / HTTP API controller，可遠端查詢 runnerctl 狀態。
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

**Python 3.8+ 是選配，只在使用 `runnerctl bot ...` Telegram / LINE / HTTP controller 時需要。其他 runnerctl 功能不需要 Python。**

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

```bash
runnerctl upgrade --check
runnerctl upgrade --check --json
runnerctl upgrade
```

`self-update` 是 alias。CLI 會依 Homebrew、npm/pnpm 或 shell installer 選擇正確升級方式。

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

建立 runner：

```bash
runnerctl add example-org/example-repo \
  --count 2 \
  --labels local,ci
```

查看：

```bash
runnerctl list
```

## Scheduler、通知與遠端查詢

這三層是不同功能：

```text
runnerctl scheduler
  GitHub-native queued-job admission / host concurrency

runnerctl notify
  runnerctl -> Telegram / LINE / webhook / custom provider

runnerctl bot
  Telegram / LINE / authenticated HTTP client -> read-only runnerctl query
```

完整文件：

- Scheduler：[docs/scheduler.md](docs/scheduler.md)
- Notification / provider：[docs/notifications.md](docs/notifications.md)
- Read-only Bot/API：[docs/bot-controller.md](docs/bot-controller.md)

### Bot/API controller

先檢查環境，輸出不會包含 token/secret：

```bash
runnerctl bot doctor --json
```

本機 read-only query：

```bash
runnerctl bot query status --json
runnerctl bot query runners --json
runnerctl bot query queue --json
runnerctl bot query scheduler --json
runnerctl bot query health --json
```

### Telegram

Telegram 使用 long polling，不需要開 public inbound port：

```bash
export RUNNERCTL_TELEGRAM_BOT_TOKEN='...'
export RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS='123456789'
runnerctl bot telegram run
```

支援：

```text
/status
/runners
/queue
/scheduler
/health
/help
```

未列在 allowlist 的 chat 不會執行查詢。runnerctl 會保存 Telegram update offset，避免重啟後重複處理已收到的 update。

### HTTP API / LINE webhook

啟動預設只綁 localhost 的 controller：

```bash
export RUNNERCTL_BOT_API_TOKEN='use-a-long-random-value'
runnerctl bot serve --bind 127.0.0.1 --port 8765
```

HTTP API：

```text
GET /v1/status
GET /v1/runners
GET /v1/queue
GET /v1/scheduler
GET /v1/health
```

`/v1/*` 需要：

```text
Authorization: Bearer <RUNNERCTL_BOT_API_TOKEN>
```

LINE 使用：

```text
POST /v1/line/webhook
```

需要：

```bash
export RUNNERCTL_LINE_CHANNEL_SECRET='...'
export RUNNERCTL_LINE_CHANNEL_ACCESS_TOKEN='...'
export RUNNERCTL_LINE_ALLOWED_USER_IDS='U...'
```

runnerctl 會在解析 JSON **之前**以 channel secret 驗證 `x-line-signature`。Signature 不正確直接回 HTTP 401，不會執行任何 command。

LINE webhook 必須透過公開 HTTPS URL 接收。建議讓 runnerctl 繼續只綁 `127.0.0.1`，再由可信任的 HTTPS reverse proxy / tunnel 對外提供 `/v1/line/webhook`。

### Read-only 安全邊界

v0.7.0 遠端 controller **不提供**：

```text
/drain
/resume
/start
/stop
/restart
/remove
/upgrade
```

Chat 文字不會直接傳給 shell，也不會變成任意 runnerctl command。只有固定的 read-only command mapping 可以執行。

非 loopback bind 必須同時有：

```text
--allow-remote
RUNNERCTL_BOT_API_TOKEN
```

runnerctl 本身不提供 TLS termination。

## AI Agent 與 JSON

```bash
runnerctl agent
runnerctl agent --json
runnerctl doctor --json
runnerctl list --json
runnerctl notify status --json
runnerctl bot doctor --json
runnerctl bot query status --json
runnerctl upgrade --check --json
```

Agent 讀 logs 時請使用：

```bash
runnerctl logs example-runner-01 --no-follow
runnerctl job-logs example-runner-01 --no-follow
```

除非使用者明確要求移除指定 runner，否則不要使用 `remove --yes`。

Repository Agent 規則放在 [AGENTS.md](AGENTS.md)，可攜式 skill 在 [skills/runnerctl/SKILL.md](skills/runnerctl/SKILL.md)。

## 多 GitHub 帳號

`runnerctl` 使用 GitHub CLI 已登入的帳號，不自行保存 GitHub access token。

```bash
runnerctl auth list
runnerctl auth status
runnerctl auth map 'example-org/*' work-account
runnerctl auth resolve example-org/example-repo
```

解析順序：explicit `--account` → exact repo mapping → owner wildcard mapping → GitHub CLI active account。

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

只有確定要移除時才使用：

```bash
runnerctl remove example-runner-01 --yes
```

## Logs

```bash
runnerctl logs example-runner-01
runnerctl job-logs example-runner-01
```

Automation 請使用 `--no-follow`。

## Shell Completion

```bash
runnerctl completion bash
runnerctl completion zsh
runnerctl completion fish
```

## 資料位置

```text
~/.local/share/runnerctl/
├── bot/
│   └── telegram.offset
├── cache/
├── notify/
├── plugins/
│   └── notify/
└── runners/
    └── example-runner-01/
        ├── .runnerctl-meta
        ├── _diag/
        ├── _work/
        └── svc.sh

~/.config/runnerctl/accounts.tsv
```

## 並行與隔離

同一台主機上的 runner instances 會共用 CPU、RAM、disk、Docker 與 network resources。GitHub-native scheduler 可用來讓額外 jobs 保持 GitHub `queued`，避免主機超載。

Docker Compose 建議每個 workflow run 使用不同 project name：

```bash
docker compose -p "ci-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" up -d
```

## 安全性

Self-hosted runner 會直接在主機上執行 workflow code。只有可信任的 repository 與 workflow 才應連到含有重要 credentials 或資料的 runner host。

Registration/removal token 只在需要時取得，不會持久化到 runnerctl mapping 或 metadata。

Bot/API token 與 LINE/Telegram secrets 使用 environment 設定；請使用權限受限的 service environment file，不要提交進 repo 或輸出到 logs。

詳見 [SECURITY.md](SECURITY.md) 與 [docs/bot-controller.md](docs/bot-controller.md)。

## Release 與發佈

新的 CLI/package version merge 到 `main` 後，在該版本尚未存在 Release 時會觸發 release workflow，跑 tests 並建立 standalone artifacts、SHA-256 manifests 與 source-compatible tarball。

有設定 `NPM_TOKEN` 時也會 publish npm package；npm publish 失敗不會阻止 GitHub Release 建立。

版本紀錄：[CHANGELOG.md](CHANGELOG.md)

## 開發

```bash
bash tests/smoke.sh
bash tests/scheduler.sh
bash tests/notify.sh
python3 tests/test_bot_controller.py
npm pack --dry-run
ruby -c Formula/runnerctl.rb
```

請閱讀 [CONTRIBUTING.md](CONTRIBUTING.md) 與 [AGENTS.md](AGENTS.md)。

## Roadmap

- Organization-level runner pools / runner groups
- GitHub-side online / busy health reporting
- Scheduler / Bot controller 的 persistent service helper
- 未來 remote operator action 的 audit / permission model
- stable versioned Homebrew formula
- Debian (`.deb`) 與 RPM package
- 更完整的 runner/account completion

## License

MIT，詳見 [LICENSE](LICENSE)。
