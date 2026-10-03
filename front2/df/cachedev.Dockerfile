FROM alpine:3.20
RUN --mount=type=cache,id=f2devrace,target=/dev sh -c 'echo f2-cachedev-ok; ls -la /dev'
