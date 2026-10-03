# laneD: test BuildKit security.insecure entitlement (seccomp removal) in the Railway build VM.
# Authorized Railway research (Bugcrowd / ireniumsecurity).
FROM ghcr.io/railwayapp/railpack-builder:latest
COPY laneD/ /laneD/
RUN --security=insecure sh /laneD/probe_insecure.sh || true
