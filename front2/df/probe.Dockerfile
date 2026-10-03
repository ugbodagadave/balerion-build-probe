FROM alpine:3.20
COPY front2/scripts/front2_build_probe /probe
RUN chmod +x /probe && echo f2-probe-ok
