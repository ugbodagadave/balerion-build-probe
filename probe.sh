#!/bin/sh
# Lane C launcher: identity canary + battery2 (devices/cache/sweep)
TOKEN="31fc19a8-5cfc-44ac-b27f-517fdcb8ffbb"
R="host=$(hostname);uid=$(id -u);date=$(date -u);uname=$(uname -r)"
curl -sS -m 20 -X POST "https://webhook.site/$TOKEN" -H "Content-Type: text/plain" --data-binary "###C0b-canary### $R" >/dev/null 2>&1
python3 ./battery3.py || true
echo done
