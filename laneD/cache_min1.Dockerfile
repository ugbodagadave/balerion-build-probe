FROM alpine:3.20
RUN --mount=type=cache,target=/c sh -c 'echo hi > /c/m; cat /c/m'
