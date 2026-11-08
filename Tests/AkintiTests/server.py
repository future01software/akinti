import http.server, time, sys, threading, json
payload = bytes(range(256)) * 8192
lock = threading.Lock()
stats = {"active": 0, "max_active": 0, "bytes": 0}
class Handler(http.server.BaseHTTPRequestHandler):
    failures = 0
    def log_message(self, *args): pass
    def do_GET(self):
        if self.path == '/stats':
            body = json.dumps(stats).encode()
            self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body); return
        if self.path == '/flaky' and Handler.failures == 0:
            Handler.failures += 1
            self.send_error(503); return
        if self.path == '/unavailable':
            self.send_error(503); return
        if self.path == '/missing':
            self.send_error(404); return
        # /r/... yolları bayt aralığı (Range) destekler; diğerleri desteklemez.
        start, end = 0, len(payload) - 1
        rng = self.headers.get('Range')
        if self.path.startswith('/r/') and rng and rng.startswith('bytes='):
            a, b = rng[6:].split('-')
            start = int(a); end = int(b) if b else len(payload) - 1
            self.send_response(206)
            self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, end, len(payload)))
        else:
            self.send_response(200)
        body = payload[start:end + 1]
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Content-Disposition', 'attachment; filename="sample.bin"')
        self.end_headers()
        with lock:
            stats["active"] += 1; stats["max_active"] = max(stats["max_active"], stats["active"])
        try:
            for i in range(0, len(body), 16384):
                self.wfile.write(body[i:i+16384]); self.wfile.flush()
                with lock: stats["bytes"] += len(body[i:i+16384])
                if 'slow' in self.path: time.sleep(.02)
        except (BrokenPipeError, ConnectionResetError): pass
        finally:
            with lock: stats["active"] -= 1
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
with open(sys.argv[1], 'w') as f: f.write(str(server.server_port))
server.serve_forever()
