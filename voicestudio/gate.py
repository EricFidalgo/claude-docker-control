#!/usr/bin/env python3
"""Phone lock in front of VoiceStudio, using the same shared password and Face ID as the Docker panel and Money app.

Phone visits (through `tailscale serve`) must unlock first; then this adds VoiceStudio's API key to every request,
so the app never asks for it. The key stays on this computer and is never sent to the phone. Requests from this
computer (no X-Forwarded-For) pass straight through, key added too.

Listens on 127.0.0.1:3901 (the address the panel gives the PC, and the target of `tailscale serve --https=3901`)
and forwards to the container on 127.0.0.1:3903. The key comes in as OMNIVOICE_API_KEY
from the service's EnvironmentFile (the secrets file), so this script never opens it.
"""
import http.client
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import lock  # noqa: E402  (linux-remote/lock.py)

LISTEN = int(os.environ.get("GATE_PORT", "3901"))
UPSTREAM = ("127.0.0.1", int(os.environ.get("GATE_UPSTREAM_PORT", "3903")))
KEY = os.environ.get("OMNIVOICE_API_KEY", "")
LOCK = lock.Lock(Path(os.environ.get("DOCK_LOCK") or Path.home() / ".local/share/app-lock/lock.json"),
                 cookie="voice_lock", rp_name="VoiceStudio")
HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailers",
       "transfer-encoding", "upgrade", "host", "authorization", "content-length"}

# Home-screen app (iPhone "Add to Home Screen"): the icon and manifest are served before the lock check, because iOS
# fetches them without the lock cookie. They're only a picture and a name. Same tags go in the app's own page
# (mobile/patch-ui.sh), so adding it from the lock screen or from the app gives the same icon.
# icon-180 (square) is for the iPhone, which rounds corners itself; icon-round-* have see-through corners, for the tab
# icon and Chrome's Install on Linux, which rounds nothing.
APP_FILES = {"/vs-app/icon-180.png": ("icon-180.png", "image/png"), "/vs-app/icon-round-192.png": ("icon-round-192.png", "image/png"),
             "/vs-app/icon-round-512.png": ("icon-round-512.png", "image/png"),
             "/manifest.webmanifest": ("manifest.webmanifest", "application/manifest+json")}
APP_TAGS = ('<link rel="apple-touch-icon" href="/vs-app/icon-180.png"><link rel="icon" href="/vs-app/icon-round-192.png">'
            '<link rel="manifest" href="/manifest.webmanifest"><meta name="apple-mobile-web-app-capable" content="yes">'
            '<meta name="mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-title" content="VoiceStudio">'
            '<meta name="theme-color" content="#1b1520">')

# Shown to a locked phone instead of the app. lock.js covers it with the unlock screen, then we reload.
LOCK_PAGE = b"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>VoiceStudio</title>"""+APP_TAGS.encode()+b"""<style>body{margin:0;background:#111}@media(prefers-color-scheme:light){body{background:#f5f5f7}}</style></head>
<body><script src="/lock.js" data-name="VoiceStudio" data-setup="dock password"></script>
<script>fetch("/api/gate-ping").then(r=>{ if(r.ok) location.reload(); });</script></body></html>"""


class Gate(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def reply(self, code, body, ctype="application/json", cookie=None, extra=()):
        try:
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            if cookie:
                self.send_header("Set-Cookie", cookie)
            for k, v in extra:
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def handle_one(self):
        path = urlparse(self.path).path
        if path == lock.AUTH_PREFIX or path.startswith(lock.AUTH_PREFIX + "/"):
            try:
                size = min(max(int(self.headers.get("Content-Length") or 0), 0), 64_000)
            except ValueError:
                size = 0
            import json
            status, body, cookie = LOCK.handle(self.command, path, self.headers, self.rfile.read(size))
            return self.reply(status, json.dumps(body).encode(), cookie=cookie)
        if path in APP_FILES:
            name, ctype = APP_FILES[path]
            return self.reply(200, (HERE / "app" / name).read_bytes(), ctype, extra=[("Cache-Control", "public, max-age=3600")])
        if path == "/lock.js":
            return self.reply(200, (HERE.parent / "lock.js").read_bytes(), "text/javascript; charset=utf-8")
        if lock.from_phone(self.headers):
            with LOCK._mutex:
                ok = LOCK._valid(LOCK._token(self.headers), LOCK._load())
            if not ok:
                if "text/html" in (self.headers.get("Accept") or "") and self.command == "GET":
                    return self.reply(200, LOCK_PAGE, "text/html; charset=utf-8")
                # The app would answer a bare 401 with its own PIN box ("Share on your network"), which isn't
                # ours. vs-mobile.js sees this header and reloads the page, which brings up the phone lock.
                return self.reply(401, b'{"locked":true}', extra=[("X-Gate-Locked", "1")])
        if path == "/api/gate-ping":
            return self.reply(200, b"{}")
        self.forward()

    def forward(self):
        size = int(self.headers.get("Content-Length") or 0)
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        if KEY:
            headers["Authorization"] = "Bearer " + KEY
        # Keep the browser's own Cookie header out of the app; the lock cookie isn't its business.
        headers.pop("Cookie", None)
        try:
            up = http.client.HTTPConnection(*UPSTREAM, timeout=600)
            up.putrequest(self.command, self.path, skip_host=True, skip_accept_encoding=True)
            # Keep the address the browser used: the app refuses a render whose Origin doesn't match its Host
            # ("Request refused: it came from another website"). X-Forwarded-Proto from tailscale serve passes too.
            up.putheader("Host", self.headers.get("Host") or "%s:%d" % UPSTREAM)
            for k, v in headers.items():
                up.putheader(k, v)
            up.putheader("Content-Length", str(size))
            up.endheaders()
            left = size
            while left > 0:
                chunk = self.rfile.read(min(left, 1 << 20))
                if not chunk:
                    break
                up.send(chunk)
                left -= len(chunk)
            res = up.getresponse()
        except OSError:
            return self.reply(502, b'{"error":"VoiceStudio is not running"}')
        try:
            self.send_response(res.status)
            for k, v in res.getheaders():
                if k.lower() not in HOP:
                    self.send_header(k, v)
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True
            while True:
                chunk = res.read(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            up.close()

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_HEAD = do_OPTIONS = handle_one


if __name__ == "__main__":
    if not KEY:
        sys.exit("OMNIVOICE_API_KEY is not set (the service loads it from the secrets file).")
    ThreadingHTTPServer(("127.0.0.1", LISTEN), Gate).serve_forever()
