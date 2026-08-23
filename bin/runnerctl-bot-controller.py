#!/usr/bin/env python3
"""runnerctl read-only bot/API controller.

Optional Python 3.8+ component. Remote commands are fixed and read-only.
"""
import argparse
import base64
import hashlib
import hmac
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "0.8.0"
MIN_PYTHON = (3, 8)
MAX_BODY = 64 * 1024
MAX_REPLY = 3500
READ_ONLY_COMMANDS = {"status", "runners", "queue", "scheduler", "health", "jobs", "failures", "help"}


def env(name, default=""):
    return os.environ.get(name, default)


def require_python():
    if sys.version_info < MIN_PYTHON:
        print("runnerctl bot: Python 3.8 or newer is required", file=sys.stderr)
        return False
    return True


def home():
    return pathlib.Path(env("RUNNERCTL_HOME", str(pathlib.Path.home() / ".local/share/runnerctl")))


def state_dir():
    path = home() / "bot"
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        path.chmod(0o700)
    except OSError:
        pass
    return path


def runnerctl_executable():
    return env("RUNNERCTL_BOT_RUNNERCTL") or "runnerctl"


def run_runnerctl(args):
    try:
        proc = subprocess.run([runnerctl_executable()] + list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True, timeout=15, check=False)
    except (OSError, subprocess.SubprocessError) as exc:
        return False, None, "runnerctl query failed: %s" % type(exc).__name__
    stdout = proc.stdout.strip()
    stderr = proc.stderr.strip()
    if proc.returncode != 0:
        return False, None, stderr or "runnerctl exited %s" % proc.returncode
    if not stdout:
        return True, {}, ""
    try:
        return True, json.loads(stdout), ""
    except ValueError:
        return True, {"output": stdout}, ""


def query_payload(name):
    if name not in READ_ONLY_COMMANDS:
        return False, None, "unsupported read-only command"
    if name == "help":
        return True, {"commands": ["status", "runners", "queue", "scheduler", "health", "jobs", "failures", "help"], "read_only": True}, ""
    mapping = {
        "runners": ["list", "--json"],
        "queue": ["queue", "status", "--json"],
        "scheduler": ["scheduler", "status", "--json"],
        "health": ["doctor", "--json"],
        "jobs": ["monitor", "jobs", "--limit", "20", "--json"],
        "failures": ["monitor", "failures", "--limit", "20", "--json"],
    }
    if name in mapping:
        return run_runnerctl(mapping[name])
    result = {"version": VERSION, "read_only": True}
    all_ok = True
    for key, args in (
        ("runners", ["list", "--json"]),
        ("queue", ["queue", "status", "--json"]),
        ("scheduler", ["scheduler", "status", "--json"]),
        ("monitor", ["monitor", "status", "--json"]),
        ("notifications", ["notify", "status", "--json"]),
    ):
        ok, value, error = run_runnerctl(args)
        result[key] = value if ok else {"ok": False, "error": error}
        all_ok = all_ok and ok
    result["ok"] = all_ok
    return True, result, ""


def normalize_command(text):
    text = (text or "").strip()
    if not text:
        return None
    first = text.split()[0]
    if first.startswith("/"):
        first = first[1:]
    first = first.split("@", 1)[0].lower()
    first = {"runner": "runners", "runnerctl": "status"}.get(first, first)
    return first if first in READ_ONLY_COMMANDS else None


def render_reply(command, payload):
    if command == "help":
        return "runnerctl read-only commands:\n/status\n/runners\n/queue\n/scheduler\n/health\n/jobs\n/failures\n/help"
    text = "runnerctl %s\n%s" % (command, json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    if len(text) > MAX_REPLY:
        text = text[:MAX_REPLY - 32] + "\n... output truncated"
    return text


def csv_set(value):
    return {item.strip() for item in value.split(",") if item.strip()}


def telegram_allowed():
    explicit = env("RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS")
    if explicit:
        return csv_set(explicit)
    fallback = env("RUNNERCTL_TELEGRAM_CHAT_ID")
    return {fallback} if fallback else set()


def line_allowed():
    return csv_set(env("RUNNERCTL_LINE_ALLOWED_USER_IDS"))


def http_json(url, data=None, headers=None, timeout=30):
    body = None
    hdrs = dict(headers or {})
    if data is not None:
        body = json.dumps(data, separators=(",", ":")).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=body, headers=hdrs, method="POST" if body is not None else "GET")
    with urllib.request.urlopen(req, timeout=timeout) as response:
        raw = response.read(MAX_BODY + 1)
    if len(raw) > MAX_BODY:
        raise RuntimeError("remote response too large")
    return json.loads(raw.decode("utf-8") or "{}")


