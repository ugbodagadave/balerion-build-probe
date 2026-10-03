FROM alpine:3.20
RUN --mount=type=cache,id=s/6aa4c0a0-e12c-4eb5-9935-ae56d40d5baa-/c,target=/c sh -c 'f=0; grep -q A2 /c/markerA2.txt 2>/dev/null && f=$((f+1)); grep -q A3 /c/markerA3.txt 2>/dev/null && f=$((f+2)); grep -q FE_WROTE /c/fe_probe.txt 2>/dev/null && f=$((f+4)); echo "CACHE_FLAGS=$f"; exit $((40+f))'
