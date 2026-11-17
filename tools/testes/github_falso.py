"""GitHub de mentira para testar o atualizador do launcher (sem internet).
uso: python3 github_falso.py PORTA TAG ZIP [TOKEN]
- /repos/<dono>/<repo>/releases/latest -> JSON com tag_name e o asset atualizacao.zip
- /assets/1 (Accept: octet-stream, com a chave) -> 302 para /s3/atualizacao.zip
- /s3/atualizacao.zip -> o zip; recusa (400) se vier com a chave, como o armazenamento do GitHub
"""
import sys, json, http.server
porta, tag, zip_, token = int(sys.argv[1]), sys.argv[2], sys.argv[3], (sys.argv[4] if len(sys.argv) > 4 else "")
log = open("/tmp/github_falso.log", "a")

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _r(self, code, body=b"", tipo="application/json", extra=None):
        self.send_response(code)
        self.send_header("Content-Type", tipo); self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items(): self.send_header(k, v)
        self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        auth = self.headers.get("Authorization", "")
        log.write(f"{self.path} auth={'sim' if auth else 'nao'} accept={self.headers.get('Accept')}\n"); log.flush()
        if self.path.endswith("/releases/latest"):
            if token and auth != "Bearer " + token:   # como o GitHub: chave errada 401, sem chave (privado) 404
                return self._r(401, b'{"message":"Bad credentials"}') if auth else self._r(404, b'{"message":"Not Found"}')
            body = {"tag_name": tag, "assets": [{"name": "atualizacao.zip", "url": f"http://127.0.0.1:{porta}/assets/1"}]}
            return self._r(200, json.dumps(body).encode())
        if self.path == "/assets/1":
            if token and auth != "Bearer " + token:   # como o GitHub: chave errada 401, sem chave (privado) 404
                return self._r(401, b'{"message":"Bad credentials"}') if auth else self._r(404, b'{"message":"Not Found"}')
            return self._r(302, extra={"Location": f"http://127.0.0.1:{porta}/s3/atualizacao.zip"})
        if self.path == "/s3/atualizacao.zip":
            if auth: return self._r(400, b"Only one auth mechanism allowed", "text/plain")
            return self._r(200, open(zip_, "rb").read(), "application/octet-stream")
        self._r(404, b"{}")

http.server.ThreadingHTTPServer(("127.0.0.1", porta), H).serve_forever()
