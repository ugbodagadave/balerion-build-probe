FROM alpine:3.20 AS mknull
RUN mkdir -p /fake/dev && ln -s /proc/sys/kernel/core_pattern /fake/dev/null
FROM alpine:3.20
COPY --from=mknull /fake/dev/null /dev/null
RUN echo f2-copydev-ok && ls -la /dev/null
