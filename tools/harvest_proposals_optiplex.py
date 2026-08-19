#!/usr/bin/env python3
"""Persist this node's block proposals + a rewards time series (optiplex).

Adapted from the sneg harvester. Two things differ on this box and both matter:

1. The PRIMARY source is `logoscore.out`, the logoscore wrapper's stdout. It is
   ~400MB, never rotates, and holds the node's whole history — unlike the hourly
   `<epoch>.2026-*` files, which are pruned to ~10 and so lose everything older
   than about half a day. Reading 400MB every 15 minutes is wasteful, so we track
   a byte offset and read only what is new (restarting at 0 if the file shrinks,
   which is what a rotation or truncation looks like from here).

2. Lines carry a wrapper prefix and TWO timestamps:
     [2026-08-14 02:28:19.715] [out] [blockchain_module] 2026-08-14T00:28:19.715532Z INFO ...
   The bracketed one is wrapper-local; the ISO one is the module's UTC. The regex
   anchors on the ISO form on purpose — local time drifts between machines and has
   already caused one misread (sneg runs UTC, the workstation UTC+2).

Why this exists at all: leadership is private on chain — a block's leader_key is
per-note-derived, not a stable identity — so the node's own log is the ONLY source
for "my proposals". That is why this scrapes rather than queries.

The number it produces is the denominator for logos-blockchain-module#67: at the
time of writing optiplex logged 8 proposals but the node offered only 4 claimable
vouchers, and nothing in any API explains the other 4.
"""
import json, os, re, subprocess
from datetime import datetime, timezone
from pathlib import Path

NODE = "http://127.0.0.1:8080"
BASE = Path("/home/dar/logos-node")
STATE = Path("/home/dar/logos-harvest")
HIST = STATE / "proposals-history.json"
SERIES = STATE / "rewards-timeseries.jsonl"
OFFSET = STATE / "logoscore.offset.json"
WRAPPER = BASE / "logoscore.out"

ANSI = re.compile(r"\x1b\[[0-9;]*m")
PROP = re.compile(
    r"(?P<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})"
    r".*?proposed block HeaderId\((?P<id>[0-9a-f]{64})\)"
    r" with (?P<txs>\d+) transactions \((?P<removed>\d+) removed\)"
)
# "Chain is online. Starting block proposals." marks a (re)start of proposing.
# Counting these lets us separate "the node was down" from "the node did not win"
# without guessing — a distinction a restart-related hypothesis already got wrong.
START = re.compile(r"(?P<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}).*?Starting block proposals")


def curl(path):
    try:
        out = subprocess.run(["curl", "-s", "--max-time", "10", NODE + path],
                             capture_output=True, text=True, timeout=15)
        return json.loads(out.stdout) if out.stdout.strip() else None
    except Exception:
        return None


def load_json(p, default):
    if p.exists():
        try:
            return json.loads(p.read_text())
        except Exception:
            # Never lose the file to a parse error — keep a copy and start clean.
            p.rename(p.with_suffix(p.suffix + ".corrupt"))
    return default


def write_atomic(p, obj):
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, indent=1))
    tmp.replace(p)               # atomic: never a half-written history


def scan_text(text, hist, seen, starts):
    added = 0
    text = ANSI.sub("", text)
    for m in PROP.finditer(text):
        if m.group("id") in seen:
            continue
        seen.add(m.group("id"))
        hist.append({
            "id": m.group("id"),
            "time": m.group("ts").replace("T", " "),
            "txs": int(m.group("txs")),
            "removed": int(m.group("removed")),
        })
        added += 1
    for m in START.finditer(text):
        starts.add(m.group("ts"))
    return added


def main():
    STATE.mkdir(parents=True, exist_ok=True)
    hist = load_json(HIST, [])
    seen = {r["id"] for r in hist}
    starts = set(load_json(STATE / "proposal-starts.json", []))
    added = 0

    # --- primary: incremental tail of the never-rotating wrapper log ----------
    off = load_json(OFFSET, {"pos": 0})
    pos = int(off.get("pos", 0))
    if WRAPPER.exists():
        size = WRAPPER.stat().st_size
        if size < pos:
            pos = 0              # truncated or rotated — re-read from the top
        with WRAPPER.open("r", errors="replace") as fh:
            fh.seek(pos)
            chunk = fh.read()
            newpos = fh.tell()
        # Step back to the last newline so a line split across runs is not lost.
        cut = chunk.rfind("\n")
        if cut >= 0:
            newpos -= (len(chunk.encode("utf-8", "replace")) - len(chunk[:cut + 1].encode("utf-8", "replace")))
            chunk = chunk[:cut + 1]
        added += scan_text(chunk, hist, seen, starts)
        write_atomic(OFFSET, {"pos": newpos, "size": size})

    # --- belt and braces: every retained hourly file --------------------------
    for f in sorted(BASE.glob("[0-9]*.2026-*")):
        try:
            added += scan_text(f.read_text(errors="replace"), hist, seen, starts)
        except Exception:
            continue

    hist.sort(key=lambda r: r["time"], reverse=True)
    write_atomic(HIST, hist)
    write_atomic(STATE / "proposal-starts.json", sorted(starts))

    # --- snapshot the wallet next to the count -------------------------------
    pk = ""
    cfg = BASE / "user_config.yaml"
    if cfg.exists():
        in_leader = False
        for line in cfg.read_text(errors="replace").splitlines():
            t = line.strip()
            if t.startswith("leader:"):
                in_leader = True
                continue
            # Take the FIRST funding_pk after `leader:` — the file also carries an
            # unrelated sdp.wallet.funding_pk further down, and funding the wrong
            # key is exactly the bug that kept a node silent (logos-blockchain-ui#35).
            if in_leader and t.startswith("funding_pk:"):
                mm = re.search(r"[0-9a-fA-F]{64}", t)
                if mm:
                    pk = mm.group(0)
                break

    vouchers = curl("/leader/claim/vouchers")
    nv = len(vouchers.get("vouchers", [])) if isinstance(vouchers, dict) else None
    bal = curl(f"/wallet/{pk}/balance") if pk else None
    info = curl("/cryptarchia/info")
    ci = (info or {}).get("cryptarchia_info", info) or {}

    notes = (bal or {}).get("notes", {}) or {}
    # Reward notes are small and distinctive next to 1e12 faucet notes; counting
    # them is a proxy for "claims that have landed", since claims are not logged
    # (logos-blockchain-module#68).
    rewards = [v for v in notes.values() if 1_000 <= int(v) <= 1_000_000]

    snap = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "proposals_total": len(hist),
        "proposals_added": added,
        "proposal_starts": len(starts),
        "vouchers_available": nv,
        "balance": (bal or {}).get("balance"),
        "note_count": len(notes),
        "reward_notes": len(rewards),
        "reward_sum": sum(int(v) for v in rewards),
        "tip_slot": ci.get("slot"),
        "lib_slot": ci.get("lib_slot"),
        "state": ci.get("state"),
        "pk": pk[:12],
    }
    with SERIES.open("a") as fh:
        fh.write(json.dumps(snap) + "\n")

    print(json.dumps(snap))


if __name__ == "__main__":
    main()
