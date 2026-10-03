FROM alpine:3.20
RUN --mount=type=cache,id=laned-shared-cache-v1,target=/c sh -c 'echo hi > /c/m; cat /c/m'
