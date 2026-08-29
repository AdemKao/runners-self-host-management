# Changelog

All notable changes to `runnerctl` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows semantic versioning for tagged releases.

## [Unreleased]

## [0.7.2] - 2026-08-29

### Fixed
- Legacy `runnerctl queue` started-hook waits are now guarded by a watchdog instead of being able to remain hidden in GitHub `Set up runner` indefinitely.
- TERM/INT/HUP cancellation now terminates the legacy queue child wait and cleans runner waiting/slot state.
- Legacy queue waits default to a 300-second safety limit, configurable with `RUNNERCTL_QUEUE_MAX_WAIT_SECONDS` before `queue enable`.
- `job.started` notifications no longer imply that workflow steps are already executing; rendered text now describes runner assignment/setup semantics.
- Telegram/LINE notification text now includes repository, branch/ref, workflow, GitHub job id, short SHA, run attempt, and a clickable GitHub Actions run URL.
- Webhook/plugin event JSON now includes branch/ref/SHA/navigation metadata and an explicit phase for runner-start and completion hooks.

### Added
- `runnerctl notify doctor RUNNER [--json]` for inspecting hook dispatchers, handler order, notification events, legacy queue state/max wait, scheduler state, warnings, and notification log location without exposing credentials.
- Regression coverage for queue cancellation, bounded max-wait behavior, actionable notification context, and custom-provider hook safety.
- Dedicated v0.7.2 release notes with immediate recovery and scheduler migration guidance.

### Security / reliability
- Custom executable notification providers are skipped by default in synchronous GitHub runner hooks so an unbounded third-party plugin cannot freeze `Set up runner`; explicit audited opt-in is available through `RUNNERCTL_NOTIFY_ALLOW_CUSTOM_HOOK_PROVIDERS=1`.
- Built-in Telegram, LINE, and webhook providers remain bounded by short network timeouts and notification hooks remain fail-open.

### Compatibility / limitations
- The event identifier `job.started` is preserved for compatibility, but it means the synchronous runner setup hook has started, not that workflow steps are already running.
- `runnerctl queue` remains compatibility mode and can still place assigned jobs in GitHub `in progress` / `Set up runner`; `runnerctl scheduler` remains the recommended GitHub-native queued-state mechanism.

## [0.7.1] - 2026-08-23

### Added
- Focused English and Traditional Chinese Telegram Chat ID quickstart guides using the official Bot API `getUpdates` response and `message.chat.id`.
- Explicit private-chat versus group/supergroup recommendations for runner operators.
- Examples for positive private chat IDs, negative group/supergroup IDs, and comma-separated inbound allowlists.
- Dedicated v0.7.1 release notes covering Telegram Chat ID setup and long-polling caveats.

### Changed
- Clarified the difference between `RUNNERCTL_TELEGRAM_CHAT_ID` (single outbound destination / compatibility fallback) and `RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS` (explicit inbound read-only allowlist).
- Bot/API help wording now describes the read-only guarantee as applying to the v0.7.x line.

### Compatibility / limitations
- No scheduler, queue, runner lifecycle, notification delivery, LINE, or Bot/API permission behavior changes are introduced in this patch.
- runnerctl's Telegram controller continues to use `getUpdates` long polling; a separate Telegram webhook configured for the same bot must be removed/disabled before using the long-polling controller.

## [0.7.0] - 2026-08-23

### Added
- `runnerctl bot` read-only query/controller commands for local status, diagnostics, Telegram long polling, and HTTP/LINE serving.
- Fixed read-only remote commands for `status`, `runners`, `queue`, `scheduler`, `health`, and `help`.
- Telegram Bot API inbound command support using `getUpdates` long polling, chat-ID allowlists, and persisted update offsets to avoid replay after restart.
- Authenticated HTTP JSON endpoints for runner, queue, scheduler, and host-health queries, bound to `127.0.0.1` by default.
- LINE Messaging API inbound webhook support with mandatory raw-body `x-line-signature` HMAC-SHA256 verification and user-ID allowlists.
- Optional Python 3.8+ standard-library controller; all existing runnerctl features remain usable without Python.
- systemd/launchd deployment guidance, reverse-proxy/TLS guidance, troubleshooting, rollback, and dedicated v0.7.0 release notes.
- Deterministic controller tests covering fixed command routing, injection rejection, Telegram allowlists/offset persistence, HTTP bearer auth, remote-bind safeguards, LINE signature verification, and user allowlists.

