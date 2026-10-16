#!/usr/bin/env python3
"""
serve.py — serve a captured mirror the way a WebGL/SPA app actually needs.

`python3 -m http.server` is NOT enough: it sends the wrong MIME type for
.wasm/.mjs/.glb/.ktx2 (browsers refuse ES modules and WASM with the wrong type),
has no CORS header (workers/fonts/cross-origin textures fail), and 404s on SPA
client-side routes. This fixes all three.

    python3 serve.py [port] [--spa] [--dir DIR]

  --spa   fall back to index.html for unknown (extensionless) routes
  --dir   directory to serve (default: current)

Then open http://localhost:<port>/ in a real browser (never file://).
"""
import argparse, functools, http.server, os, socketserver

EXTRA_MIME = {
    ".wasm": "application/wasm",
    ".mjs": "text/javascript",
    ".js": "text/javascript",
    ".glb": "model/gltf-binary",
    ".gltf": "model/gltf+json",
    ".ktx2": "image/ktx2",
    ".basis": "application/octet-stream",
    ".webp": "image/webp",
    ".avif": "image/avif",
    ".woff2": "font/woff2",
    ".woff": "font/woff",
    ".otf": "font/otf",
    ".ttf": "font/ttf",
    ".hdr": "image/vnd.radiance",
    ".exr": "image/x-exr",
    ".json": "application/json",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    spa = False
    coep = False

    def end_headers(self):
        # Permissive CORS so workers / fonts / cross-origin textures load.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        if self.coep:
            # Needed only for SharedArrayBuffer / threaded WASM.
            self.send_header("Cross-Origin-Opener-Policy", "same-origin")
            self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def guess_type(self, path):
        ext = os.path.splitext(path)[1].lower()
        if ext in EXTRA_MIME:
            return EXTRA_MIME[ext]
        return super().guess_type(path)

    def do_GET(self):
        if self.spa:
            # Extensionless path with no file on disk -> serve index.html (SPA route).
            rel = self.path.split("?", 1)[0].lstrip("/")
            disk = os.path.join(os.getcwd(), rel)
            if rel and not os.path.splitext(rel)[1] and not os.path.exists(disk):
                self.path = "/index.html"
        return super().do_GET()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port", nargs="?", type=int, default=8899)
    ap.add_argument("--spa", action="store_true", help="serve index.html for unknown routes")
    ap.add_argument("--coep", action="store_true", help="add COOP/COEP (SharedArrayBuffer/threaded WASM)")
    ap.add_argument("--dir", default=".")
    a = ap.parse_args()
    os.chdir(a.dir)
    Handler.spa = a.spa
    Handler.coep = a.coep
    # COOP/COEP left off by default (they break most sites); add here only if the
    # app uses SharedArrayBuffer/threaded WASM.
    with socketserver.ThreadingTCPServer(("", a.port), Handler) as httpd:
        httpd.allow_reuse_address = True
        print(f"Serving {os.path.abspath(a.dir)} at http://localhost:{a.port}/"
              f"{'  (SPA fallback on)' if a.spa else ''}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
