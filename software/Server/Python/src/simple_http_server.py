#!/usr/bin/env python3
"""
Simple read-only HTTP file server (no TLS).

On startup it asks for:
  - the TCP port to listen on
  - the folder to publish (Windows-style path, e.g. C:\\Users\\roniv\\Dev\\MSX\\gameroms)

Only GET/HEAD are served. Any method that could modify the filesystem
(PUT, POST, DELETE, PATCH, MKCOL, COPY, MOVE) is rejected with 403 Forbidden.
"""

import os
import sys
import time
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class ReadOnlyHTTPRequestHandler(SimpleHTTPRequestHandler):
    """SimpleHTTPRequestHandler that explicitly refuses any write method."""

    def log_message(self, format, *args):
        # Replace the default combined-log line with a plain "URL requested" line.
        pass

    def _log_request_url(self, method):
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] {self.client_address[0]} requested {method} {self.path}")

    def do_GET(self):
        self._log_request_url("GET")
        super().do_GET()

    def do_HEAD(self):
        self._log_request_url("HEAD")
        super().do_HEAD()

    def _reject_write(self):
        self._log_request_url(self.command + " (rejected)")
        self.send_error(403, "Forbidden: server is read-only")

    def do_PUT(self):
        self._reject_write()

    def do_POST(self):
        self._reject_write()

    def do_DELETE(self):
        self._reject_write()

    def do_PATCH(self):
        self._reject_write()

    def do_MKCOL(self):
        self._reject_write()

    def do_COPY(self):
        self._reject_write()

    def do_MOVE(self):
        self._reject_write()


def prompt_port():
    while True:
        raw = input("TCP port to listen on: ").strip()
        try:
            port = int(raw)
        except ValueError:
            print("Please enter a valid integer port number.")
            continue
        if not (1 <= port <= 65535):
            print("Port must be between 1 and 65535.")
            continue
        return port


def prompt_folder():
    while True:
        raw = input(r"Folder to publish (e.g. C:\Users\roniv\Dev\MSX\gameroms): ").strip().strip('"')
        if not raw:
            print("Please enter a folder path.")
            continue
        path = os.path.normpath(raw)
        if not os.path.isdir(path):
            print(f'"{path}" is not a valid directory.')
            continue
        return os.path.abspath(path)


def main():
    port = prompt_port()
    folder = prompt_folder()

    handler = functools.partial(ReadOnlyHTTPRequestHandler, directory=folder)
    server = ThreadingHTTPServer(("", port), handler)

    print(f"\nServing '{folder}' read-only on http://localhost:{port}/ (Ctrl+C to stop)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        server.server_close()


if __name__ == "__main__":
    sys.exit(main())
