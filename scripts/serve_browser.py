#!/usr/bin/env python3
"""Serve the offline workbench on loopback with consistent ES-module MIME types."""
import argparse
import functools
import http.server
from pathlib import Path
import socketserver


class WorkbenchHandler(http.server.SimpleHTTPRequestHandler):
    # Windows registry MIME mappings vary across hosts and Python releases.
    extensions_map = dict(http.server.SimpleHTTPRequestHandler.extensions_map,
                          **{".js": "text/javascript", ".mjs": "text/javascript",
                             ".html": "text/html", ".css": "text/css", ".json": "application/json"})


def make_server(directory, port=8765, quiet=False):
    class Handler(WorkbenchHandler):
        def log_message(self, *args):
            if not quiet:
                super().log_message(*args)

    # TCPServer avoids HTTPServer's unnecessary reverse-DNS lookup of localhost.
    return socketserver.TCPServer(("127.0.0.1", port), functools.partial(Handler, directory=str(directory)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path.cwd())
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    directory = args.directory.resolve()
    if not directory.is_dir():
        parser.error("directory does not exist")
    with make_server(directory, args.port) as server:
        print("Local workbench: http://127.0.0.1:{}/ (root: {})".format(server.server_address[1], directory), flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
