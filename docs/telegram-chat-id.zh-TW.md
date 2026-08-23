# runnerctl Telegram Chat ID 快速設定

runnerctl 會使用 Telegram **chat ID** 決定通知要送到哪個對話，以及哪些對話可以執行 read-only Bot/API 查詢。

不需要依賴第三方「查 ID Bot」。Telegram 官方 Bot API 的 incoming update 本身就會回傳 chat ID。

## 該使用哪個環境變數？

`RUNNERCTL_TELEGRAM_CHAT_ID`

- 單一通知目的地 / 單一允許 chat；
- 保留給 v0.6 notification 設定相容使用；
- 單一管理者最簡單的設定方式。

`RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS`

- v0.7 read-only controller 的 inbound allowlist；
- 可以用逗號分隔多個 chat ID；
- 如果有多個私人 chat 或 group 要查 runnerctl，建議使用這個。

若沒有設定 `RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS`，v0.7 controller 會在有設定 `RUNNERCTL_TELEGRAM_CHAT_ID` 時把它當作單一允許 chat。

## 建議預設：private chat

如果這台 runner host 主要由一個人管理，建議直接使用**你和 bot 的私人對話**。

優點：

- allowlist 最簡單；
- runner / repository 狀態不會廣播到群組；
- 通知雜訊比較少；
- `/status`、`/queue` 等 read-only command 的授權範圍最清楚。

只有在多個可信任的維運人員需要共享通知或查詢時，才建議使用 group / supergroup。

## 找到 private chat ID

1. 使用 BotFather 建立 Telegram bot，妥善保存 bot token。
2. 打開你和該 bot 的私人聊天。
3. 傳一則訊息，例如 `hello` 或 `/status`。
4. 使用官方 Bot API 取得 updates：

```bash
export RUNNERCTL_TELEGRAM_BOT_TOKEN='YOUR_BOT_TOKEN'

curl -fsSL \
  "https://api.telegram.org/bot${RUNNERCTL_TELEGRAM_BOT_TOKEN}/getUpdates"
```

5. 找到剛才的訊息並查看：

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

`message.chat.id` 就是 chat ID，照原值複製即可。

設定 runnerctl：

```bash
export RUNNERCTL_TELEGRAM_CHAT_ID='123456789'
export RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS='123456789'
```

確認設定但不輸出 token：

```bash
runnerctl notify status --json
runnerctl bot doctor --json
```

測試 outbound notification：

```bash
runnerctl notify test --provider telegram
```

只執行一次 read-only Telegram polling：

```bash
runnerctl bot telegram run --once
```

## 找到 group chat ID

當多個可信任的維運人員需要共用 runner 通知或 read-only 查詢時，可以使用 group。

1. 把 bot 加入 Telegram group。
2. 在 group 中送出 bot 能收到的訊息。如果 Telegram bot privacy mode 會過濾一般訊息，可以使用 `/status@your_bot_username` 這類 bot command。
3. 再呼叫上面的 `getUpdates`。
4. 找到該 group 訊息的 `message.chat.id`。

Group / supergroup ID 可能是負數，例如：

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

負號必須原樣保留：

```bash
export RUNNERCTL_TELEGRAM_CHAT_ID='-1001234567890'
export RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS='-1001234567890'
```

多個允許 chat：

```bash
export RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS='123456789,-1001234567890'
```

## Private 還是 Group？

| 使用情境 | 建議 |
| --- | --- |
| 個人 runner host / 單一管理者 | Private chat |
| 比較敏感的維運狀態 | Private chat |
| 小型可信任維運團隊共享通知 | Private group / supergroup |
| 多位管理者各自私聊 | `RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS` 放多個 ID |

即使 v0.7 遠端 command 都是 read-only，group 仍會讓群組中的人看到 repository / runner 狀態，所以請只使用可信任的 group。

## `getUpdates` 沒有資料

常見原因：

- 建立 bot 後先再傳一則新訊息。
- Group 中若 bot privacy mode 阻擋一般訊息，改傳 bot command。
- 確認使用的 token 就是目前對話中那個 bot 的 token。
- 不要把 token 貼到 issue、log 或截圖裡。

Telegram 對同一個 bot 有兩種互斥的 update delivery 方式：`getUpdates` long polling 與 webhook。runnerctl v0.7 的 Telegram controller 使用 `getUpdates`；如果同一個 bot 已在其他服務設定 Telegram webhook，請先移除/停用該 webhook，再使用 `runnerctl bot telegram run`。

## 官方文件

Telegram Bot API：<https://core.telegram.org/bots/api#getupdates>

runnerctl 需要的欄位就是 incoming message 的 `message.chat.id`。