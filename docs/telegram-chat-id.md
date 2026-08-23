# Telegram Chat ID quickstart for runnerctl

runnerctl uses a Telegram **chat ID** to decide where outbound notifications go and which chats are allowed to run read-only bot queries.

You do not need a third-party "ID lookup" bot. Telegram's official Bot API already returns the chat ID in incoming updates.

## Which variable should I use?

`RUNNERCTL_TELEGRAM_CHAT_ID`

- one destination / one allowed chat;
- kept for compatibility with the v0.6 notification setup;
- a good default for a single operator.

`RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS`

- inbound Bot/API allowlist introduced for the read-only controller;
- accepts one or more comma-separated chat IDs;
- preferred when multiple private chats or groups may query runnerctl.

If `RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS` is unset, the v0.7 controller falls back to `RUNNERCTL_TELEGRAM_CHAT_ID` when it is configured.

## Recommended default: private chat

For one person operating a runner host, use a **private chat with the bot**.

Advantages:

- simplest allowlist;
- operational status is not broadcast to a team room;
- less alert noise;
- easier to reason about who can run `/status`, `/queue`, and the other read-only commands.

Use a group only when multiple trusted operators should share the same alerts or status queries.

## Find a private chat ID

1. Create a Telegram bot with BotFather and keep its bot token private.
2. Open a private conversation with your bot.
3. Send a message such as `hello` or `/status`.
4. Ask the official Bot API for updates:

```bash
export RUNNERCTL_TELEGRAM_BOT_TOKEN='YOUR_BOT_TOKEN'

curl -fsSL \
  "https://api.telegram.org/bot${RUNNERCTL_TELEGRAM_BOT_TOKEN}/getUpdates"
```

5. Find the incoming message and read:

```json
{
  "message": {
    "chat": {
      "id": 123456789,
      "type": "private"
    }
  }
}
```

The value of `message.chat.id` is the chat ID. Copy it exactly.

Configure runnerctl:

```bash
export RUNNERCTL_TELEGRAM_CHAT_ID='123456789'
export RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS='123456789'
```

Then check configuration without printing the token:

```bash
runnerctl notify status --json
runnerctl bot doctor --json
```

For outbound notification testing:

```bash
runnerctl notify test --provider telegram
```

For one read-only polling cycle:

```bash
runnerctl bot telegram run --once
```

## Find a group chat ID

Use a group when several trusted operators should receive the same runner alerts or run the same read-only bot commands.

1. Add the bot to the Telegram group.
2. Send a message in the group that produces an update visible to the bot. A direct bot command such as `/status@your_bot_username` is a reliable choice when bot privacy settings restrict ordinary group messages.
3. Call `getUpdates` with the bot token as shown above.
4. Find the group message and read `message.chat.id`.

A group or supergroup ID can be negative, for example:

```json
{
  "message": {
    "chat": {
      "id": -1001234567890,
      "type": "supergroup"
    }
  }
}
```

Keep the leading minus sign exactly as returned by Telegram:

```bash
export RUNNERCTL_TELEGRAM_CHAT_ID='-1001234567890'
export RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS='-1001234567890'
```

Multiple allowed chats are comma-separated:

```bash
export RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS='123456789,-1001234567890'
```

## Private chat or group?

| Use case | Recommendation |
| --- | --- |
| Personal runner host / one operator | Private chat |
| Sensitive operational status | Private chat |
| Small trusted ops team sharing alerts | Private group or supergroup |
| Multiple separate operators | Multiple IDs in `RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS` |

Remember that group members who can talk to the bot are still subject to runnerctl's chat-ID allowlist. v0.7 remote commands are read-only, but a group can still expose repository/runner status to everyone in that group, so use a trusted group.

## `getUpdates` returns no messages

Check these common causes:

- Send a new message to the bot after creating it.
- For a group, send a bot command if Telegram bot privacy mode prevents the bot from receiving ordinary messages.
- Make sure the bot token belongs to the same bot you are messaging.
- Do not paste the token into issue comments, logs, or screenshots.

Telegram supports two mutually exclusive update-delivery approaches for a bot: `getUpdates` long polling and webhooks. runnerctl v0.7 uses `getUpdates` for its Telegram controller. If that bot currently has a Telegram webhook configured elsewhere, remove/disable that webhook before using `runnerctl bot telegram run`.

## Official reference

Telegram Bot API: <https://core.telegram.org/bots/api#getupdates>

The important field for runnerctl is the incoming message's `message.chat.id`.