### Changed
- Shell, Homebrew, npm, and GitHub Release packages now include the optional bot controller and its v0.6 compatibility frontend.
- The v0.6 frontend remains an internal compatibility layer while v0.7 adds bot/API discoverability and version-aware upgrade behavior.

### Security
- Remote mutation is intentionally unavailable in v0.7.0. Bot/API clients cannot start, stop, remove, drain, resume, upgrade, or otherwise mutate runnerctl state.
- Chat text is never interpolated into a shell command; only fixed read-only command names map to fixed runnerctl argument vectors.
- Telegram inbound queries require an allowed chat ID.
- LINE webhook requests are verified before JSON parsing, and valid senders must also be present in `RUNNERCTL_LINE_ALLOWED_USER_IDS`.
- HTTP `/v1/*` queries require `RUNNERCTL_BOT_API_TOKEN`; token comparison is constant-time.
- Non-loopback HTTP binding requires both `--allow-remote` and an API token. runnerctl does not provide TLS termination.
- Inbound request bodies are limited to 64 KiB, and bot/controller status output reports credential presence without returning credential values.

### Compatibility / limitations
- Python 3.8+ is required only for `runnerctl bot ...`; it is not a general runnerctl dependency.
- Telegram mode does not require a public listener because it uses long polling.
- LINE inbound commands require a publicly reachable HTTPS webhook, normally provided by a trusted reverse proxy/tunnel in front of the loopback controller.
- Remote mutating commands require a future authorization/audit model and are explicitly out of scope.

## [0.6.0] - 2026-08-23

### Added
- `runnerctl notify` commands for provider discovery, configuration/status inspection, test delivery, manual event emission, and per-runner job notifications.
- Built-in Telegram Bot API, LINE Messaging API, and generic JSON webhook notification providers.
- Executable custom notification providers under `$RUNNERCTL_HOME/plugins/notify/` using a stable stdin JSON event contract.
- Per-runner `job.started` and `job.completed` notifications composed through the existing shared runner hook dispatcher.
- Scheduler control-plane notification events for enable, disable, drain, resume, and command errors.
- Stable notification event schema with host, runner, repository, run, workflow, job, URL, timestamp, and message metadata.
- Comprehensive notification/provider documentation and dedicated v0.6.0 release notes.
- Deterministic fake-curl/provider tests covering Telegram, LINE, webhook payloads, plugin delivery, secret redaction, hook composition, and provider failure behavior.

### Changed
- Shell, Homebrew, npm, and GitHub Release packaging now include the notification dispatcher and built-in providers.
- The v0.5 frontend is retained as an internal compatibility layer while the v0.6 frontend adds notification discoverability and version-aware upgrade behavior.
- Scheduler control commands emit best-effort notification events without changing scheduler command success/failure semantics.

### Security
- Provider credentials are read from environment variables rather than normal runnerctl config or positional CLI arguments.
- `notify status` / `notify providers` expose only configured/not-configured state and never intentionally return Telegram tokens, LINE channel tokens, or webhook authorization values.
- Built-in providers pass authorization material to curl through config stdin instead of command-line arguments.

### Reliability
- Job-hook notification delivery is fail-open so notification outages do not fail CI jobs.
- Built-in providers use bounded network timeouts; hook delivery performs one attempt while manual test/emit commands may retry once and return non-zero for operator diagnostics.

### Compatibility / limitations
- `job.completed` means the GitHub runner completion hook executed; v0.6.0 does not guess the final GitHub job conclusion.
- Exact succeeded/failed notifications require a future GitHub `workflow_job` webhook/event-controller integration.
- Telegram/LINE inbound bot commands such as `/status` are intentionally not included in v0.6.0 because they require a persistent authenticated bot/API controller, long polling or public webhooks, authorization, and replay/rate-limit protections.

