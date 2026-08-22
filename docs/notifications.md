# runnerctl notifications and integrations

`runnerctl notify` adds outbound operational notifications without coupling the runner manager to one messaging vendor.

v0.6.0 supports:

- Telegram Bot API notifications
- LINE Messaging API push notifications
- generic JSON webhooks
- executable third-party notification providers
- job started/completed hooks
- scheduler control-plane events
- local provider/configuration status queries

The notification layer is optional. Existing runner, cleanup, legacy queue, and scheduler behavior continues to work when no notification provider is configured.

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

The core event schema is provider-independent. Built-in providers and third-party plugins receive the same event information.

## Important delivery semantics

GitHub self-hosted runner started/completed hooks are synchronous. A slow notification hook must not delay or fail a CI job.

runnerctl therefore uses these rules:

- hook-driven notifications are **fail-open**;
- built-in providers use a short connect timeout (default 2 seconds);
- built-in providers use a short total request timeout (default 4 seconds);
- hook delivery performs one attempt;
- manual `notify test` / `notify emit` may retry once and return non-zero if delivery still fails;
- notification failures are recorded without credentials;
- provider credentials are never printed by `status` or `providers`.

Override timeouts only when necessary:

```bash
export RUNNERCTL_NOTIFY_CONNECT_TIMEOUT=2
export RUNNERCTL_NOTIFY_TOTAL_TIMEOUT=4
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
```

### Provider selection

When `RUNNERCTL_NOTIFY_PROVIDERS` is unset, built-in providers with complete configuration and executable custom plugins are selected automatically.

To restrict delivery:

```bash
export RUNNERCTL_NOTIFY_PROVIDERS=telegram,webhook
```

The value is a comma-separated provider list.

## Events

### Job lifecycle

When notifications are enabled for a runner, runnerctl composes notification handlers into the existing shared GitHub runner hook dispatcher.

Supported v0.6 job events:

- `job.started`
- `job.completed`

Example:

```bash
runnerctl notify enable oracle-ci-01 \
  --events job.started,job.completed
```

The hook event contains runner/repository/run/job/workflow information when GitHub exposes those environment variables to the runner hook.

### Important: completion is not the final GitHub conclusion

`ACTIONS_RUNNER_HOOK_JOB_COMPLETED` runs after workflow steps but before GitHub has fully finalized the job. v0.6 therefore emits `job.completed`, not `job.succeeded` or `job.failed`.

runnerctl deliberately does **not** guess a final conclusion.

For exact success/failure notifications, a future event controller should consume GitHub `workflow_job` webhook events, where the final conclusion is authoritative.

### Scheduler events

The v0.6 frontend emits these control-plane events after successful scheduler commands:

- `scheduler.enabled`
- `scheduler.disabled`
- `scheduler.drained`
- `scheduler.resumed`

A failing scheduler control command attempts to emit:

- `scheduler.error`

Notification delivery never changes the scheduler command's own exit status.

## Telegram setup

Telegram uses the Bot API `sendMessage` method.

Required environment variables:

```bash
export RUNNERCTL_TELEGRAM_BOT_TOKEN='...'
export RUNNERCTL_TELEGRAM_CHAT_ID='...'
```

Recommended setup:

1. Create/manage a Telegram bot using Telegram's official bot management flow.
2. Add/start the bot in the target private chat, group, supergroup, or channel as appropriate.
3. Obtain the target chat ID using Telegram's Bot API/update tooling.
4. Store the bot token outside shell history and source code.
5. Export the token and chat ID to the runner service environment.
6. Test delivery:

```bash
runnerctl notify test --provider telegram
```

Official Bot API reference:

- https://core.telegram.org/bots/api

### Telegram security note

The bot token authorizes Bot API calls. Treat it like a password. Do not commit it to a workflow, repository, `.runnerctl-meta`, notification config, or support ticket.

## LINE Messaging API setup

LINE notifications use the Messaging API push-message endpoint.

Required environment variables:

```bash
export RUNNERCTL_LINE_CHANNEL_ACCESS_TOKEN='...'
export RUNNERCTL_LINE_TO='U...'
```

`RUNNERCTL_LINE_TO` can be a supported Messaging API destination such as a user/group/room ID, subject to LINE's push-message conditions.

Recommended setup:

1. Create/configure a LINE Messaging API channel and Official Account.
2. Issue an appropriate channel access token.
3. Obtain the target user/group/room ID from your Messaging API integration/webhook events.
4. Ensure the destination meets LINE's conditions for receiving push messages.
5. Store the channel access token outside source code.
6. Test delivery:

```bash
runnerctl notify test --provider line
```

Official LINE documentation:

- https://developers.line.biz/en/reference/messaging-api/
- https://developers.line.biz/en/docs/messaging-api/sending-messages/
- https://developers.line.biz/en/docs/basics/channel-access-token/

### LINE security note

A channel access token authorizes Messaging API operations. Revoke and replace it if exposure is suspected.

## Generic webhook provider

Required:

```bash
export RUNNERCTL_WEBHOOK_URL='https://example.com/hooks/runnerctl'
```

Optional complete authorization/header value:

