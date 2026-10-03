FROM alpine:3.20
RUN --mount=type=cache,id=s/6b0a7dda-c8e5-4a47-90b6-662095a26c2c-/c,target=/c sh -c 'echo "B own-id read:"; cat /c/markerA2.txt 2>/dev/null || echo "(none)"'
RUN --mount=type=cache,id=s/6aa4c0a0-e12c-4eb5-9935-ae56d40d5baa-/c,target=/c2 sh -c 'echo "B foreign-A-id read:"; cat /c2/markerA2.txt 2>/dev/null || echo "(none)"'
