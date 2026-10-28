"""Serves todo.html on localhost and lets it read and write TODO.md, so nothing has to be picked.

Run with `make todo`. Only TODO.md can be written; everything else is read-only.
"""

import http.server
import pathlib
import sys
import threading
import webbrowser

ROOT = pathlib.Path(__file__).resolve().parent.parent
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_PUT(self):
        if self.path.split("?")[0] != "/TODO.md":
            self.send_error(403)
            return
        length = int(self.headers.get("Content-Length", 0))
        (ROOT / "TODO.md").write_bytes(self.rfile.read(length))
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
url = f"http://127.0.0.1:{PORT}/todo.html"
print(f"TODO en {url} (Ctrl+C para cerrar)")
threading.Timer(0.3, webbrowser.open, [url]).start()
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
