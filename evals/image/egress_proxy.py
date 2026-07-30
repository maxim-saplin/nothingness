#!/usr/bin/env python3
"""Minimal exact-host HTTP proxy for evaluator egress."""
from __future__ import annotations

import argparse
import http.server
import ipaddress
import socket
import socketserver
import threading
from urllib.parse import urlsplit


def allowed_destination(host: str, port: int, allowed_hosts: set[str]) -> bool:
    normalized = host.lower().rstrip(".")
    try:
        ipaddress.ip_address(normalized)
    except ValueError:
        return normalized in allowed_hosts and port == 443
    return False


def split_authority(value: str, default_port: int = 80) -> tuple[str, int] | None:
    if value.startswith("["):
        return None
    host, separator, port_text = value.rpartition(":")
    if not separator:
        return value, default_port
    if not host or not port_text.isdigit():
        return None
    port = int(port_text)
    return (host, port) if 1 <= port <= 65535 else None


def relay(source: socket.socket, destination: socket.socket) -> None:
    import select

    while True:
        readable, _, _ = select.select((source, destination), (), (), 30)
        if not readable:
            return
        for current, other in ((source, destination), (destination, source)):
            if current not in readable:
                continue
            data = current.recv(65536)
            if not data:
                return
            other.sendall(data)


class Proxy(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    allowed_hosts: set[str] = set()

    def log_message(self, format: str, *args: object) -> None:
        return

    def denied(self) -> None:
        self.send_error(403, "destination denied")

    def do_CONNECT(self) -> None:
        destination = split_authority(self.path)
        if destination is None or not allowed_destination(*destination, self.allowed_hosts):
            self.denied()
            return
        try:
            upstream = socket.create_connection(destination, timeout=10)
        except OSError:
            self.send_error(502, "upstream unavailable")
            return
        self.send_response(200, "Connection Established")
        self.end_headers()
        try:
            relay(self.connection, upstream)
        finally:
            upstream.close()

    def do_GET(self) -> None:
        parsed = urlsplit(self.path)
        if parsed.scheme != "https" or not parsed.hostname or not allowed_destination(parsed.hostname, parsed.port or 443, self.allowed_hosts):
            self.denied()
            return
        self.send_error(501, "use CONNECT")

    do_POST = do_GET
    do_PUT = do_GET
    do_DELETE = do_GET
    do_HEAD = do_GET
    do_OPTIONS = do_GET
    do_PATCH = do_GET


class Forwarder(socketserver.BaseRequestHandler):
    destination: tuple[str, int]

    def handle(self) -> None:
        with socket.create_connection(self.destination, timeout=10) as upstream:
            relay(self.request, upstream)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--allow-host", action="append", required=True)
    parser.add_argument("--port", type=int, default=3128)
    parser.add_argument("--novnc-host", required=True)
    parser.add_argument("--novnc-port", type=int, default=6080)
    arguments = parser.parse_args()
    Proxy.allowed_hosts = {host.lower().rstrip(".") for host in arguments.allow_host}
    Forwarder.destination = (arguments.novnc_host, 6080)
    with socketserver.ThreadingTCPServer(("0.0.0.0", arguments.port), Proxy) as proxy, socketserver.ThreadingTCPServer(("0.0.0.0", arguments.novnc_port), Forwarder) as novnc:
        proxy.daemon_threads = True
        novnc.daemon_threads = True
        thread = threading.Thread(target=novnc.serve_forever, daemon=True)
        thread.start()
        proxy.serve_forever()


if __name__ == "__main__":
    main()