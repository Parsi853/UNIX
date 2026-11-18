FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends util-linux \
    && rm -rf /var/lib/apt/lists/*

COPY worker.sh /usr/local/bin/concurrent-worker
ENTRYPOINT ["/bin/sh", "/usr/local/bin/concurrent-worker"]
