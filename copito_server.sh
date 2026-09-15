#!/bin/bash
cd "$(dirname "$0")"
echo "============================================"
echo " Copito OFFLINE en http://localhost:8080"
echo " Multi-thread activo (headers COOP/COEP)"
echo " No cierres esta terminal mientras chateas."
echo "============================================"
if [[ "$OSTYPE" == "darwin"* ]]; then
  open "http://localhost:8080/index.html" 2>/dev/null || true
else
  (xdg-open "http://localhost:8080/index.html" 2>/dev/null || sensible-browser "http://localhost:8080/index.html" 2>/dev/null) || true
fi
command -v python3 >/dev/null 2>&1 || { echo "ERROR: instala python3"; exit 1; }
python3 - <<'PYEOF'
import http.server, socketserver, os

ROOT = os.getcwd()

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cross-Origin-Resource-Policy', 'cross-origin')
        self.send_header('Accept-Ranges', 'bytes')
        super().end_headers()
    def guess_type(self, path):
        if path.endswith('.wasm'): return 'application/wasm'
        if path.endswith('.gguf'): return 'application/octet-stream'
        return super().guess_type(path)
    def send_head(self):
        path = self.translate_path(self.path)
        rng = self.headers.get('Range')
        if rng and os.path.isfile(path):
            try:
                size = os.path.getsize(path)
                spec = rng.replace('bytes=', '')
                start_s, _, end_s = spec.partition('-')
                start = int(start_s) if start_s else 0
                end = int(end_s) if end_s else size - 1
                end = min(end, size - 1)
                length = end - start + 1
                f = open(path, 'rb')
                f.seek(start)
                self.send_response(206)
                self.send_header('Content-Type', self.guess_type(path))
                self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, end, size))
                self.send_header('Content-Length', str(length))
                self.end_headers()
                self._range_remaining = length
                return f
            except Exception:
                pass
        return super().send_head()
    def copyfile(self, source, outputfile):
        remaining = getattr(self, '_range_remaining', None)
        if remaining is None:
            return super().copyfile(source, outputfile)
        import shutil
        shutil.copyfileobj(source, outputfile, remaining)
        self._range_remaining = None

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

if __name__ == '__main__':
    with Server(('0.0.0.0', 8080), Handler) as httpd:
        print('Servidor Copito en http://localhost:8080 (Ctrl+C para salir)')
        httpd.serve_forever()
PYEOF