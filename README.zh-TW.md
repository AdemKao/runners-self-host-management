# runnerctl

[English](README.md)

![CI](https://github.com/AdemKao/runners-self-host-management/actions/workflows/ci.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

`runnerctl` 是一個小型開源 CLI，用來在單一 macOS 或 Linux 主機上管理多個 GitHub Actions self-hosted runner。

它適合想使用本機或專用 CI 主機的開發者與小型團隊，避免每個 repository、每個 runner 都要手動重複 GitHub 提供的安裝與註冊步驟。

## 功能

- 為單一 repository 註冊一個或多個 self-hosted runner。
- 在同一台主機上同時執行多個 runner instance。
- macOS 使用 `launchd`、Linux 使用 `systemd` 背景管理 runner service。
- 支援多個 GitHub CLI 帳號，而且不自行保存長效憑證。
- 可將 repository owner 或個別 repository 對應到指定 GitHub 帳號。
- 統一進行啟動、停止、重啟、狀態查詢與移除。
- 查看 runner 與 workflow worker 的 diagnostic logs。
- 支援 shell、npm/pnpm、Homebrew HEAD 安裝，不需要手動 clone 專案。
- Tagged release 可產生 SHA-256 checksum。

## 系統需求

執行環境：

- macOS（Apple Silicon / Intel）或 Linux（x64 / arm64）
- Bash
- `curl`
- `tar`
- GitHub CLI (`gh`)
- 對要註冊 runner 的 repository 具備 admin 權限

只有使用 npm / pnpm 安裝時才需要 Node.js 生態系工具。

## 安裝

### macOS / Linux 安裝腳本

安裝目前 `main` 版本：

```bash
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh | bash
```

預設安裝到 `~/.local/bin/runnerctl`。可以透過 `PREFIX` 修改：

```bash
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh | PREFIX="$HOME/.local" bash
```

安裝特定 tagged release 時可指定 `RUNNERCTL_VERSION`。Tagged release 安裝流程會先驗證 SHA-256 checksum：

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

此專案也已準備好發布為 npm package `@ademkao/runnerctl`。正式發布到 npm registry 後可使用：

```bash
npm install -g @ademkao/runnerctl
# 或
pnpm add -g @ademkao/runnerctl
```

### Homebrew / Linuxbrew

Repository 內含 HEAD formula，可直接將此 repository 加為 custom tap：

```bash
brew tap ademkao/runnerctl https://github.com/AdemKao/runners-self-host-management
brew install --HEAD ademkao/runnerctl/runnerctl
```

此方式可用於 macOS Homebrew 與 Linuxbrew。

### 開發安裝

貢獻者仍可使用 clone：

```bash
git clone https://github.com/AdemKao/runners-self-host-management.git
cd runners-self-host-management
bash install.sh
```

## 快速開始

確認環境：

```bash
runnerctl doctor
```

尚未登入 GitHub CLI 時：

```bash
runnerctl auth login
runnerctl auth list
```

如果有多個 GitHub 帳號，可以建立 repository 對應：

```bash
runnerctl auth map 'example-org/*' work-account
runnerctl auth map 'example-user/*' personal-account
```

為一個 repository 建立兩個可並行執行的 runners：

```bash
runnerctl add example-org/example-repo \
  --count 2 \
  --labels local,ci
```

查看 runner：

```bash
runnerctl list
```

GitHub Actions workflow 可使用相同 labels：

```yaml
jobs:
  test:
    runs-on: [self-hosted, local, ci]
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/test.sh
```

如果兩個 runner 都是 idle，兩個符合條件的 jobs 就可以同時執行。

## 指令

```text
runnerctl doctor

runnerctl auth list
runnerctl auth status
runnerctl auth use ACCOUNT
runnerctl auth login [GH_AUTH_LOGIN_OPTIONS...]
runnerctl auth setup-git
runnerctl auth doctor
runnerctl auth map OWNER/REPO|OWNER/* ACCOUNT
runnerctl auth unmap OWNER/REPO|OWNER/*
runnerctl auth mappings
runnerctl auth resolve OWNER/REPO

runnerctl add OWNER/REPO [--count N] [--labels a,b] [--name-prefix PREFIX] [--account ACCOUNT]
runnerctl list
runnerctl status [RUNNER]
runnerctl start RUNNER
runnerctl stop RUNNER
runnerctl restart RUNNER
runnerctl start-all
runnerctl stop-all
runnerctl logs RUNNER [--no-follow]
runnerctl job-logs RUNNER [--no-follow]
runnerctl remove RUNNER [--yes] [--account ACCOUNT]
runnerctl version
```

## 多 GitHub 帳號

GitHub CLI 可以在同一個 host 保存多個已登入帳號。`runnerctl` 直接使用這些既有登入資訊，不會自行保存 token。

查看帳號：

```bash
runnerctl auth list
```

如果真的要切換目前 `gh` 的 active account：

```bash
runnerctl auth use work-account
```

日常 runner 操作比較推薦建立 mapping，而不是一直切換 global active account：

```bash
runnerctl auth map 'example-org/*' work-account
runnerctl auth map example-user/example-repo personal-account
```

帳號解析優先順序：

1. 指令上的 `--account ACCOUNT`；
2. 完整 `OWNER/REPO` mapping；
3. `OWNER/*` mapping；
4. GitHub CLI 目前的 active account。

查看某個 repository 最後會使用哪個帳號：

```bash
runnerctl auth resolve example-org/example-repo
```

Mapping 只保存帳號名稱，credential 仍由 GitHub CLI 管理。

### Git 認證與 GitHub CLI 認證不同

`gh` authentication 與 Git SSH authentication 是兩套不同機制。

HTTPS remote 可以讓 Git 使用 GitHub CLI credential：

```bash
runnerctl auth setup-git
```

SSH remote 則仍由 SSH configuration 決定使用哪一把 key。`runnerctl auth use` 不會修改 `~/.ssh/config` 或 SSH key。

可以使用：

```bash
runnerctl auth doctor
```

查看 active GitHub account、Git protocol、目前 repository remote，以及最後解析出的 runner account。

## Runner 資料位置

預設資料：

```text
~/.local/share/runnerctl/
├── cache/
└── runners/
    ├── example-runner-01/
    │   ├── .runnerctl-meta
    │   ├── _diag/
    │   ├── _work/
    │   └── svc.sh
    └── example-runner-02/
```

帳號 mapping 另外放在：

```text
~/.config/runnerctl/accounts.tsv
```

可透過環境變數修改：

```bash
export RUNNERCTL_HOME="$HOME/github-runners"
export RUNNERCTL_CONFIG_HOME="$HOME/.config/runnerctl"
```

## Logs

Runner connection / service log：

```bash
runnerctl logs example-runner-01
```

最新 workflow worker log：

```bash
runnerctl job-logs example-runner-01
```

加上 `--no-follow` 會輸出最後 200 行後結束。

## 並行執行與隔離

同一台主機上的多個 runner instance 可以同時執行 jobs，但仍會共用 CPU、RAM、disk、Docker 與 network resource。

如果 CI 使用 Docker Compose，建議每個 workflow run 都使用不同 project name：

```bash
docker compose -p "ci-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" up -d
```

如果 jobs 可能並行，不要共用固定 host ports 或 globally named resources。

## 安全性

Self-hosted runner 會直接在主機上執行 workflow code。只有可信任的 repositories 與 workflows 才應該連到含有重要 credential 或本機資料的 runner host。

`runnerctl` 不會保存 GitHub runner registration/removal token，需要時才會透過選定的 GitHub CLI 帳號取得短效 token。

完整安全政策請參考 [SECURITY.md](SECURITY.md)。

## Release 與發佈

`v*` tag 會觸發 release workflow。流程會先確認 Git tag、CLI version 與 npm package version 一致，再產生：

```text
runnerctl
runnerctl.sha256
runnerctl-<version>.tar.gz
runnerctl-<version>.tar.gz.sha256
```

如果 repository 有設定 `NPM_TOKEN` secret，同一個 tag workflow 也會發布 npm package。沒有設定時，GitHub Release 仍可正常完成，只跳過 npm publish。

## 開發

執行 smoke tests：

```bash
bash tests/smoke.sh
```

確認 npm package：

```bash
npm pack --dry-run
```

檢查 Homebrew formula syntax：

```bash
ruby -c Formula/runnerctl.rb
```

送出 pull request 前請先閱讀 [CONTRIBUTING.md](CONTRIBUTING.md)。

## Roadmap

- Organization-level runner pools 與 runner groups。
- GitHub-side online / busy health reporting。
- Host-level concurrency / resource limits。
- 從正式 release 自動產生 stable Homebrew formula。
- Debian (`.deb`) 與 RPM packages。

## License

MIT，詳見 [LICENSE](LICENSE)。
