# runnerctl notifications and integrations

`runnerctl notify` adds outbound operational notifications without coupling runner management to one messaging vendor.

Current built-in providers:

- Telegram Bot API
- LINE Messaging API
- generic JSON webhook
- executable third-party notification providers

Current event sources include runner job hooks and scheduler control-plane events.

The notification layer is optional. Existing runner, cleanup, queue, scheduler, and Bot/API behavior continues to work when no provider is configured.

## Architecture

```text
GitHub Actions runner / runnerctl scheduler
                 |
                 | event
                 v
        runnerctl notification event
                 |
          stable JSON contract
                 |
       +---------+----------+----------+
       |                    |          |
       v                    v          v
   Telegram               LINE      webhook
       |
       +---------------- custom executable plugins
```

The core event schema is provider-independent. Consumers should ignore unknown JSON fields so future runnerctl versions can add context without breaking integrations.

## Critical runner-hook semantics

GitHub self-hosted runner started/completed hooks are **synchronous**.

`ACTIONS_RUNNER_HOOK_JOB_STARTED` runs after GitHub has assigned a job to a runner but before workflow steps begin. GitHub does not provide a built-in timeout for this hook.

Therefore runnerctl keeps the compatibility event identifier:

```text
job.started
```

but human-readable notifications describe it as:

```text
runner assigned / setup started
```

A v0.7.2 started message also contains:

```text
note: workflow steps have not started yet; this is the synchronous runner setup hook.
```

Do not interpret `job.started` as proof that build/test/deploy steps have started executing.

`ACTIONS_RUNNER_HOOK_JOB_COMPLETED` runs after workflow steps, before GitHub has fully finalized the job. runnerctl therefore emits `job.completed`, not `job.succeeded` or `job.failed`.

For authoritative final conclusions, use a future/event-controller integration based on GitHub `workflow_job` events rather than guessing inside runner hooks.

## Delivery reliability

runnerctl uses these rules:

- hook-driven notifications are **fail-open**;
- built-in providers use a short connect timeout (default 2 seconds);
- built-in providers use a short total request timeout (default 4 seconds);
- hook delivery performs one attempt;
- manual `notify test` / `notify emit` may retry once and return non-zero if delivery still fails;
- notification failures are recorded without credentials;
- provider credentials are never printed by `status`, `providers`, or `doctor`.

Override built-in HTTP timeouts only when necessary:

```bash
export RUNNERCTL_NOTIFY_CONNECT_TIMEOUT=2
export RUNNERCTL_NOTIFY_TOTAL_TIMEOUT=4
```

### Custom providers inside runner hooks

Manual custom-provider delivery remains supported:

```bash
runnerctl notify emit custom.event --message "hello"
```

However, v0.7.2 skips executable custom providers by default when invoked from the synchronous GitHub runner hook. A third-party executable has no guaranteed runtime bound and could otherwise freeze GitHub `Set up runner` indefinitely.

If a custom provider has been independently audited and has its own hard timeout, an operator may explicitly opt in:

```bash
export RUNNERCTL_NOTIFY_ALLOW_CUSTOM_HOOK_PROVIDERS=1
```

## Commands

```bash
runnerctl notify status
runnerctl notify status --json

runnerctl notify providers
runnerctl notify providers --json

runnerctl notify test --provider telegram
runnerctl notify test --provider line
runnerctl notify test --provider webhook
runnerctl notify test --all

runnerctl notify emit deployment.completed --message "production deployment completed"

runnerctl notify enable RUNNER
runnerctl notify enable RUNNER --events job.started,job.completed
runnerctl notify disable RUNNER

runnerctl notify doctor RUNNER
runnerctl notify doctor RUNNER --json
```

## Operator diagnostics

Use `notify doctor` when a job appears stuck at `Set up runner`, when notifications fire but workflow steps do not begin, or when you need to inspect hook composition.

```bash
runnerctl notify doctor example-runner-01
```

The command reports without returning secrets:

- notification enabled state and event filter;
- started/completed dispatcher paths;
- registered started/completed handler names in execution order;
- legacy queue enabled/drained state;
- legacy queue max concurrency and max hidden wait;
- GitHub-native scheduler enabled state;
- notification failure log path;
- warnings for dangerous combinations.

A common warning is:

```text
legacy queue is enabled; GitHub Set up runner may wait up to 300s; prefer runnerctl scheduler
```

Also inspect:

```bash
runnerctl queue status --json
runnerctl scheduler status --json
```

If you intended to use the scheduler, disable the deprecated host-side gate:

```bash
runnerctl queue disable
```

## Event context

Job notification JSON includes GitHub context when available from the runner-hook environment:

- `event`
- `phase`
- `timestamp`
- `host`
- `runner`
- `repository`
- `branch`
- `ref`
- `ref_type`
- short `sha`
- `run_id`
- `run_attempt`
- `job`
- `workflow`
- `github_event`
- `actor`
- `server_url`
- `run_url`
- `message`

For pull requests, runnerctl prefers `GITHUB_HEAD_REF` so the source branch is shown instead of only the synthetic pull-request merge ref.

runnerctl deliberately does not perform another GitHub API request from the synchronous start hook just to resolve a display job name. The stable `GITHUB_JOB` id and clickable Actions run URL are used instead.

Example started notification:

```text
[runnerctl] runner assigned / setup started
event: job.started
runner: example-runner-01
repo: example-org/example-repo
branch: feature/example-change
workflow: CI
job: build_and_test
sha: 0123456789ab
run: 98765 (attempt 2)
url: https://github.com/example-org/example-repo/actions/runs/98765
note: workflow steps have not started yet; this is the synchronous runner setup hook.
```

## Provider selection

When `RUNNERCTL_NOTIFY_PROVIDERS` is unset, built-in providers with complete configuration and executable custom plugins are discovered automatically for manual delivery.

To restrict delivery:

```bash
export RUNNERCTL_NOTIFY_PROVIDERS=telegram,webhook
```

## Job lifecycle notifications

Enable:

```bash
runnerctl notify enable example-runner-01 \
  --events job.started,job.completed
```

runnerctl:

1. writes a per-runner notification event filter;
2. creates fail-open started/completed handlers;
3. registers them with the shared `runnerctl-hooks` dispatcher;
4. preserves cleanup/legacy-queue handlers already using that dispatcher;
5. restarts the managed runner service when possible because runner `.env` hook changes are loaded on restart.

If the deprecated legacy queue is enabled, `notify enable` warns that `job.started` may be followed by a local `Set up runner` wait. Prefer the GitHub-native scheduler for production queueing.

Disable:

```bash
runnerctl notify disable example-runner-01
```

## Scheduler events

runnerctl emits best-effort notifications for:

- `scheduler.enabled`
- `scheduler.disabled`
- `scheduler.drained`
- `scheduler.resumed`
- `scheduler.error`

Notification delivery never changes the scheduler command's own success/failure status.

## Telegram setup

Required environment variables:

```bash
export RUNNERCTL_TELEGRAM_BOT_TOKEN='...'
export RUNNERCTL_TELEGRAM_CHAT_ID='...'
```

Test:

```bash
runnerctl notify test --provider telegram
```

`RUNNERCTL_TELEGRAM_CHAT_ID` is the outbound destination. See `docs/telegram-chat-id.md` and `docs/telegram-chat-id.zh-TW.md` for private-chat and group/supergroup setup.

Treat the bot token like a password. Do not commit it to workflows, source code, `.runnerctl-meta`, support tickets, or diagnostic output.

## LINE Messaging API setup

Required environment variables:

```bash
export RUNNERCTL_LINE_CHANNEL_ACCESS_TOKEN='...'
export RUNNERCTL_LINE_TO='U...'
```

Test:

```bash
runnerctl notify test --provider line
```

`RUNNERCTL_LINE_TO` must be a destination supported by the LINE Messaging API and the account/channel relationship must satisfy LINE's push-message conditions.

Treat the channel access token like a password and revoke/replace it if exposure is suspected.

## Generic webhook provider

Required:

```bash
export RUNNERCTL_WEBHOOK_URL='https://example.com/hooks/runnerctl'
```

