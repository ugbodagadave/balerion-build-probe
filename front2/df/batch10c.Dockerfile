FROM alpine:3.20 AS volumedev
VOLUME /dev
RUN echo f2-volumedev-ok
