#!/usr/bin/env python3
"""Headless tests for the reachability prober (issue #129). No network egress —
everything runs against a local responder on 127.0.0.1. Run: python3 test_probe.py
"""
import socket
import threading
import unittest

import probe


def _responder(port, stop, echo_nonce=True):
    """Reference udp/PORT responder mirroring the node responder (issue #126):
    reply to `MAGIC + nonce` with `MAGIC_OK + nonce`. echo_nonce=False replies with
    a wrong nonce (to prove the prober rejects unbound responses)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", port))
    s.settimeout(0.2)
    while not stop.is_set():
        try:
            data, addr = s.recvfrom(512)
        except socket.timeout:
            continue
        if data.startswith(probe.MAGIC):
            nonce = data[len(probe.MAGIC):]
            reply = probe.MAGIC_OK + (nonce if echo_nonce else b"\xde\xad\xbe\xef")
            s.sendto(reply, addr)
    s.close()


def _free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


class ProbeTest(unittest.TestCase):
    def test_reachable_when_responder_echoes_nonce(self):
        port, stop = _free_port(), threading.Event()
        t = threading.Thread(target=_responder, args=(port, stop), daemon=True)
        t.start()
        try:
            ok, rtt, _ = probe.probe_udp("127.0.0.1", port, "a1b2c3d4", timeout_s=2)
            self.assertTrue(ok)
            self.assertIsInstance(rtt, int)
        finally:
            stop.set(); t.join(timeout=1)

    def test_not_reachable_when_silent(self):
        port = _free_port()  # nothing listening
        ok, rtt, detail = probe.probe_udp("127.0.0.1", port, "a1b2c3d4", timeout_s=1)
        self.assertFalse(ok)
        self.assertIsNone(rtt)

    def test_not_reachable_on_nonce_mismatch(self):
        # A responder that replies with the WRONG nonce must NOT count as reachable
        # (guards against a spoofed/unbound "reachable").
        port, stop = _free_port(), threading.Event()
        t = threading.Thread(target=_responder, args=(port, stop, False), daemon=True)
        t.start()
        try:
            ok, _, _ = probe.probe_udp("127.0.0.1", port, "a1b2c3d4", timeout_s=1)
            self.assertFalse(ok)
        finally:
            stop.set(); t.join(timeout=1)


if __name__ == "__main__":
    unittest.main()
