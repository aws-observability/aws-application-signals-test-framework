# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

"""Forward original OTLP HTTP request bytes to AWS over TLS, without signing."""

import logging
import os
import select
import socket
import socketserver
import ssl
import sys
import threading


class OtlpForwardingHandler(socketserver.BaseRequestHandler):
    """Inspect the first request path, then relay the complete byte stream."""

    def handle(self):
        self.request.settimeout(60)
        try:
            request = b""
            while b"\r\n\r\n" not in request:
                data = self.request.recv(65536)
                if not data:
                    return
                request += data
                if len(request.split(b"\r\n\r\n", 1)[0]) > 65536:
                    raise ValueError("Request headers are too large")

            method, path, _ = request.split(b"\r\n", 1)[0].decode("ascii").split()
            if method == "GET" and path == "/healthcheck":
                self.request.sendall(
                    b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                )
                return

            if method != "POST" or path not in self.server.destinations:
                self.request.sendall(
                    b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                )
                return

            host = self.server.destinations[path]
            with socket.create_connection((host, 443), timeout=10) as connection:
                with self.server.tls.wrap_socket(connection, server_hostname=host) as upstream:
                    upstream.sendall(request)
                    upstream.setblocking(False)
                    want_write = False
                    while True:
                        if upstream.pending():
                            readable = [upstream]
                        else:
                            readable, writable, _ = select.select(
                                [self.request, upstream], [upstream] if want_write else [], [], 60
                            )
                            if writable and upstream not in readable:
                                readable.append(upstream)
                        if not readable:
                            return
                        for source in readable:
                            try:
                                data = source.recv(65536)
                                want_write = False
                            except ssl.SSLWantReadError:
                                want_write = False
                                continue
                            except ssl.SSLWantWriteError:
                                want_write = True
                                continue
                            if not data:
                                return
                            if source is self.request:
                                upstream.settimeout(10)
                                try:
                                    upstream.sendall(data)
                                finally:
                                    upstream.setblocking(False)
                            else:
                                self.request.sendall(data)
        except (OSError, ValueError):
            logging.exception("OTLP forwarding failed")


class OtlpForwardingProxy(socketserver.ThreadingTCPServer):
    """Route each signal to its AWS endpoint while preserving signed requests."""

    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, region, address=("127.0.0.1", 4318)):
        self.destinations = {
            "/v1/traces": f"xray.{region}.amazonaws.com",
            "/v1/logs": f"logs.{region}.amazonaws.com",
            "/v1/metrics": f"monitoring.{region}.amazonaws.com",
        }
        self.tls = ssl.create_default_context()
        super().__init__(address, OtlpForwardingHandler)


def start_proxy():
    """Start the opt-in test proxy with the Django sample app."""
    if (
        os.environ.get("OTLP_PROXY_ENABLED") != "true"
        or sys.argv[1:2] != ["runserver"]
        or ("--noreload" not in sys.argv and os.environ.get("RUN_MAIN") != "true")
    ):
        return
    region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")
    if not region:
        raise ValueError("OTLP_PROXY_ENABLED requires AWS_REGION or AWS_DEFAULT_REGION")
    proxy = OtlpForwardingProxy(region)
    threading.Thread(target=proxy.serve_forever, daemon=True).start()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    with OtlpForwardingProxy(sys.argv[1]) as proxy:
        proxy.serve_forever()
