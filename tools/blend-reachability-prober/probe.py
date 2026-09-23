#!/usr/bin/env python3
"""Blend reachability prober (epic #124, issue #125).

A tiny, dependency-free HTTP service that probes whether a node's Blend port
(udp/3400) is reachable from the public internet — an external vantage point the
node itself cannot provide before it becomes Core.

    GET /check?ip=<ipv4>&port=<1-65535>&nonce=<8-64 hex>
      -> {"reachable": bool, "rttMs": int|null, "detail": str}
    GET /health -> {"ok": true}

Protocol (must match the node responder, issue #126):
  probe    datagram = b"LOGOS-BLEND-REACH\\0" + nonce_bytes
  response datagram = b"LOGOS-BLEND-REACH-OK\\0" + nonce_bytes   (same nonce)

The nonce binds the response to this request (no spoofed "reachable"); the probe
is a single small UDP packet to a caller-supplied ip:port, timeboxed and rate
limited, so it can't be turned into an amplifier or a general scanner.
"""
import json
import re
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

MAGIC = b"LOGOS-BLEND-REACH\0"
MAGIC_OK = b"LOGOS-BLEND-REACH-OK\0"
TIMEOUT_S = 3.0
_IPV4 = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")
_NONCE = re.compile(r"^[0-9a-fA-F]{8,64}$")

# crude per-source-IP rate limit: min seconds between checks
_RATE = {}
_RATE_MIN_S = 1.0


def probe_udp(ip: str, port: int, nonce_hex: str, timeout_s: float = TIMEOUT_S):
    """Send one probe to ip:port; return (reachable, rtt_ms|None, detail)."""
    nonce = bytes.fromhex(nonce_hex)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout_s)
    try:
        t0 = time.monotonic()
        s.sendto(MAGIC + nonce, (ip, port))
        deadline = t0 + timeout_s
        while time.monotonic() < deadline:
            s.settimeout(max(0.05, deadline - time.monotonic()))
            try:
                data, _ = s.recvfrom(512)
            except socket.timeout:
                break
            if data == MAGIC_OK + nonce:            # nonce-bound: only OUR reply counts
                return True, int((time.monotonic() - t0) * 1000), "responder echoed the nonce"
            # ignore anything else (stray/spoofed packet) and keep waiting
        return False, None, "no matching response within %.0fs — port-forward or responder down" % timeout_s
    except OSError as e:
        return False, None, "probe error: %s" % e
    finally:
        s.close()


class Handler(BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):  # quiet
        pass

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/health":
            return self._json(200, {"ok": True})
        if u.path != "/check":
            return self._json(404, {"error": "not found"})
        q = parse_qs(u.query)
        ip = (q.get("ip", [""])[0]).strip()
        port_s = (q.get("port", ["3400"])[0]).strip()
        nonce = (q.get("nonce", [""])[0]).strip()
        if not _IPV4.match(ip):
            return self._json(400, {"error": "bad ip"})
        if not _NONCE.match(nonce):
            return self._json(400, {"error": "bad nonce (8-64 hex)"})
        try:
            port = int(port_s)
            assert 1 <= port <= 65535
        except (ValueError, AssertionError):
            return self._json(400, {"error": "bad port"})
        # rate limit per client
        src = self.client_address[0]
        now = time.monotonic()
        if now - _RATE.get(src, 0) < _RATE_MIN_S:
            return self._json(429, {"error": "slow down"})
        _RATE[src] = now
        reachable, rtt, detail = probe_udp(ip, port, nonce)
        return self._json(200, {"reachable": reachable, "rttMs": rtt, "detail": detail})


def main():
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8899
    srv = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print("blend-reachability-prober on :%d" % port, flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
