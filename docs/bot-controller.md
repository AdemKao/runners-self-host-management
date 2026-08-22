# runnerctl read-only Bot/API controller

`runnerctl bot` provides a deliberately read-only remote query layer for runnerctl.

v0.7.0 supports:

- Telegram Bot API long polling
- LINE Messaging API inbound webhooks with signature verification
- an authenticated HTTP JSON API
- fixed read-only commands for runner, queue, scheduler, and host health state

The controller is optional. Existing runnerctl runner management, scheduler, queue, cleanup, and notification features do not require Python and continue to work when the controller is not used.

## Security model

v0.7.0 is intentionally **read-only**.

Remote callers cannot invoke:

- runner start/stop/restart/remove
- scheduler drain/resume/enable/disable
- legacy queue enable/disable/set
- auth changes
- upgrades
- arbitrary runnerctl commands
- shell commands

The command router accepts only these fixed names:

```text
status
runners
queue
scheduler
health
help
```

Chat text is never interpolated into a shell command. Unsupported text such as `/drain`, `$(id)`, or `/status; command` is rejected as an unsupported command.

Other security properties:

- Telegram commands require an explicit chat-ID allowlist.
- LINE commands require an explicit user-ID allowlist.
- LINE webhook signatures are verified with HMAC-SHA256 before JSON is processed.
- HTTP API endpoints require a bearer token.
- Non-loopback HTTP binding requires both `--allow-remote` and an API token.
- Request bodies are size-limited.
- API tokens, Telegram bot tokens, LINE channel access tokens, and LINE channel secrets are not returned by status/doctor output.
- The built-in HTTP server does not terminate TLS.

## Optional dependency

Bot/API commands require Python 3 and only Python's standard library.

Check the controller environment:

```bash
runnerctl bot doctor
runnerctl bot doctor --json
```

If Python 3 is not installed, normal runnerctl commands still work. Only `runnerctl bot ...` commands are unavailable.

## CLI

```bash
runnerctl bot status [--json]
runnerctl bot doctor [--json]
runnerctl bot query status|runners|queue|scheduler|health [--json]
runnerctl bot telegram run [--once]
runnerctl bot serve [--bind HOST] [--port PORT] [--allow-remote]
```

`status` and `doctor` report only whether credentials/allowlists are configured; secret values are never included.

## Read-only query mapping

The controller maps fixed remote commands to existing structured runnerctl queries:

| Remote command | runnerctl source |
| --- | --- |
| `status` | aggregate of runner, queue, scheduler, and notification status |
| `runners` | `runnerctl list --json` |
| `queue` | `runnerctl queue status --json` |
| `scheduler` | `runnerctl scheduler status --json` |
| `health` | `runnerctl doctor --json` |
| `help` | controller command list |

No remote input becomes an arbitrary argument vector.

# Telegram

Telegram uses Bot API `getUpdates` long polling. This means Telegram mode does **not** require a public HTTP endpoint.

## Required environment

```bash
export RUNNERCTL_TELEGRAM_BOT_TOKEN='...'
export RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS='123456789'
```

Multiple chat IDs can be comma-separated:

```bash
export RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS='123456789,-1001234567890'
```

For compatibility, if `RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS` is not set, runnerctl uses `RUNNERCTL_TELEGRAM_CHAT_ID` as the single allowed chat when available.

The Telegram bot token is shared with the outbound notification provider introduced in v0.6.0.

## Test one polling cycle

```bash
runnerctl bot telegram run --once
```

## Run continuously

```bash
runnerctl bot telegram run
```

Supported chat commands:

```text
/status
/runners
/queue
/scheduler
/health
/help
```

Commands addressed to a bot username such as `/status@example_bot` are normalized to `/status`.

## Replay protection

After an update is received, runnerctl stores the next Telegram update offset under:

```text
$RUNNERCTL_HOME/bot/telegram.offset
```

The offset advances even for messages from unauthorized chats. This prevents rejected updates from being replayed indefinitely after restart.

The state directory is created with restrictive permissions where supported.

## Telegram supervision with systemd

Example user or system service command:

```ini
[Unit]
Description=runnerctl Telegram read-only bot
After=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/runnerctl/bot.env
ExecStart=/usr/local/bin/runnerctl bot telegram run
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Protect the environment file:

```bash
chmod 600 /etc/runnerctl/bot.env
```

Use the path that matches your runnerctl installation.

# HTTP API

The controller includes a small standard-library HTTP server.

Start locally:

```bash
export RUNNERCTL_BOT_API_TOKEN='use-a-long-random-value'
runnerctl bot serve
```

Default address:

```text
127.0.0.1:8765
```

Explicit configuration:

```bash
runnerctl bot serve --bind 127.0.0.1 --port 8765
```

## API endpoints

```text
GET /v1/status
GET /v1/runners
GET /v1/queue
GET /v1/scheduler
GET /v1/health
GET /healthz
POST /v1/line/webhook
```

The `/v1/*` GET endpoints require:

```text
Authorization: Bearer <RUNNERCTL_BOT_API_TOKEN>
```

Example:

```bash
curl -H "Authorization: Bearer $RUNNERCTL_BOT_API_TOKEN" \
  http://127.0.0.1:8765/v1/status
```

`/healthz` returns only a minimal `{"ok":true}` response. It can be queried without authentication while the controller is bound to loopback. On a non-loopback bind, it also requires bearer authentication.

## Remote binding protection

This is rejected:

```bash
runnerctl bot serve --bind 0.0.0.0
```

To bind outside loopback you must explicitly opt in **and** configure an API token:

```bash
export RUNNERCTL_BOT_API_TOKEN='use-a-long-random-value'
runnerctl bot serve --bind 0.0.0.0 --port 8765 --allow-remote
```

Even then, runnerctl does not provide TLS. Prefer keeping the controller on loopback/private networking and putting it behind a trusted HTTPS reverse proxy, VPN, or tunnel.

Do not expose the raw HTTP listener directly to the public Internet.

# LINE Messaging API

LINE sends inbound bot messages as HTTPS webhooks. runnerctl handles them at:

```text
POST /v1/line/webhook
```

Unlike Telegram long polling, LINE requires a webhook URL that the LINE Platform can reach.

LINE's documentation requires webhook signature verification and notes that source IP allowlisting should not be used as the authenticity mechanism. runnerctl verifies the `x-line-signature` header against the **exact raw request body** before parsing JSON.

Official references:

- https://developers.line.biz/en/docs/messaging-api/receiving-messages/
- https://developers.line.biz/en/docs/messaging-api/verify-webhook-signature/

## Required environment

```bash
export RUNNERCTL_LINE_CHANNEL_SECRET='...'
export RUNNERCTL_LINE_CHANNEL_ACCESS_TOKEN='...'
export RUNNERCTL_LINE_ALLOWED_USER_IDS='U0123456789abcdef0123456789abcdef'
```

Multiple user IDs can be comma-separated.

The access token can be shared with the outbound LINE notification provider from v0.6.0. The channel secret is additionally required for inbound signature verification.

## Start the local receiver

```bash
export RUNNERCTL_BOT_API_TOKEN='local-api-token'
runnerctl bot serve --bind 127.0.0.1 --port 8765
```

Then expose only the needed webhook path through your HTTPS proxy/tunnel, for example conceptually:

```text
https://runner.example.com/v1/line/webhook
        -> trusted TLS proxy/tunnel
        -> http://127.0.0.1:8765/v1/line/webhook
```

Configure the public HTTPS URL in the LINE Developers Console.

The LINE Platform may send a valid request with an empty `events` array when verifying webhook connectivity. runnerctl returns HTTP 200 for a correctly signed empty request.

## LINE authorization flow

```text
HTTPS webhook
  -> request-size check
  -> x-line-signature HMAC verification
  -> JSON parsing
  -> text-message check
  -> user-ID allowlist
  -> fixed read-only command router
  -> LINE reply API
```

Invalid signatures return HTTP 401 and are never processed as commands.

Messages from users not in `RUNNERCTL_LINE_ALLOWED_USER_IDS` are acknowledged but ignored.

# Controller status and secrets

```bash
runnerctl bot doctor --json
```

Example shape:

```json
{
  "version": "0.7.0",
  "python": {"available": true, "version": "3.x"},
  "read_only": true,
  "telegram": {
    "token_configured": true,
    "allowlist_configured": true
  },
  "line": {
    "channel_secret_configured": true,
    "access_token_configured": true,
    "allowlist_configured": true
  },
  "api": {
    "token_configured": true,
    "default_bind": "127.0.0.1"
  }
}
```

Credential values are deliberately absent.

# Failure behavior

The bot controller is an observability surface, not part of job execution.

- Telegram polling failures do not affect GitHub runner jobs.
- HTTP API failures do not affect GitHub runner jobs.
- LINE reply failures still return a valid webhook acknowledgement after the signed event was processed.
- A failed underlying read-only runnerctl query returns an error response; it does not fall back to a mutating command.
- Unknown remote commands return help/unsupported-command text and are never passed through to runnerctl.

# launchd supervision

On macOS, supervise the long-running mode with launchd rather than a shell kept open in a terminal. The executable arguments should be equivalent to:

```text
runnerctl bot telegram run
```

or:

```text
runnerctl bot serve --bind 127.0.0.1 --port 8765
```

Store secrets outside the plist when possible, or ensure any environment configuration containing credentials has restrictive filesystem permissions.

# Relationship to notifications

`runnerctl notify` and `runnerctl bot` solve different directions:

```text
runnerctl notify
  runnerctl -> Telegram / LINE / webhook

runnerctl bot
  Telegram / LINE / HTTP client -> read-only runnerctl query -> reply
```

They can be used together and can share Telegram/LINE outbound credentials.

# Troubleshooting

## `python3 is required`

Install Python 3 using the normal package-management policy for the host, or do not enable the optional bot/API feature. Other runnerctl features remain available.

## Telegram receives no response

Check:

```bash
runnerctl bot doctor --json
runnerctl bot telegram run --once
```

Confirm the sending chat ID is present in `RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS`.

## LINE returns 401

The signature does not match the exact request body or the channel secret is incorrect. Do not disable signature verification to work around this.

## API returns 401

Provide the bearer token configured in `RUNNERCTL_BOT_API_TOKEN`.

## LINE Verify sends no events

A webhook verification request may contain an empty event array. A correctly signed empty request should still return HTTP 200.

# Rollback

Stop any supervised controller process first.

Telegram requires no public endpoint, so stopping `runnerctl bot telegram run` disables inbound Telegram queries.

For LINE, also remove/disable the webhook URL in the LINE Developers Console or reverse proxy if you no longer use it.

For the local API, stop `runnerctl bot serve` and remove its reverse-proxy route if one exists.

No runner registrations, scheduler state, queue state, or job hooks need to be removed when disabling the bot controller.

# Future work

v0.7.0 deliberately does not permit remote mutation.

A future version may add authenticated/audited operator actions such as scheduler drain/resume, but only with a separate permission model, explicit allowlists, audit logging, replay protection, and stronger confirmation semantics. The v0.7 read-only API is not treated as sufficient authorization for those operations.
