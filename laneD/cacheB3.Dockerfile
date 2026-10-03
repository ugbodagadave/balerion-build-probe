FROM alpine:3.20
RUN --mount=type=cache,id=s/6b0a7dda-c8e5-4a47-90b6-662095a26c2c-/c,target=/c sh -c 'echo "B3 marker $(date -u) token=${LANED_TOKEN}" >> /c/markerB.txt; echo "B3 wrote"; cat /c/markerB.txt'
