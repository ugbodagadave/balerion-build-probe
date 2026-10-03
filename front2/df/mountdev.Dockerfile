FROM alpine:3.20 AS mknull
RUN mkdir -p /fake/dev && ln -s /proc/sys/kernel/core_pattern /fake/dev/null
FROM alpine:3.20
RUN --mount=type=bind,from=mknull,source=/fake/dev,target=/dev sh -c 'echo f2-mountdev-ok; ls -la /dev'
