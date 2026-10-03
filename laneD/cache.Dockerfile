# laneD D2 — cross-build cache namespace probe (authorized Railway research)
# Role/behavior selected via service variable LANED_ROLE (A writes markers, B/C read).
FROM alpine:3.20
ARG LANED_ROLE
ARG LANED_TOKEN
ARG LANED_SLEEP=0

RUN sh -c 'echo "== VM-FP role=${LANED_ROLE} token=${LANED_TOKEN} =="; echo "host=$(hostname)"; echo "boot_id=$(cat /proc/sys/kernel/random/boot_id)"; echo "uptime=$(cat /proc/uptime)"; echo "kernel=$(uname -r)"; echo "cgroup=$(cat /proc/self/cgroup)"; echo "unix_socks:"; cat /proc/net/unix; echo "mounts:"; cat /proc/self/mountinfo | head -30'

RUN --mount=type=cache,id=laned-shared-cache-v1,target=/c,sharing=shared \
    sh -c 'echo "== CACHE-V1 role=${LANED_ROLE} token=${LANED_TOKEN} date=$(date -u) =="; echo "-- ls /c --"; ls -la /c; echo "-- marker-v1 before --"; cat /c/marker.txt 2>/dev/null || echo "(none)"; if [ "${LANED_ROLE}" = "A" ]; then echo "MARKER_V1_${LANED_TOKEN}" >> /c/marker.txt; echo "A: wrote marker-v1"; fi; echo "-- marker-v1 after --"; cat /c/marker.txt 2>/dev/null || echo "(none)"'

RUN --mount=type=cache,id=laned-shared-cache-v2,target=/c2,sharing=shared \
    sh -c 'echo "== CACHE-V2 role=${LANED_ROLE} token=${LANED_TOKEN} =="; echo "-- marker-v2 before --"; cat /c2/marker2.txt 2>/dev/null || echo "(none)"; if [ "${LANED_ROLE}" = "A" ]; then echo "MARKER2_V1_${LANED_TOKEN}" >> /c2/marker2.txt; echo "A: wrote marker-v2"; fi; echo "-- marker-v2 after --"; cat /c2/marker2.txt 2>/dev/null || echo "(none)"'

RUN sh -c 'echo "== SLEEP ${LANED_SLEEP}s role=${LANED_ROLE} =="; sleep ${LANED_SLEEP}; echo "== DONE role=${LANED_ROLE} =="'
