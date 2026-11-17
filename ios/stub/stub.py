#!/usr/bin/env python3
"""The CI replica's stand-in for newswatch (the real page needs Deyao's Google login): on 127.0.0.1:PORT,
- /app/health/app-signin?state=S → 302 to dev.de0ch.yycsystems://signed-in?state=S#token=T, T a JWT-shaped token with
  an exp an hour away, minted here and remembered (as Access signs him in and hands the page its token);
- /app/health → the page when the CF_Authorization cookie is a token minted here: it shows "stub ok", the cookie's
  token and the window's size in CSS px; any other cookie → 302 to Access's login (a spent token);
- /log → what it was asked (the test reads it)."""
import base64, json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
MINTED, LOG = set(), []
b64 = lambda d: base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip("=")  # noqa: E731

PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<style>html,body{margin:0;background:#1a1d20;color:#e8eaec;font:13px/18px monospace;overflow:hidden}
#box{position:absolute;inset:0;border:1px solid #3cc48a}</style></head>
<body><div id="box"><p>stub ok</p><p id="size"></p><p>cookie ok</p></div>
<script>document.getElementById('size').textContent = 'window ' + innerWidth + 'x' + innerHeight;</script></body></html>"""


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        u = urlparse(self.path)
        cookie = dict(p.strip().split("=", 1) for p in (self.headers.get("Cookie") or "").split(";") if "=" in p)
        LOG.append({"path": u.path, "cookie": cookie.get("CF_Authorization", "")})
        if u.path == "/app/health/app-signin":
            state = parse_qs(u.query).get("state", [""])[0]
            tok = b64({"alg": "none"}) + "." + b64({"exp": int(time.time()) + 3600, "email": "chendeyao000@gmail.com"}) + ".stub"
            MINTED.add(tok)
            return self.send(302, b"", {"Location": f"dev.de0ch.yycsystems://signed-in?state={state}#token={tok}"})
        if u.path == "/app/health":
            if cookie.get("CF_Authorization") in MINTED:
                return self.send(200, PAGE.encode(), {"Content-Type": "text/html; charset=utf-8"})
            return self.send(302, b"", {"Location": "https://yyc-hk.cloudflareaccess.com/cdn-cgi/access/login/newswatch.yyc-internal.com"})
        if u.path == "/log":
            return self.send(200, json.dumps(LOG).encode(), {"Content-Type": "application/json"})
        return self.send(404, b"not found", {"Content-Type": "text/plain"})

    def send(self, code, body, headers):
        self.send_response(code)
        for k, v in {**headers, "Cache-Control": "no-store", "Content-Length": str(len(body))}.items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
