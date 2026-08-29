# Host-wide global job queue

`runnerctl queue` is the **legacy host-side admission gate** kept for compatibility. For new production setups, prefer `runnerctl scheduler`, which keeps waiting jobs in GitHub's native `queued` state before assignment.

The legacy gate can keep multiple repository-specific GitHub Actions runners online while limiting how many jobs actually execute on one physical host. It is useful on small VMs, but its semantics are different from the scheduler.

## Important GitHub Actions semantics

The legacy gate runs from `ACTIONS_RUNNER_HOOK_JOB_STARTED` **after GitHub has assigned the job**. GitHub executes that hook synchronously and does not provide a built-in timeout.

Therefore a waiting legacy-queue job can appear in GitHub as:

```text
in progress
Set up runner
```

while no workflow step has started yet. This waiting time may consume job timeout semantics and is the main reason the GitHub-native scheduler is preferred.

## v0.7.2 safety watchdog

Legacy queue waits are no longer unbounded.

Default maximum hidden wait:

```text
300 seconds
```

Configure the limit before enabling the gate:

```bash
export RUNNERCTL_QUEUE_MAX_WAIT_SECONDS=120
runnerctl queue enable --max-concurrency 1
```

If a wait exceeds the limit, runnerctl exits the started hook with an explicit error instead of leaving `Set up runner` stuck indefinitely.

TERM, INT, and HUP also terminate the hidden queue child and clean that runner's local waiting/slot files. Cancelling an Actions job should therefore no longer leave the wait loop running indefinitely.

## Inspect capacity

```bash
runnerctl capacity
runnerctl capacity --json
```

The recommendation is conservative. A host around 1 GiB RAM recommends one lightweight concurrent job and zero concurrent Node/Docker-heavy builds.

## Enable the execution gate

```bash
runnerctl queue enable --max-concurrency 1
```

All managed runner services remain online. GitHub can still assign jobs from different repositories, but the synchronous job-start hook waits until a host-wide execution slot is available.

```text
GitHub Actions
  ├─ repo-a job ─→ runner-a ─┐
  ├─ repo-b job ─→ runner-b ─┼─→ legacy runnerctl host gate (max=1) ─→ workload
  └─ repo-c job ─→ runner-c ─┘
```

runnerctl prints a warning when enabling this compatibility mode.

## Status

```bash
runnerctl queue status
runnerctl queue status --json
```

The status includes:

- configured maximum concurrency;
- active slots;
- locally waiting jobs;
- drain state;
- managed runner count;
- legacy max-wait seconds;
- mode (`legacy-admission-gate`).

## Diagnose a runner stuck at Set up runner

If notifications are enabled, use:

```bash
runnerctl notify doctor RUNNER
runnerctl notify doctor RUNNER --json
```

This shows the started/completed hook dispatchers, handler order, queue state, configured max wait, scheduler state, and a warning when the legacy gate is active.

Also inspect:

```bash
runnerctl queue status --json
runnerctl scheduler status --json
```

If you intended to use the scheduler, disable the old gate:

```bash
runnerctl queue disable
```

## Change concurrency

```bash
runnerctl queue set --max-concurrency 2
```

Lowering the limit never terminates an already-running job. If active jobs temporarily exceed the new limit, no new slot is granted until active usage drops below the configured maximum.

## Drain for maintenance

```bash
runnerctl queue drain
```

Active jobs continue. Newly assigned jobs wait at the legacy pre-job gate, subject to the configured max-wait safety limit.

After maintenance:

```bash
runnerctl queue resume
```

## Disable

```bash
runnerctl queue disable
```

Queue hooks are removed and watchdog compatibility files are cleaned. Existing runnerctl workspace-cleanup and notification hooks remain configured because these features use a shared hook dispatcher.

## No external queue service

This feature does not add Redis, RabbitMQ, PostgreSQL, or another scheduler. The local state lives under:

```text
$RUNNERCTL_HOME/queue/
```

Atomic filesystem state protects host-wide slot acquisition. Stale slot entries whose recorded worker process no longer exists are repaired during queue status/acquisition checks.

## Recommended production setup

For a small shared runner host, prefer GitHub-native scheduling:

```bash
runnerctl queue disable
runnerctl scheduler enable --max-concurrency 1
runnerctl scheduler status
```

Workflows that participate in scheduler admission must include the configured scheduler routing label (default `runnerctl-scheduled`) in `runs-on`; see `runnerctl scheduler --help` and `docs/scheduler.md`.

The distinction is:

```text
runnerctl queue
  assignment happens first
  -> GitHub shows in progress / Set up runner
  -> local hook waits

runnerctl scheduler
  routing capacity is controlled before assignment
  -> waiting work remains GitHub queued
  -> preferred production model
```
