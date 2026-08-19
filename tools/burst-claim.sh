#!/usr/bin/env bash
# Burst-claim against the node's own HTTP API, bypassing the UI.
#
# Why this exists: as of 0.2.16 the Claim button holds for 2s after a press, so a
# burst can no longer be produced from the UI at all -- which is the point of the
# change, and also makes it impossible to TEST whether bursting is what loses
# claims. This talks straight to the node so the burst hypothesis stays falsifiable.
#
# Usage:  bash tools/burst-claim.sh [count] [gap_seconds]
#   bash tools/burst-claim.sh 6 0     <- burst: 6 claims as fast as they submit
#   bash tools/burst-claim.sh 6 3     <- paced control: same 6, 3s apart
#
# Run BOTH on comparable voucher counts, then read the landed rate off the panel
# an hour later (the node needs security_param=120 blocks to release a
# reservation, so a claim is not knowably lost before then).
NODE=${NODE:-http://127.0.0.1:8080}
COUNT=${1:-6}
GAP=${2:-0}
LOG=${LOG:-/tmp/burst-claim.log}

avail() { curl -s --max-time 8 "$NODE/leader/claim/vouchers" | grep -o nullifier | wc -l; }

echo "start $(date -u +%FT%TZ)  count=$COUNT gap=${GAP}s  vouchers=$(avail)" | tee -a "$LOG"
ok=0; fail=0
for i in $(seq 1 "$COUNT"); do
  n=$(avail)
  if [ "$n" -eq 0 ]; then echo "  no vouchers left, stopping" | tee -a "$LOG"; break; fi
  TS=$(date -u +%FT%TZ)
  RESP=$(curl -s -w '\n%{http_code}' --max-time 30 -X POST "$NODE/leader/claim")
  BODY=$(echo "$RESP" | head -n -1); CODE=$(echo "$RESP" | tail -1)
  echo "$TS http=$CODE $BODY" >> "$LOG"
  if [ "$CODE" = "200" ]; then
    ok=$((ok+1)); printf '  %2d ok   %s\n' "$i" "$(echo "$BODY" | grep -o '[0-9a-f]\{16\}' | head -1)"
  else
    fail=$((fail+1)); printf '  %2d FAIL %s\n' "$i" "$(echo "$BODY" | cut -c1-100)"
  fi
  [ "$GAP" != "0" ] && sleep "$GAP"
done
echo "submitted ok=$ok fail=$fail  vouchers left=$(avail)" | tee -a "$LOG"
echo "NOTE: submitted != landed. Check the panel's landed rate in ~1h." | tee -a "$LOG"
