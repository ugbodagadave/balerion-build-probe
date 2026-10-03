FROM alpine:3.20
RUN --mount=type=bind,source=/etc/hostname,target=/mnt/h sh -c 'echo f2-mountproc-ok; cat /mnt/h'