## [0.5.0] - 2026-08-22

### Added
- `runnerctl scheduler` for GitHub-native queued-job semantics across runnerctl-managed repository runners.
- Routing-label admission using the default `runnerctl-scheduled` custom label, with configurable `--label`, `--max-concurrency`, and polling interval.
- Scheduler commands for `status`, `enable`, `disable`, `tick`, `run`, `drain`, and `resume`, including stable JSON output for status/tick.
- Best-effort round-robin scheduling across managed repositories while preserving a host-wide concurrency limit.
- Fail-closed reconciliation when runner state or queued-job state cannot be read completely from GitHub.
- Dedicated scheduler architecture/migration guide and detailed v0.5.0 release notes.
- Deterministic fake-GitHub regression coverage for routing-label grants/revocation, drain/resume, busy-runner safety, legacy-queue mutual exclusion, and API failure behavior.

### Changed
- `runnerctl queue` is now explicitly documented as the legacy v0.4 host-side admission gate. It remains supported for backwards compatibility but is no longer described as GitHub-native queueing.
- Scheduled workflows must opt into the new scheduler by adding the configured routing label (default `runnerctl-scheduled`) to `runs-on`.
- Shell, Homebrew, npm, and GitHub Release packaging now include the v0.5 scheduler plus internal v0.4.3 legacy implementations used by compatibility wrappers.
- Scheduler control commands are serialized; manual `scheduler tick` is rejected while the background controller is active to prevent concurrent reconciliation.

### Fixed
- Jobs waiting for scheduler-controlled host capacity can remain in GitHub's `queued` state instead of being assigned first and waiting inside a pre-job hook as `in progress`.
- The scheduler avoids spending a job's `timeout-minutes` budget on runnerctl-side capacity waiting because admission occurs through runner matching before GitHub assignment.

### Compatibility / limitations
- v0.5.0 scheduler supports runnerctl-managed **repository-level** runners. Organization/enterprise runner scheduling is future work.
- Jobs without the scheduler routing label bypass scheduler concurrency control.
- Polling is best-effort and is not strict global FIFO; a just-finished eligible runner can accept another job before the next poll.
- `scheduler enable` starts a convenience background controller that is not reboot-persistent. Production hosts should supervise `runnerctl scheduler run` with a service manager.
- Larger fleets should prefer GitHub `workflow_job` webhooks and/or runner scale-set tooling over aggressive polling.

## [0.4.3] - 2026-08-22

### Fixed
- Shell release installs no longer fail at process exit under `set -u` because temporary-directory cleanup no longer references a function-local variable after it goes out of scope.
- Shell and Homebrew installs now preserve the source-compatible `bin/runnerctl-*` helper layout expected by `runnerctl-base`, so `host`, `ci`, `capacity`, and `queue` commands resolve their installed helpers correctly.
- Existing flattened shell-install helper paths under `libexec/runnerctl/` remain available for compatibility.

### Added
- Tagged-release installer regression coverage that verifies SHA-256 manifests, successful shell exit, installed queue/capacity execution, and queue hook registration without starting a runner service.

## [0.4.2] - 2026-08-22

### Added
- Host capacity inspection via `runnerctl capacity` with human-readable and JSON output.
- Opt-in host-wide job admission control via `runnerctl queue`.
- Queue commands for `status`, `enable`, `disable`, `set`, `drain`, and `resume`.
- A host-wide execution-slot gate so runners from multiple repositories can stay online while limiting how many jobs actually execute concurrently.
- Shared runner hook dispatching so queue admission/release hooks and workspace cleanup hooks can coexist.
- Regression coverage for cross-repository queueing, drain/resume behavior, stale slot recovery, and hook composition.
- Documentation for the global host queue design and GitHub Actions job-assignment semantics.

### Changed
- Shell, Homebrew, npm, and GitHub Release packaging now include the queue and hook helpers.
- Workspace cleanup now uses the shared hook dispatcher instead of owning the GitHub runner completion hook directly.

## [0.4.1] - 2026-08-21

