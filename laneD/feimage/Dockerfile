FROM curlimages/curl:latest
COPY probe64 /probe64
COPY fe_probe.sh /fe_probe.sh
RUN chmod +x /probe64 /fe_probe.sh
ENTRYPOINT ["/fe_probe.sh"]
