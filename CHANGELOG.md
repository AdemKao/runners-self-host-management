# Changelog

All notable changes to `runnerctl` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows semantic versioning for tagged releases.

## [Unreleased]

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

[Unreleased]: https://github.com/AdemKao/runners-self-host-management/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.4.1
[0.4.0]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.4.0
[0.3.3]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.3.3
[0.3.2]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.3.2
[0.3.1]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.3.1
[0.3.0]: https://github.com/AdemKao/runners-self-host-management/releases/tag/v0.3.0