```bash
export RUNNERCTL_WEBHOOK_AUTH_HEADER='Authorization: Bearer ...'
```

Test:

```bash
runnerctl notify test --provider webhook
```

The webhook receives `Content-Type: application/json` and the runnerctl event object.

Example event:

```json
{
  "schema_version": 1,
  "event": "job.completed",
  "timestamp": "2026-08-22T12:34:56Z",
  "host": "oracle-ci-01",
  "runner": "billing-runner-01",
  "repository": "example-org/example-repo",
  "run_id": "123456789",
  "run_attempt": "1",
  "job": "test",
  "workflow": "CI",
  "run_url": "https://github.com/example-org/example-repo/actions/runs/123456789",
  "message": "[runnerctl] job.completed ..."
}
```

`schema_version` is intended to make provider integrations forward-compatible. Consumers should ignore unknown fields.

## Custom provider plugins

Custom notification providers are executable files in:

```text
$RUNNERCTL_HOME/plugins/notify/NAME
```

Provider contract:

- event JSON is provided on stdin;
- `RUNNERCTL_NOTIFY_EVENT` contains the event name;
- `RUNNERCTL_NOTIFY_MESSAGE` contains the human-readable rendered message;
- exit `0` means delivery succeeded;
- non-zero means delivery failed.

Example shell provider:

```bash
#!/usr/bin/env bash
set -euo pipefail
payload="$(cat)"
# Send $payload to your integration.
# Never echo credentials.
```

Make it executable:

```bash
chmod 700 "$RUNNERCTL_HOME/plugins/notify/my-provider"
export RUNNERCTL_NOTIFY_PROVIDERS=my-provider
runnerctl notify test --provider my-provider
```

A plugin should implement its own short network timeout. Hook-driven calls set:

```text
RUNNERCTL_NOTIFY_HOOK=1
```

Plugins can use this signal to disable long retries during runner hooks.

## Secret handling

runnerctl does not store provider tokens in its normal configuration files.

Recommended options:

- a protected service-manager environment file (`chmod 600`);
- a secret manager that injects environment variables into the runner service;
- protected host-level environment configuration.

Avoid:

- command-line token arguments;
- committing `.env` files with tokens;
- embedding tokens in GitHub workflow YAML;
- logging environment variables during CI;
- sharing `RUNNERCTL_WEBHOOK_AUTH_HEADER`, Telegram bot tokens, or LINE channel tokens in diagnostics.

`runnerctl notify status --json` reports whether built-in provider credentials appear configured but does not return their values.

## Enabling runner job notifications

```bash
runnerctl notify enable my-runner \
  --events job.started,job.completed
```

runnerctl:

1. writes a per-runner notification event filter;
2. creates fail-open started/completed handlers;
3. registers them with `runnerctl-hooks`;
4. preserves cleanup/queue handlers already using the shared dispatcher;
5. restarts the managed runner service when possible because GitHub runner `.env` hook changes require a restart.

If automatic restart is unavailable, runnerctl prints a manual-restart warning.

Disable:

```bash
runnerctl notify disable my-runner
```

## Monitoring and queries

Local operational query:

```bash
runnerctl notify status
runnerctl notify status --json
```

This shows configured runners, event filters, and whether built-in providers have the required environment variables. Secrets are never returned.

This v0.6 feature is **not** a metrics database and does not retain a complete job history. Provider failures are appended to:

```text
$RUNNERCTL_HOME/notify/notify.log
```

Only provider name/event/failure metadata is written; credentials are not intentionally logged.

## Why Telegram/LINE `/status` commands are not in v0.6

Outbound notifications and inbound bot commands have different security and lifecycle requirements.

An inbound Telegram bot can use long polling or a webhook. An inbound LINE bot requires Messaging API webhook handling. That introduces:

- a long-running bot/API controller;
- request signature/authentication validation;
- user/chat authorization rules;
- replay/rate-limit handling;
- potentially a public HTTPS endpoint;
- command permissions for operational data/actions.

v0.6 intentionally ships the provider/event foundation first. A later bot-controller/API layer can consume `runnerctl ... --json` commands safely without redesigning outbound notifications.

## Troubleshooting

### `provider ... is not configured`

Check the required environment variables in the same service/user environment where runnerctl runs:

```bash
runnerctl notify providers
```

Do not print token values while debugging.

### Test fails but job continues

Expected. Manual `notify test` returns non-zero for diagnostics. Job hooks are fail-open by design.

### Hooks do not fire

After `notify enable`, verify the runner service was restarted. GitHub runner hook environment changes are loaded on restart.

Also inspect:

```bash
runnerctl notify status
runnerctl cleanup status
runnerctl queue status
```

The shared hook composer allows notification, cleanup, and legacy queue handlers to coexist.

### LINE returns success but no user receives a message

Review LINE's documented push-message delivery conditions, friend/block status, and destination ID.

### Telegram destination does not receive a message

Verify the target chat ID, bot membership/permissions, and bot token.

## Rollback

For each runner:

```bash
runnerctl notify disable RUNNER
```

Then remove provider environment variables from the runner service environment and restart the service if necessary.

No repository workflow changes are required to use or remove v0.6 notifications.
