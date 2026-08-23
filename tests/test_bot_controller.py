#!/usr/bin/env python3
import base64
import hashlib
import hmac
import importlib.util
import json
import os
import pathlib
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "bin" / "runnerctl-bot-controller.py"
spec = importlib.util.spec_from_file_location("runnerctl_bot_controller", MODULE_PATH)
bot = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(bot)


class Env:
    def __init__(self, **values):
        self.values = values
        self.old = {}

    def __enter__(self):
        for key, value in self.values.items():
            self.old[key] = os.environ.get(key)
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        return self

    def __exit__(self, *_):
        for key, value in self.old.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


class BotControllerTests(unittest.TestCase):
    def make_fake_runnerctl(self, tmp):
        path = tmp / "runnerctl"
        path.write_text(
            "#!/usr/bin/env python3\n"
            "import json,sys\n"
            "args=sys.argv[1:]\n"
            "if args==['list','--json']: print(json.dumps([{'name':'runner-a','state':'idle'}]))\n"
            "elif args==['queue','status','--json']: print(json.dumps({'enabled':False,'active':0}))\n"
            "elif args==['scheduler','status','--json']: print(json.dumps({'enabled':True,'max_concurrency':1}))\n"
            "elif args==['monitor','status','--json']: print(json.dumps({'enabled':True,'history_count':2}))\n"
            "elif args==['monitor','jobs','--limit','20','--json']: print(json.dumps([{'job':'test','conclusion':'success'}]))\n"
            "elif args==['monitor','failures','--limit','20','--json']: print(json.dumps([{'job':'build','conclusion':'failure'}]))\n"
            "elif args==['notify','status','--json']: print(json.dumps({'configured_providers':1}))\n"
            "elif args==['doctor','--json']: print(json.dumps({'assessment':'ok'}))\n"
            "else: print('unexpected:'+repr(args),file=sys.stderr); sys.exit(7)\n"
        )
        path.chmod(0o755)
        return path

    def start_server(self):
        server = bot.ThreadingHTTPServer(("127.0.0.1", 0), bot.ControllerHandler)
        setattr(server, "runnerctl_bind", "127.0.0.1")
        thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True)
        thread.start()
        return server, thread

    def test_command_router_is_fixed_and_read_only(self):
        self.assertEqual(bot.normalize_command("/status"), "status")
        self.assertEqual(bot.normalize_command("/runners@my_bot hello"), "runners")
        self.assertEqual(bot.normalize_command("/jobs"), "jobs")
        self.assertEqual(bot.normalize_command("/failures"), "failures")
        self.assertIsNone(bot.normalize_command("/drain"))
        self.assertIsNone(bot.normalize_command("/status; rm -rf /"))
        self.assertIsNone(bot.normalize_command("$(id)"))

    def test_query_uses_fixed_runnerctl_argv(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = pathlib.Path(td)
            fake = self.make_fake_runnerctl(tmp)
            with Env(RUNNERCTL_BOT_RUNNERCTL=str(fake)):
                ok, payload, error = bot.query_payload("runners")
                self.assertTrue(ok, error)
                self.assertEqual(payload[0]["name"], "runner-a")
                ok, payload, error = bot.query_payload("status")
                self.assertTrue(ok, error)
                self.assertEqual(payload["scheduler"]["max_concurrency"], 1)
                self.assertEqual(payload["monitor"]["history_count"], 2)
                ok, payload, error = bot.query_payload("jobs")
                self.assertTrue(ok, error)
                self.assertEqual(payload[0]["conclusion"], "success")
                ok, payload, error = bot.query_payload("failures")
                self.assertTrue(ok, error)
                self.assertEqual(payload[0]["conclusion"], "failure")

    def test_bearer_constant_time_contract(self):
        self.assertTrue(bot.bearer_ok("Bearer abc", "abc"))
        self.assertFalse(bot.bearer_ok("Bearer abd", "abc"))
        self.assertFalse(bot.bearer_ok("abc", "abc"))
        self.assertFalse(bot.bearer_ok("Bearer abc", ""))

    def test_line_signature(self):
        raw = b'{"events":[]}'
        secret = "line-secret"
        sig = base64.b64encode(hmac.new(secret.encode(), raw, hashlib.sha256).digest()).decode()
        self.assertTrue(bot.line_signature_valid(raw, sig, secret))
        self.assertFalse(bot.line_signature_valid(raw + b"x", sig, secret))

    def test_remote_bind_requires_explicit_flag_and_token(self):
        with Env(RUNNERCTL_BOT_API_TOKEN=None):
            self.assertEqual(bot.serve("0.0.0.0", 8765, False), 2)
            self.assertEqual(bot.serve("0.0.0.0", 8765, True), 2)

    def test_http_api_requires_bearer_and_exposes_history(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = pathlib.Path(td)
            fake = self.make_fake_runnerctl(tmp)
            with Env(RUNNERCTL_BOT_RUNNERCTL=str(fake), RUNNERCTL_BOT_API_TOKEN="api-secret"):
                server, thread = self.start_server()
                try:
                    base = "http://127.0.0.1:%s" % server.server_address[1]
                    with self.assertRaises(urllib.error.HTTPError) as ctx:
                        urllib.request.urlopen(base + "/v1/runners", timeout=2)
                    self.assertEqual(ctx.exception.code, 401)
                    for path, expected in (("/v1/runners", "runner-a"), ("/v1/jobs", "success"), ("/v1/failures", "failure")):
                        req = urllib.request.Request(base + path, headers={"Authorization": "Bearer api-secret"})
                        with urllib.request.urlopen(req, timeout=2) as response:
                            payload = json.loads(response.read())
                        if path == "/v1/runners":
                            self.assertEqual(payload[0]["name"], expected)
                        else:
                            self.assertEqual(payload[0]["conclusion"], expected)
                finally:
                    server.shutdown(); server.server_close(); thread.join(timeout=2)

    def test_line_webhook_verifies_signature_and_allowlist(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = pathlib.Path(td)
            fake = self.make_fake_runnerctl(tmp)
            replies = []
            original_reply = bot.line_reply
            bot.line_reply = lambda token, text: replies.append((token, text))
            try:
                with Env(
                    RUNNERCTL_BOT_RUNNERCTL=str(fake),
                    RUNNERCTL_LINE_CHANNEL_SECRET="channel-secret",
                    RUNNERCTL_LINE_CHANNEL_ACCESS_TOKEN="access-token",
                    RUNNERCTL_LINE_ALLOWED_USER_IDS="Uallowed",
                ):
                    server, thread = self.start_server()
                    try:
                        url = "http://127.0.0.1:%s/v1/line/webhook" % server.server_address[1]
                        body = json.dumps({"events":[{"type":"message","replyToken":"reply-1","source":{"userId":"Uallowed"},"message":{"type":"text","text":"/jobs"}}]}, separators=(",", ":")).encode()
                        sig = base64.b64encode(hmac.new(b"channel-secret", body, hashlib.sha256).digest()).decode()
                        req = urllib.request.Request(url, data=body, headers={"Content-Type":"application/json","x-line-signature":sig}, method="POST")
                        with urllib.request.urlopen(req, timeout=2) as response:
                            self.assertEqual(response.status, 200)
                        self.assertEqual(len(replies), 1)
                        self.assertIn("runnerctl jobs", replies[0][1])

                        bad = urllib.request.Request(url, data=body, headers={"Content-Type":"application/json","x-line-signature":"bad"}, method="POST")
                        with self.assertRaises(urllib.error.HTTPError) as ctx:
                            urllib.request.urlopen(bad, timeout=2)
                        self.assertEqual(ctx.exception.code, 401)

                        unauthorized_body = json.dumps({"events":[{"type":"message","replyToken":"reply-2","source":{"userId":"Uother"},"message":{"type":"text","text":"/failures"}}]}, separators=(",", ":")).encode()
                        unauthorized_sig = base64.b64encode(hmac.new(b"channel-secret", unauthorized_body, hashlib.sha256).digest()).decode()
                        req = urllib.request.Request(url, data=unauthorized_body, headers={"Content-Type":"application/json","x-line-signature":unauthorized_sig}, method="POST")
                        urllib.request.urlopen(req, timeout=2).read()
                        self.assertEqual(len(replies), 1)
                    finally:
                        server.shutdown(); server.server_close(); thread.join(timeout=2)
            finally:
                bot.line_reply = original_reply

    def test_telegram_allowlist_offset_and_jobs_command(self):
        with tempfile.TemporaryDirectory() as td:
            calls = []
            original = bot.telegram_api
            def fake_api(method, payload):
                calls.append((method, payload))
                if method == "getUpdates":
                    return {"ok": True, "result": [
                        {"update_id": 10, "message": {"chat": {"id": 111}, "text": "/jobs"}},
                        {"update_id": 11, "message": {"chat": {"id": 999}, "text": "/status"}},
                    ]}
                if method == "sendMessage":
                    return {"ok": True}
                raise AssertionError(method)
            bot.telegram_api = fake_api
            try:
                tmp = pathlib.Path(td)
                fake = self.make_fake_runnerctl(tmp)
                with Env(RUNNERCTL_HOME=td, RUNNERCTL_BOT_RUNNERCTL=str(fake), RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS="111"):
                    self.assertEqual(bot.telegram_poll_once(False), 0)
                    self.assertEqual(bot.read_offset(), 12)
                    sends = [payload for method, payload in calls if method == "sendMessage"]
                    self.assertEqual(len(sends), 1)
                    self.assertEqual(str(sends[0]["chat_id"]), "111")
                    self.assertIn("runnerctl jobs", sends[0]["text"])
            finally:
                bot.telegram_api = original


if __name__ == "__main__":
    unittest.main(verbosity=2)