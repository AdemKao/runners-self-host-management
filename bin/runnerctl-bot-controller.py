#!/usr/bin/env python3
"""runnerctl read-only bot/API controller.

Optional Python 3 component. Remote commands are intentionally fixed and read-only.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import pathlib
import shlex
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

VERSION = "0.7.0"
MAX_BODY = 64 * 1024
MAX_REPLY = 3500
READ_ONLY_COMMANDS = {"status", "runners", "queue", "scheduler", "health", "help"}


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def home() -> pathlib.Path:
    return pathlib.Path(env("RUNNERCTL_HOME", str(pathlib.Path.home() / ".local/share/runnerctl")))


def state_dir() -> pathlib.Path:
    path = home() / "bot"
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        path.chmod(0o700)
    except OSError:
        pass
    return path


def runnerctl_executable() -> str:
    override = env("RUNNERCTL_BOT_RUNNERCTL")
    if override:
        return override
    return "runnerctl"


def run_runnerctl(args: list[str]) -> tuple[bool, Any, str]:
    command = [runnerctl_executable(), *args]
    try:
        proc = subprocess.run(command, capture_output=True, text=True, timeout=15, check=False)
    except (OSError, subprocess.SubprocessError) as exc:
        return False, None, f"runnerctl query failed: {type(exc).__name__}"
    stdout = proc.stdout.strip()
    stderr = proc.stderr.strip()
    if proc.returncode != 0:
        return False, None, stderr or f"runnerctl exited {proc.returncode}"
    if not stdout:
        return True, {}, ""
    try:
        return True, json.loads(stdout), ""
    except json.JSONDecodeError:
        return True, {"output": stdout}, ""


def query_payload(name: str) -> tuple[bool, Any, str]:
    if name not in READ_ONLY_COMMANDS:
        return False, None, "unsupported read-only command"
    if name == "help":
        return True, {
            "commands": ["status", "runners", "queue", "scheduler", "health", "help"],
            "read_only": True,
        }, ""
    if name == "runners":
        return run_runnerctl(["list", "--json"])
    if name == "queue":
        return run_runnerctl(["queue", "status", "--json"])
    if name == "scheduler":
        return run_runnerctl(["scheduler", "status", "--json"])
    if name == "health":
        return run_runnerctl(["doctor", "--json"])
    # status: aggregate read-only snapshots; individual failures remain visible.
    result: dict[str, Any] = {"version": VERSION, "read_only": True}
    all_ok = True
    for key, args in (
        ("runners", ["list", "--json"]),
        ("queue", ["queue", "status", "--json"]),
        ("scheduler", ["scheduler", "status", "--json"]),
        ("notifications", ["notify", "status", "--json"]),
    ):
        ok, value, error = run_runnerctl(args)
        result[key] = value if ok else {"ok": False, "error": error}
        all_ok = all_ok and ok
    result["ok"] = all_ok
    return True, result, ""


def normalize_command(text: str) -> str | None:
    text = (text or "").strip()
    if not text:
        return None
    first = text.split()[0]
    if first.startswith("/"):
        first = first[1:]
    first = first.split("@", 1)[0].lower()
    aliases = {"runner": "runners", "runnerctl": "status"}
    first = aliases.get(first, first)
    return first if first in READ_ONLY_COMMANDS else None


def render_reply(command: str, payload: Any) -> str:
    if command == "help":
        return "runnerctl read-only commands:\n/status\n/runners\n/queue\n/scheduler\n/health\n/help"
    text = f"runnerctl {command}\n" + json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
    if len(text) > MAX_REPLY:
        text = text[: MAX_REPLY - 32] + "\n... output truncated"
    return text


def csv_set(value: str) -> set[str]:
    return {item.strip() for item in value.split(",") if item.strip()}


def telegram_allowed() -> set[str]:
    explicit = env("RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS")
    if explicit:
        return csv_set(explicit)
    fallback = env("RUNNERCTL_TELEGRAM_CHAT_ID")
    return {fallback} if fallback else set()


def line_allowed() -> set[str]:
    return csv_set(env("RUNNERCTL_LINE_ALLOWED_USER_IDS"))


def http_json(url: str, *, data: dict[str, Any] | None = None, headers: dict[str, str] | None = None, timeout: int = 30) -> Any:
    body = None
    hdrs = dict(headers or {})
    if data is not None:
        body = json.dumps(data, separators=(",", ":")).encode()
        hdrs.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=body, headers=hdrs, method="POST" if body is not None else "GET")
    with urllib.request.urlopen(req, timeout=timeout) as response:
        raw = response.read(MAX_BODY + 1)
    if len(raw) > MAX_BODY:
        raise RuntimeError("remote response too large")
    return json.loads(raw.decode() or "{}")


def telegram_api(method: str, payload: dict[str, Any]) -> Any:
    token = env("RUNNERCTL_TELEGRAM_BOT_TOKEN")
    if not token:
        raise RuntimeError("Telegram bot token is not configured")
    base = env("RUNNERCTL_TELEGRAM_API_BASE", "https://api.telegram.org")
    url = f"{base.rstrip('/')}/bot{token}/{method}"
    return http_json(url, data=payload, timeout=35)


def telegram_offset_file() -> pathlib.Path:
    return state_dir() / "telegram.offset"


def read_offset() -> int:
    try:
        return int(telegram_offset_file().read_text().strip() or "0")
    except (OSError, ValueError):
        return 0


def write_offset(value: int) -> None:
    path = telegram_offset_file()
    tmp = path.with_suffix(".tmp")
    tmp.write_text(f"{value}\n")
    try:
        tmp.chmod(0o600)
    except OSError:
        pass
    tmp.replace(path)


def telegram_poll_once(long_poll: bool) -> int:
    allowed = telegram_allowed()
    if not allowed:
        print("runnerctl bot: Telegram chat allowlist is not configured", file=sys.stderr)
        return 2
    offset = read_offset()
    timeout = 25 if long_poll else 0
    try:
        result = telegram_api("getUpdates", {"offset": offset, "timeout": timeout, "allowed_updates": ["message"]})
    except Exception as exc:  # secret-safe error
        print(f"runnerctl bot: Telegram polling failed: {type(exc).__name__}", file=sys.stderr)
        return 1
    updates = result.get("result", []) if isinstance(result, dict) else []
    for update in updates:
        update_id = int(update.get("update_id", -1))
        if update_id >= 0:
            offset = max(offset, update_id + 1)
            write_offset(offset)
        message = update.get("message") or {}
        chat_id = str((message.get("chat") or {}).get("id", ""))
        text = message.get("text") or ""
        if chat_id not in allowed:
            continue
        command = normalize_command(text)
        if command is None:
            reply = "Unsupported command. Use /help."
        else:
            ok, payload, error = query_payload(command)
            reply = render_reply(command, payload if ok else {"ok": False, "error": error})
        try:
            telegram_api("sendMessage", {"chat_id": chat_id, "text": reply})
        except Exception as exc:
            print(f"runnerctl bot: Telegram reply failed: {type(exc).__name__}", file=sys.stderr)
    return 0


def telegram_run(once: bool) -> int:
    if once:
        return telegram_poll_once(False)
    while True:
        rc = telegram_poll_once(True)
        if rc == 2:
            return rc
        if rc != 0:
            time.sleep(3)


def line_signature_valid(raw: bytes, signature: str, secret: str) -> bool:
    digest = hmac.new(secret.encode(), raw, hashlib.sha256).digest()
    expected = base64.b64encode(digest).decode()
    return hmac.compare_digest(expected, signature or "")


def line_reply(reply_token: str, text: str) -> None:
    access_token = env("RUNNERCTL_LINE_CHANNEL_ACCESS_TOKEN")
    if not access_token:
        raise RuntimeError("LINE channel access token is not configured")
    base = env("RUNNERCTL_LINE_API_BASE", "https://api.line.me")
    http_json(
        f"{base.rstrip('/')}/v2/bot/message/reply",
        data={"replyToken": reply_token, "messages": [{"type": "text", "text": text[:5000]}]},
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=6,
    )


def safe_loopback(bind: str) -> bool:
    return bind in {"127.0.0.1", "::1", "localhost"}


def bearer_ok(header: str, token: str) -> bool:
    if not token or not header.startswith("Bearer "):
        return False
    return hmac.compare_digest(header[7:], token)


class ControllerHandler(BaseHTTPRequestHandler):
    server_version = "runnerctl-bot/0.7"

    def log_message(self, fmt: str, *args: Any) -> None:
        # Avoid logging headers, bodies, tokens, or channel secrets.
        sys.stderr.write("[runnerctl-bot] " + (fmt % args) + "\n")

    def json_response(self, status: int, payload: Any) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def api_authorized(self) -> bool:
        token = env("RUNNERCTL_BOT_API_TOKEN")
        return bearer_ok(self.headers.get("Authorization", ""), token)

    def do_GET(self) -> None:  # noqa: N802
        path = urllib.parse.urlsplit(self.path).path
        if path == "/healthz":
            bind = getattr(self.server, "runnerctl_bind", "127.0.0.1")
            if not safe_loopback(bind) and not self.api_authorized():
                self.json_response(401, {"ok": False, "error": "unauthorized"})
                return
            self.json_response(200, {"ok": True})
            return
        mapping = {
            "/v1/status": "status",
            "/v1/runners": "runners",
            "/v1/queue": "queue",
            "/v1/scheduler": "scheduler",
            "/v1/health": "health",
        }
        command = mapping.get(path)
        if command is None:
            self.json_response(404, {"ok": False, "error": "not found"})
            return
        if not self.api_authorized():
            self.json_response(401, {"ok": False, "error": "unauthorized"})
            return
        ok, payload, error = query_payload(command)
        self.json_response(200 if ok else 503, payload if ok else {"ok": False, "error": error})

    def do_POST(self) -> None:  # noqa: N802
        path = urllib.parse.urlsplit(self.path).path
        if path != "/v1/line/webhook":
            self.json_response(404, {"ok": False, "error": "not found"})
            return
        length_text = self.headers.get("Content-Length", "0")
        try:
            length = int(length_text)
        except ValueError:
            self.json_response(400, {"ok": False, "error": "invalid content length"})
            return
        if length < 0 or length > MAX_BODY:
            self.json_response(413, {"ok": False, "error": "request too large"})
            return
        raw = self.rfile.read(length)
        secret = env("RUNNERCTL_LINE_CHANNEL_SECRET")
        signature = self.headers.get("x-line-signature", "")
        if not secret or not line_signature_valid(raw, signature, secret):
            self.json_response(401, {"ok": False, "error": "invalid signature"})
            return
        try:
            body = json.loads(raw.decode() or "{}")
        except (UnicodeDecodeError, json.JSONDecodeError):
            self.json_response(400, {"ok": False, "error": "invalid json"})
            return
        allowed = line_allowed()
        # Valid webhook verification requests may contain an empty event list.
        for event in body.get("events", []):
            if event.get("type") != "message" or (event.get("message") or {}).get("type") != "text":
                continue
            source = event.get("source") or {}
            user_id = str(source.get("userId", ""))
            if not allowed or user_id not in allowed:
                continue
            command = normalize_command((event.get("message") or {}).get("text", ""))
            if command is None:
                reply = "Unsupported command. Use /help."
            else:
                ok, payload, error = query_payload(command)
                reply = render_reply(command, payload if ok else {"ok": False, "error": error})
            reply_token = event.get("replyToken") or ""
            if reply_token:
                try:
                    line_reply(reply_token, reply)
                except Exception as exc:
                    print(f"runnerctl bot: LINE reply failed: {type(exc).__name__}", file=sys.stderr)
        self.json_response(200, {"ok": True})


def serve(bind: str, port: int, allow_remote: bool) -> int:
    if not safe_loopback(bind):
        if not allow_remote:
            print("runnerctl bot: non-loopback bind requires --allow-remote", file=sys.stderr)
            return 2
        if not env("RUNNERCTL_BOT_API_TOKEN"):
            print("runnerctl bot: non-loopback bind requires RUNNERCTL_BOT_API_TOKEN", file=sys.stderr)
            return 2
    server = ThreadingHTTPServer((bind, port), ControllerHandler)
    setattr(server, "runnerctl_bind", bind)
    print(f"runnerctl bot controller listening on {bind}:{server.server_address[1]}")
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


def doctor_payload() -> dict[str, Any]:
    telegram_allow = telegram_allowed()
    line_allow = line_allowed()
    return {
        "version": VERSION,
        "python": {"available": True, "version": sys.version.split()[0]},
        "read_only": True,
        "telegram": {
            "token_configured": bool(env("RUNNERCTL_TELEGRAM_BOT_TOKEN")),
            "allowlist_configured": bool(telegram_allow),
        },
        "line": {
            "channel_secret_configured": bool(env("RUNNERCTL_LINE_CHANNEL_SECRET")),
            "access_token_configured": bool(env("RUNNERCTL_LINE_CHANNEL_ACCESS_TOKEN")),
            "allowlist_configured": bool(line_allow),
        },
        "api": {"token_configured": bool(env("RUNNERCTL_BOT_API_TOKEN")), "default_bind": "127.0.0.1"},
    }


def cmd_query(name: str, as_json: bool) -> int:
    ok, payload, error = query_payload(name)
    if as_json:
        print(json.dumps(payload if ok else {"ok": False, "error": error}, ensure_ascii=False, separators=(",", ":")))
    else:
        print(render_reply(name, payload if ok else {"ok": False, "error": error}))
    return 0 if ok else 1


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="runnerctl bot", description="Read-only Telegram, LINE, and HTTP API controller")
    sub = p.add_subparsers(dest="command", required=True)
    status = sub.add_parser("status", help="Show bot/controller configuration without secrets")
    status.add_argument("--json", action="store_true")
    doctor = sub.add_parser("doctor", help="Check optional controller prerequisites/configuration")
    doctor.add_argument("--json", action="store_true")
    query = sub.add_parser("query", help="Run a fixed read-only query")
    query.add_argument("name", choices=sorted(READ_ONLY_COMMANDS - {"help"}))
    query.add_argument("--json", action="store_true")
    telegram = sub.add_parser("telegram", help="Telegram Bot API long-polling controller")
    telegram_sub = telegram.add_subparsers(dest="telegram_command", required=True)
    run = telegram_sub.add_parser("run")
    run.add_argument("--once", action="store_true")
    server = sub.add_parser("serve", help="Serve read-only HTTP API and LINE webhook")
    server.add_argument("--bind", default="127.0.0.1")
    server.add_argument("--port", type=int, default=8765)
    server.add_argument("--allow-remote", action="store_true")
    return p


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    if args.command in {"status", "doctor"}:
        payload = doctor_payload()
        if args.json:
            print(json.dumps(payload, separators=(",", ":")))
        else:
            print(json.dumps(payload, indent=2, sort_keys=True))
        return 0
    if args.command == "query":
        return cmd_query(args.name, args.json)
    if args.command == "telegram":
        return telegram_run(args.once)
    if args.command == "serve":
        if not (1 <= args.port <= 65535):
            print("runnerctl bot: --port must be between 1 and 65535", file=sys.stderr)
            return 2
        return serve(args.bind, args.port, args.allow_remote)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
