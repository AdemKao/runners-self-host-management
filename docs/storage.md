# Host storage inspection and scoped maintenance

`runnerctl storage` adds bounded disk admission and opt-in, scoped maintenance.
It exists because workspace cleanup alone cannot prevent a host from filling up:
Docker images and build cache live in `/var/lib/docker` and `/var/lib/containerd`,
while runner data usually lives on a separate volume.

Python 3.8 or newer is required, like the other optional v0.7+ helpers.

## What it never does

`runnerctl storage` deliberately cannot:

- run `docker system prune`, `docker image prune`, `docker volume prune`, or
  `docker container prune`;
- remove any volume, including unused anonymous volumes;
- remove images, containerd content, package-manager caches, workspaces,
  backups, or the Docker daemon's own directories;
- write to a path outside the runner directories listed in the policy;
- operate on the shared `default` or `desktop-linux` builder.

There is no "clean everything" flag. Deleting state that another project or
rollback path still needs is an operator decision, not a CLI default.

## Read-only inspection

```bash
runnerctl storage inspect --path / --json
runnerctl storage inspect --path / --path /srv/data
```

Reports total bytes, free bytes, used percentage, and free inodes per path.
`inspect` needs no policy file.

## Admission check

A policy file declares the reserves that must exist before new work is admitted:

```json
{
  "schema_version": 1,
  "filesystems": [
    {"path": "/", "min_free_bytes": 12884901888, "min_free_inodes": 200000, "max_used_percent": 85},
    {"path": "/srv/data", "min_free_bytes": 21474836480, "min_free_inodes": 300000, "max_used_percent": 85}
  ],
  "runners": ["/srv/data/example-runner/runnerctl/runners/example-runner-01"],
  "log_retention_days": 14,
  "builder": {
    "name": "example-builder",
    "docker_config": "/srv/data/example-runner/runnerctl/docker",
    "unused_hours": 168,
    "max_used_gib": 4
  }
}
```

```bash
runnerctl storage check --policy /etc/runnerctl/storage.json --json
```

Exit codes: `0` when every declared filesystem satisfies its reserve,
`3` when admission should be blocked, `1` on an invalid or unreadable policy.
This is intended for a pre-job hook or scheduler gate, not for deleting anything.

`min_free_bytes` guards against small absolute free space, `max_used_percent`
guards against a nearly full device, and `min_free_inodes` catches
file-count exhaustion that byte reserves miss.

## Preview, then apply

```bash
runnerctl storage plan  --policy /etc/runnerctl/storage.json
runnerctl storage gc --policy /etc/runnerctl/storage.json            # preview only
runnerctl storage gc --policy /etc/runnerctl/storage.json --apply --audit /var/log/runnerctl-storage.jsonl
```

Without `--apply`, `gc` prints the plan and changes nothing. `--apply` requires
`--audit`, and deletion happens only after a concurrent-change check on device,
inode, size, and mtime. Each removal is fsync'ed to the audit log before the
unlink, and a non-zero exit means maintenance was partial.

Expired diagnostic logs:

- Only files matching `Runner_*.log` and `Worker_*.log` inside a listed runner's
  `_diag` directory are eligible.
- The newest two files of each kind are always retained, regardless of age.
- Any file whose identity changed between planning and applying is skipped
  rather than deleted.

Optional builder GC is limited to one explicitly named builder from the policy,
with an age filter and a cache budget. It never prunes images or volumes, and it
uses the builder's own `--config` directory.

Concurrent maintenance is prevented with an exclusive lock next to the audit
file, so a second `gc --apply` exits non-zero instead of interleaving.

## Workspace cleanup changes in v0.8.0

`cleanup status` no longer walks workspace trees by default, because measuring
every workspace on a busy host can take minutes. Pass `--sizes` (with an
optional `--timeout SECONDS`, default 5) to opt in:

```bash
runnerctl cleanup status example-runner-01 --json
runnerctl cleanup status example-runner-01 --json --sizes --timeout 15
```

Without `--sizes`, `workspace_kb` is `null` and `scan_status` is
`not-requested`. With `--sizes`, a slow or failed measurement reports
`workspace_kb: null` with `scan_status` of `timeout` or `unavailable`; it never
reports an unmeasured workspace as zero.

The post-job hook now uses a Python helper that:

- requires Python 3.8+ and refuses to run without it;
- re-validates that the workspace is exactly `<runner>/_work/<owner>/<repo>`;
- bounds removal to 30 seconds and reports a partial result on timeout;
- leaves other directories untouched.

Manual `cleanup run RUNNER` now requires `RUNNERCTL_CLEANUP_IDLE_CONFIRMED=1` so
that an operator has explicitly confirmed the runner is idle:

```bash
RUNNERCTL_CLEANUP_IDLE_CONFIRMED=1 runnerctl cleanup run example-runner-01
```

`cleanup run --dry-run` still only previews.

## Policy validation

Policies fail closed. Rejected without echoing policy contents: unsupported
`schema_version`, relative or traversing paths, symlinked targets, negative or
boolean policy integers, `max_used_percent` outside 1-100, unmanaged runner
paths, oversized policy files, and shared builder names. Errors are printed as a
single stable JSON error code on stderr.

## Suggested rollout

1. Install the release, then confirm `runnerctl storage inspect --path /`.
2. Set reserves that match real headroom, not aspirational free space.
3. Run `storage check` and confirm it blocks only when you intend.
4. Run `storage plan` and review the file list before any `--apply`.
5. Enable the builder entry only for builders you created and want bounded.
6. Enable workspace cleanup per runner when workflows no longer depend on
   leftover workspace content; each change restarts that runner service.