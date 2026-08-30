#!/usr/bin/env python3
import http.server
import socketserver

class COOPCOEPHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

if __name__ == "__main__":
    PORT = 8934
    with socketserver.TCPServer(("", PORT), COOPCOEPHandler) as httpd:
        print(f"Serving test-page/ with COOP/COEP headers on port {PORT}")
        httpd.serve_forever()
