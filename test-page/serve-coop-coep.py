#!/usr/bin/env python3
import http.server
import socketserver

class COOPCOEPHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        # This project's core/.data/.wasm artifacts get rebuilt repeatedly
        # during a single debugging session while the server keeps running.
        # Without this, browsers may serve a stale cached copy on a normal
        # reload (no Cache-Control/ETag were being sent at all), silently
        # testing an old build and producing misleading results.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

if __name__ == "__main__":
    PORT = 8934
    with socketserver.TCPServer(("", PORT), COOPCOEPHandler) as httpd:
        print(f"Serving test-page/ with COOP/COEP headers on port {PORT}")
        httpd.serve_forever()
