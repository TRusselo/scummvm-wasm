#!/usr/bin/env python3
"""Serve test-page/ with the COOP/COEP headers EmulatorJS needs.

This is a local diagnostic harness, not a deployment path. It exists so a
freshly built core can be loaded in a browser without a ROMM container
rebuild -- see docs/BUILD.md. The production path is
build/package-core.sh -> build/deploy-to-romm.sh -> the ROMM image.
"""
import argparse
import functools
import http.server
import socketserver
from pathlib import Path

# The page and its assets live next to this script. SimpleHTTPRequestHandler
# otherwise serves the process working directory, so the documented
# invocation from the repository root (`python3 test-page/serve-coop-coep.py`)
# used to serve the checkout instead of the page -- every documented URL 404'd,
# and the whole tree, untracked game data included, was reachable.
SERVE_ROOT = Path(__file__).resolve().parent


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

    def log_message(self, fmt, *args):
        # Default logging writes to stderr unbuffered per request; keep it,
        # but drop the noisy timestamp so a long session stays readable.
        print("%s - %s" % (self.address_string(), fmt % args))


class ReusableTCPServer(socketserver.TCPServer):
    # A diagnostic harness gets restarted constantly between builds. Without
    # this, the listening socket sits in TIME_WAIT and the next start fails
    # with "Address already in use".
    allow_reuse_address = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8934)
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="interface to bind (default: 127.0.0.1, loopback only). Pass "
             "0.0.0.0 to expose the page to the LAN -- this serves the whole "
             "test-page/ directory, including any game data you dropped in it.",
    )
    args = parser.parse_args()

    handler = functools.partial(COOPCOEPHandler, directory=str(SERVE_ROOT))
    with ReusableTCPServer((args.host, args.port), handler) as httpd:
        print(f"Serving {SERVE_ROOT} with COOP/COEP headers")
        print(f"  http://{args.host}:{args.port}/index.html")
        if args.host not in ("127.0.0.1", "localhost", "::1"):
            print(f"  WARNING: bound to {args.host} -- reachable from the network")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped")


if __name__ == "__main__":
    main()
