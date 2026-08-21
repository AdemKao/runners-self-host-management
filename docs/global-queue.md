# Host-wide global job queue

`runnerctl` can keep multiple repository-specific GitHub Actions runners online while limiting how many jobs actually execute on one physical host.

This is useful when a small VM is registered with several repositories and GitHub would otherwise dispatch one job to each idle runner at the same time.

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

All managed runner services remain online. GitHub can still assign jobs from different repositories, but the job-start hook waits until a host-wide execution slot is available.

```text
GitHub Actions
  ├─ repo-a job ─→ runner-a ─┐
  ├─ repo-b job ─→ runner-b ─┼─→ runnerctl host gate (max=1) ─→ workload
  └─ repo-c job ─→ runner-c ─┘
```

GitHub remains the source of truth for workflow/job state. Because assignment happens before the local gate, a GitHub job may appear started while its runnerctl pre-job hook is waiting for a local slot.

## Status

```bash
runnerctl queue status
runnerctl queue status --json
```

The status reports configured maximum concurrency, active slots, locally waiting jobs, drain state, and managed runner count.

## Change concurrency

```bash
runnerctl queue set --max-concurrency 2
```

Lowering the limit never terminates an already-running job. If active jobs temporarily exceed the new limit, no new slot is granted until active usage drops below the configured maximum.

## Drain for maintenance

```bash
runnerctl queue drain
```

Active jobs continue. Newly assigned jobs wait at the pre-job gate.

After maintenance:

```bash
runnerctl queue resume
```

## Disable

```bash
runnerctl queue disable
```

Queue hooks are removed and the host returns to normal GitHub runner behavior. Existing runnerctl workspace-cleanup hooks remain configured because queue and cleanup use a shared hook dispatcher.

## No external queue service

This feature does not add Redis, RabbitMQ, PostgreSQL, or another scheduler. The local state lives under:

```text
$RUNNERCTL_HOME/queue/
```

Atomic filesystem state protects host-wide slot acquisition. Stale slot entries whose recorded worker process no longer exists are repaired during queue status/acquisition checks.

## Recommended small-VM setup

For a 2 CPU / ~1 GiB VM:

```bash
runnerctl capacity
runnerctl queue enable --max-concurrency 1
runnerctl queue status
```

Use additional RAM before increasing concurrency for Node builds, Docker image builds, or other memory-intensive jobs.
