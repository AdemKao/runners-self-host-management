# GitHub-native scheduler

`runnerctl scheduler` was introduced in v0.5.0 to solve a semantic problem in the v0.4.x host-side queue.

## Queue versus scheduler

### `runnerctl queue` — legacy admission gate

The v0.4.x queue uses GitHub runner `job-started` / `job-completed` hooks. GitHub has already assigned the job when the start hook runs, so the Actions UI reports the job as **in progress** even while runnerctl is waiting for a local host slot.

That makes the legacy gate useful as an emergency host-protection mechanism, but it is **not GitHub-native queueing**. Time spent waiting in the pre-job hook can also consume part of the job's `timeout-minutes` budget.

### `runnerctl scheduler` — GitHub-native queued semantics

The scheduler uses a custom routing label. Managed repository runners stay online, but only runners currently admitted by the scheduler receive the routing label (default: `runnerctl-scheduled`).

A workflow that requests that label has no matching runner until the scheduler grants capacity, so GitHub keeps the job in its normal **queued** state. Once capacity is granted, GitHub assigns the job and it becomes **in progress**.

```text
GitHub queued job
      |
      | requests runnerctl-scheduled
      v
no admitted matching runner
      |
      | runnerctl scheduler grants label
      v
matching runner available
      |
      v
GitHub assigns job -> in progress
```

## Required workflow migration

The scheduler only controls jobs that explicitly request its routing label.

Before:

```yaml
runs-on: [self-hosted, linux, x64]
```

After:

```yaml
runs-on: [self-hosted, linux, x64, runnerctl-scheduled]
```

**Jobs that do not include `runnerctl-scheduled` bypass the scheduler and can still run concurrently.** This is intentional so migration can be performed workflow by workflow.

If you choose a custom label:

```bash
runnerctl scheduler enable --max-concurrency 1 --label low-memory-ci
```

then workflows must request `low-memory-ci` instead.

## Migration from the v0.4 queue

1. Upgrade runnerctl.
2. Disable the legacy admission gate if it is enabled.
3. Add the scheduler routing label to every workflow job that should share the host capacity limit.
4. Enable the scheduler.
5. Verify GitHub Actions shows excess jobs as `queued`, not `in progress`.

```bash
runnerctl queue status
runnerctl queue disable

runnerctl scheduler enable --max-concurrency 1
runnerctl scheduler status
```

For a small Oracle VM with limited memory, start with one slot:

```bash
runnerctl scheduler enable --max-concurrency 1 --interval 30
```

## Commands

```bash
runnerctl scheduler status
runnerctl scheduler status --json
runnerctl scheduler enable --max-concurrency 1
runnerctl scheduler enable --max-concurrency 2 --interval 20
runnerctl scheduler tick
runnerctl scheduler tick --json
runnerctl scheduler drain
runnerctl scheduler resume
runnerctl scheduler disable
runnerctl scheduler run
```

### `enable`

Writes scheduler configuration, performs an initial reconciliation, and starts a local background controller. The initial reconciliation must succeed or the scheduler remains disabled.

### `tick`

Runs one reconciliation cycle. A manual tick is rejected while the background controller is active to avoid concurrent reconciliation accidentally granting too much capacity.

### `drain`

Stops granting new routing capacity. A runner currently reported busy keeps its scheduler label until the job finishes. Idle admitted runners have the label revoked.

### `resume`

Re-enables routing-label grants according to configured capacity.

### `disable`

Stops the local controller and removes the scheduler routing label from managed runners. It does not unregister runners and does not terminate an already-running GitHub job.

### `run`

Runs the scheduler controller in the foreground. This is the recommended entry point when supervising runnerctl with systemd, launchd, Docker, or another process supervisor.

## Controller lifecycle and reboot behavior

`runnerctl scheduler enable` starts a background controller for convenience. That background process is **not a reboot-persistent service in v0.5.0**.

For a production host that must recover automatically after reboot, supervise:

```bash
runnerctl scheduler run
```

with the host's service manager. Future releases may add first-class scheduler service installation.

## Repository and account scope

v0.5.0 supports **repository-level runners managed by runnerctl**. Each runner's `.runnerctl-meta` identifies its repository and GitHub account. The scheduler uses the corresponding authenticated `gh` account for API calls.

Organization-level and enterprise-level runner scheduling is not implemented in v0.5.0.

The GitHub credential used by the scheduler needs permission to:

- read workflow runs/jobs and repository runner state;
- manage custom labels on the repository's self-hosted runners.

If an account cannot read a complete scheduler snapshot, runnerctl fails closed and does not grant additional capacity.

## Polling and fairness limitations

v0.5.0 is intentionally a lightweight polling controller for small runner fleets.

- Default poll interval: 30 seconds.
- It inspects recent queued/in-progress workflow runs and their jobs.
- It is **best-effort round-robin across managed repositories**, not a strict global FIFO queue.
- A runner that still has the scheduler label after completing a job can accept another matching job before the next poll. Host concurrency remains bounded by the number of routing labels granted, but perfect cross-repository fairness is not guaranteed.
- More repositories and shorter intervals mean more GitHub API requests.

For larger fleets or low-latency autoscaling, use GitHub's `workflow_job` webhook and/or GitHub Actions runner scale-set tooling instead of aggressive polling.

## Failure behavior

The scheduler is designed to fail closed when state is uncertain:

- a runner-state API failure prevents new routing-label grants for that reconciliation;
- a queued-job API failure prevents new routing-label grants;
- the scheduler never intentionally revokes capacity from a runner reported busy simply to improve fairness;
- lowering capacity or draining does not terminate an active workflow job;
- scheduler and legacy `runnerctl queue` modes cannot be enabled at the same time.

## Legacy queue remains available

`runnerctl queue` is not removed in v0.5.0. It remains useful when you need a purely local safety gate and cannot modify workflow labels. Its help now clearly identifies it as a legacy admission gate.

Use the legacy gate only when its semantics are acceptable:

```text
GitHub status: in progress
runnerctl state: waiting for host slot
```

Use the scheduler when you need:

```text
GitHub status: queued
runnerctl state: waiting for host capacity
```

## Rollback

To stop using the scheduler:

```bash
runnerctl scheduler disable
```

Then remove `runnerctl-scheduled` from workflow `runs-on` labels. Jobs return to normal GitHub self-hosted-runner routing.

If necessary, the legacy local admission gate can then be enabled separately:

```bash
runnerctl queue enable --max-concurrency 1
```