def telegram_api(method, payload):
    token = env("RUNNERCTL_TELEGRAM_BOT_TOKEN")
    if not token:
        raise RuntimeError("Telegram bot token is not configured")
    base = env("RUNNERCTL_TELEGRAM_API_BASE", "https://api.telegram.org")
    return http_json("%s/bot%s/%s" % (base.rstrip("/"), token, method), data=payload, timeout=35)


def telegram_offset_file():
    return state_dir() / "telegram.offset"


def read_offset():
    try:
        return int(telegram_offset_file().read_text().strip() or "0")
    except (OSError, ValueError):
        return 0


def write_offset(value):
    path = telegram_offset_file()
    tmp = path.with_suffix(".tmp")
    tmp.write_text("%s\n" % value)
    try:
        tmp.chmod(0o600)
    except OSError:
        pass
    tmp.replace(path)


def telegram_poll_once(long_poll):
    allowed = telegram_allowed()
    if not allowed:
        print("runnerctl bot: Telegram chat allowlist is not configured", file=sys.stderr)
        return 2
    offset = read_offset()
    try:
        result = telegram_api("getUpdates", {"offset": offset, "timeout": 25 if long_poll else 0, "allowed_updates": ["message"]})
    except Exception as exc:
        print("runnerctl bot: Telegram polling failed: %s" % type(exc).__name__, file=sys.stderr)
        return 1
    updates = result.get("result", []) if isinstance(result, dict) else []
    for update in updates:
        update_id = int(update.get("update_id", -1))
        if update_id >= 0:
            offset = max(offset, update_id + 1)
            write_offset(offset)
        message = update.get("message") or {}
        chat_id = str((message.get("chat") or {}).get("id", ""))
        if chat_id not in allowed:
            continue
        command = normalize_command(message.get("text") or "")
        if command is None:
            reply = "Unsupported command. Use /help."
        else:
            ok, payload, error = query_payload(command)
            reply = render_reply(command, payload if ok else {"ok": False, "error": error})
        try:
            telegram_api("sendMessage", {"chat_id": chat_id, "text": reply})
        except Exception as exc:
            print("runnerctl bot: Telegram reply failed: %s" % type(exc).__name__, file=sys.stderr)
    return 0


def telegram_run(once):
    if once:
        return telegram_poll_once(False)
    while True:
        rc = telegram_poll_once(True)
        if rc == 2:
            return rc
        if rc != 0:
            time.sleep(3)


def line_signature_valid(raw, signature, secret):
    digest = hmac.new(secret.encode("utf-8"), raw, hashlib.sha256).digest()
    expected = base64.b64encode(digest).decode("ascii")
    return hmac.compare_digest(expected, signature or "")


def line_reply(reply_token, text):
    access_token = env("RUNNERCTL_LINE_CHANNEL_ACCESS_TOKEN")
    if not access_token:
        raise RuntimeError("LINE channel access token is not configured")
    base = env("RUNNERCTL_LINE_API_BASE", "https://api.line.me")
    http_json("%s/v2/bot/message/reply" % base.rstrip("/"),
              data={"replyToken": reply_token, "messages": [{"type": "text", "text": text[:5000]}]},
              headers={"Authorization": "Bearer %s" % access_token}, timeout=6)


def safe_loopback(bind):
    return bind in {"127.0.0.1", "::1", "localhost"}


def bearer_ok(header, token):
    if not token or not header.startswith("Bearer "):
        return False
    return hmac.compare_digest(header[7:], token)