### Added
- `runnerctl ci check OWNER/REPO` for read-only GitHub Actions workflow compatibility scanning.
- `--current-host` comparison for checking whether the current machine satisfies detected workflow requirements.
- Stable JSON output for CI compatibility results.
- Detection for Docker container actions, `docker://` actions, service containers, job containers, and obvious OS-specific commands.
- Migration guidance and deterministic macOS/Linux regression fixtures.

### Changed
- Shell, Homebrew, npm, and GitHub Release packaging now include the CI compatibility helper.

## [0.4.0] - 2026-08-21

### Added
- `runnerctl host inspect` for read-only host prerequisite inspection.
- `runnerctl host bootstrap --dry-run` and `runnerctl host bootstrap` for preparing runner hosts.
- RHEL-compatible Linux 8+ / AlmaLinux support using DNF.
- Debian-family and macOS/Homebrew bootstrap paths.
- GitHub CLI RPM repository setup for supported DNF hosts.
- Deterministic host-bootstrap regression coverage, including AlmaLinux 8.10, CentOS 7, and macOS cases.

### Changed
- Release handling was hardened so GitHub Releases can complete independently when npm publication is unavailable or fails.

### Security
- Host bootstrap deliberately avoids automatic swap, firewall, Docker, credential, and runner-registration changes.

## [0.3.3] - 2026-08-21

### Fixed
- Release-state handling now tracks GitHub Release publication and npm package publication independently.
- npm publication can be retried after a partial release without requiring a new CLI version.
- npm registry visibility is verified after publication.
- The public frontend/core version is checked to prevent version drift.

## [0.3.2] - 2026-08-20

### Added
- `runnerctl cleanup status`, `enable`, `enable-all`, `disable`, and manual cleanup commands.
- `runnerctl add ... --cleanup` for automatically enabling post-job workspace cleanup on newly registered runners.
- GitHub runner completion-hook integration for workspace cleanup.
- Regression coverage for launchd service detection and post-job cleanup behavior.

### Fixed
- macOS launchd status detection now resolves service labels correctly and reports running/stopped state consistently.

### Changed
- Cleanup removes only the completed job's validated `GITHUB_WORKSPACE` contents while preserving package-manager caches, Docker state, and runner logs.

## [0.3.1] - 2026-08-20

### Added
- `runnerctl upgrade` and `runnerctl self-update`.
- `runnerctl upgrade --check` and `runnerctl upgrade --check --json`.
- Installation-method detection for Homebrew, npm, pnpm, and shell installations.
- Upgrade status in the agent contract and project documentation.

### Fixed
- Homebrew wrapper generation now uses the Pathname API correctly, fixing the `ENOTDIR` installation/completion failure from v0.3.0.
- Shell completion generation now runs through the installed `runnerctl` wrapper.

## [0.3.0] - 2026-08-20

### Added
- Agent-friendly command-specific help and discoverability.
- `runnerctl agent` and `runnerctl agent --json` automation contracts.
- Stable JSON output for discovery commands.
- Explicit read-only, mutating, and destructive command guidance.
- Bash, Zsh, and Fish shell completion.
- Homebrew completion generation.
- `AGENTS.md`, `CLAUDE.md`, and the portable `skills/runnerctl/SKILL.md` integration guide.
- Unified distribution across shell install, npm/pnpm, Homebrew, and GitHub Releases.
- English and Traditional Chinese documentation.

## Earlier development

The project began with the initial `runnerctl` implementation for managing multiple GitHub Actions self-hosted runners on one host, including runner registration, service lifecycle management, logs, removal, environment diagnostics, installation tooling, CI, and local isolation guidance.

[Unreleased]: https://github.com/AdemKao/runners-self-host-management/compare/v0.7.2...HEAD
[0.7.2]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.7.2
[0.7.1]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.7.1
[0.7.0]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.7.0
[0.6.0]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.6.0
[0.5.0]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.5.0
[0.4.3]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.4.3
[0.4.2]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.4.2
[0.4.1]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.4.1
[0.4.0]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.4.0
[0.3.3]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.3.3
[0.3.2]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.3.2
[0.3.1]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.3.1
[0.3.0]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.3.0