Optional authorization header:

```bash
export RUNNERCTL_WEBHOOK_AUTH_HEADER='Authorization: Bearer ...'
```

Test:

```bash
runnerctl notify test --provider webhook
```

The webhook receives `Content-Type: application/json` and the runnerctl event object.

Example:

```json
{
  "schema_version": 1,
  "event": "job.started",
  "phase": "runner-assigned-before-steps",
  "host": "oracle-ci-01",
  "runner": "example-runner-01",
  "repository": "example-org/example-repo",
  "branch": "feature/example-change",
  "ref": "refs/pull/123/merge",
  "ref_type": "branch",
  "sha": "0123456789ab",
  "run_id": "98765",
  "run_attempt": "2",
  "job": "build_and_test",
  "workflow": "CI",
  "run_url": "https://github.com/example-org/example-repo/actions/runs/98765",
  "message": "[runnerctl] runner assigned / setup started ..."
}
```

`schema_version` remains `1`; fields are additive. Consumers should ignore unknown fields.

## Custom provider plugins

Custom notification providers are executable files in:

```text
$RUNNERCTL_HOME/plugins/notify/NAME
```

Contract:

- event JSON on stdin;
- `RUNNERCTL_NOTIFY_EVENT` contains the event name;
- `RUNNERCTL_NOTIFY_MESSAGE` contains the human-readable message;
- exit `0` means delivery succeeded;
- non-zero means delivery failed.

Example:

```bash
#!/usr/bin/env bash
set -euo pipefail
payload="$(cat)"
# Deliver $payload using a bounded client.
```

Make it executable:

```bash
chmod 700 "$RUNNERCTL_HOME/plugins/notify/my-provider"
export RUNNERCTL_NOTIFY_PROVIDERS=my-provider
runnerctl notify test --provider my-provider
```

## Secret handling

runnerctl does not intentionally persist provider tokens in its normal configuration files.

Recommended storage:

- protected service-manager environment file (`chmod 600`);
- secret manager injecting environment variables into the runner service;
- protected host-level environment configuration.

Avoid:

- token command-line arguments;
- committing secret `.env` files;
- workflow YAML containing provider credentials;
- dumping environment variables in CI logs.

Remember: a token exported only in an interactive SSH shell may work for `runnerctl notify test` but not for runner hooks. The runner service must receive the provider environment variables.

## Monitoring and failure log

```bash
runnerctl notify status --json
runnerctl notify doctor RUNNER --json
```

Provider failures are appended to:

```text
$RUNNERCTL_HOME/notify/notify.log
```

Only provider/event/failure metadata is written; credentials are not intentionally logged.

## Troubleshooting

### Notification arrives, then GitHub is stuck at Set up runner

Run:

```bash
runnerctl notify doctor RUNNER
runnerctl queue status --json
runnerctl scheduler status --json
```

If legacy queue is enabled, that local admission gate can wait after the notification because GitHub has already assigned the job. v0.7.2 bounds that wait and makes cancellation deterministic, but the recommended fix is to migrate queueing to `runnerctl scheduler`.

### `provider ... is not configured`

Check:

```bash
runnerctl notify providers
```

Do not print credential values while debugging.

### Manual test fails but a job continues

Expected. Manual `notify test` is fail-closed for diagnostics; runner hooks are fail-open.

### Hooks do not fire

After `notify enable`, make sure the runner service restarted. GitHub runner `.env` hook changes are loaded on restart.

### Telegram destination receives nothing

Verify chat ID, bot membership/permissions, service environment, and token. See the Telegram Chat ID guides in `docs/`.

### LINE returns success but no user receives a message

Review destination ID, Official Account relationship, friend/block state, and LINE's push-message delivery conditions.

## Rollback

Disable notifications per runner:

```bash
runnerctl notify disable RUNNER
```

Remove provider environment variables from the runner service environment and restart if necessary.

If rolling back runnerctl itself from v0.7.2, be aware that older versions restore the unbounded legacy queue-start wait. Prefer disabling `runnerctl queue` and using the scheduler rather than relying on the old admission gate.