class ControllerHandler(BaseHTTPRequestHandler):
    server_version = "runnerctl-bot/0.8"

    def log_message(self, fmt, *args):
        sys.stderr.write("[runnerctl-bot] " + (fmt % args) + "\n")

    def json_response(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def api_authorized(self):
        return bearer_ok(self.headers.get("Authorization", ""), env("RUNNERCTL_BOT_API_TOKEN"))

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        if path == "/healthz":
            bind = getattr(self.server, "runnerctl_bind", "127.0.0.1")
            if not safe_loopback(bind) and not self.api_authorized():
                self.json_response(401, {"ok": False, "error": "unauthorized"})
                return
            self.json_response(200, {"ok": True})
            return
        mapping = {"/v1/status": "status", "/v1/runners": "runners", "/v1/queue": "queue",
                   "/v1/scheduler": "scheduler", "/v1/health": "health", "/v1/jobs": "jobs",
                   "/v1/failures": "failures"}
        command = mapping.get(path)
        if command is None:
            self.json_response(404, {"ok": False, "error": "not found"})
            return
        if not self.api_authorized():
            self.json_response(401, {"ok": False, "error": "unauthorized"})
            return
        ok, payload, error = query_payload(command)
        self.json_response(200 if ok else 503, payload if ok else {"ok": False, "error": error})

    def do_POST(self):
        if urllib.parse.urlsplit(self.path).path != "/v1/line/webhook":
            self.json_response(404, {"ok": False, "error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
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
            body = json.loads(raw.decode("utf-8") or "{}")
        except (UnicodeDecodeError, ValueError):
            self.json_response(400, {"ok": False, "error": "invalid json"})
            return
        allowed = line_allowed()
        for event in body.get("events", []):
            if event.get("type") != "message" or (event.get("message") or {}).get("type") != "text":
                continue
            user_id = str((event.get("source") or {}).get("userId", ""))
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
                    print("runnerctl bot: LINE reply failed: %s" % type(exc).__name__, file=sys.stderr)
        self.json_response(200, {"ok": True})


def serve(bind, port, allow_remote):
    if not safe_loopback(bind):
        if not allow_remote:
            print("runnerctl bot: non-loopback bind requires --allow-remote", file=sys.stderr)
            return 2
        if not env("RUNNERCTL_BOT_API_TOKEN"):
            print("runnerctl bot: non-loopback bind requires RUNNERCTL_BOT_API_TOKEN", file=sys.stderr)
            return 2
    server = ThreadingHTTPServer((bind, port), ControllerHandler)
    setattr(server, "runnerctl_bind", bind)
    print("runnerctl bot controller listening on %s:%s" % (bind, server.server_address[1]))
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


def doctor_payload():
    return {
        "version": VERSION,
        "python": {"available": True, "version": sys.version.split()[0], "minimum": "3.8"},
        "read_only": True,
        "telegram": {"token_configured": bool(env("RUNNERCTL_TELEGRAM_BOT_TOKEN")), "allowlist_configured": bool(telegram_allowed())},
        "line": {"channel_secret_configured": bool(env("RUNNERCTL_LINE_CHANNEL_SECRET")),
                 "access_token_configured": bool(env("RUNNERCTL_LINE_CHANNEL_ACCESS_TOKEN")),
                 "allowlist_configured": bool(line_allowed())},
        "api": {"token_configured": bool(env("RUNNERCTL_BOT_API_TOKEN")), "default_bind": "127.0.0.1"},
    }


def cmd_query(name, as_json):
    ok, payload, error = query_payload(name)
    value = payload if ok else {"ok": False, "error": error}
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")) if as_json else render_reply(name, value))
    return 0 if ok else 1


def build_parser():
    p = argparse.ArgumentParser(prog="runnerctl bot", description="Read-only Telegram, LINE, and HTTP API controller")
    sub = p.add_subparsers(dest="command")
    status = sub.add_parser("status", help="Show controller configuration without secrets"); status.add_argument("--json", action="store_true")
    doctor = sub.add_parser("doctor", help="Check controller prerequisites/configuration"); doctor.add_argument("--json", action="store_true")
    query = sub.add_parser("query", help="Run a fixed read-only query"); query.add_argument("name", choices=sorted(READ_ONLY_COMMANDS - {"help"})); query.add_argument("--json", action="store_true")
    telegram = sub.add_parser("telegram", help="Telegram Bot API long polling"); telegram_sub = telegram.add_subparsers(dest="telegram_command")
    run = telegram_sub.add_parser("run"); run.add_argument("--once", action="store_true")
    server = sub.add_parser("serve", help="Serve read-only HTTP API and LINE webhook"); server.add_argument("--bind", default="127.0.0.1"); server.add_argument("--port", type=int, default=8765); server.add_argument("--allow-remote", action="store_true")
    return p


def main(argv=None):
    if not require_python():
        return 2
    parser = build_parser(); args = parser.parse_args(argv)
    if not args.command:
        parser.print_help(); return 0
    if args.command in ("status", "doctor"):
        payload = doctor_payload(); print(json.dumps(payload, separators=(",", ":")) if args.json else json.dumps(payload, indent=2, sort_keys=True)); return 0
    if args.command == "query":
        return cmd_query(args.name, args.json)
    if args.command == "telegram":
        if args.telegram_command != "run":
            parser.print_help(); return 2
        return telegram_run(args.once)
    if args.command == "serve":
        if not 1 <= args.port <= 65535:
            print("runnerctl bot: --port must be between 1 and 65535", file=sys.stderr); return 2
        return serve(args.bind, args.port, args.allow_remote)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())