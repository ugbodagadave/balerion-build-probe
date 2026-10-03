FROM alpine:3.20
RUN --mount=type=cache,id=s/6aa4c0a0-e12c-4eb5-9935-ae56d40d5baa-/c,target=/c sh -c 'echo "A2 marker $(date -u)" >> /c/markerA2.txt; echo "A2 wrote; content:"; cat /c/markerA2.txt'
