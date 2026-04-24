FROM itzg/minecraft-server:java21

ARG PACKAGE_MODE=bootstrap
ARG ATM9_VERSION=1.1.1
ARG MINECRAFT_VERSION=1.20.1
ARG PACKAGE_VCS_REF=local
ARG PACKAGE_REPOSITORY_URL=https://github.com/TheClassyPenguin/all-the-docker-9

ENV MINECRAFT_SERVER_METADATA_FILE=/opt/minecraft-bootstrap/all-the-mods-9.env \
    MINECRAFT_SERVER_DATA_DIR=/data/server \
    MINECRAFT_SERVER_PORT=42424 \
    MINECRAFT_SERVER_MIN_MEMORY=4G \
    MINECRAFT_SERVER_MAX_MEMORY=8G \
    MINECRAFT_SERVER_BACKUP_ENABLED=true \
    MINECRAFT_SERVER_BACKUP_INTERVAL_SECONDS=21600 \
    MINECRAFT_SERVER_BACKUP_DIR=/data/backups \
    MINECRAFT_SERVER_BACKUP_RETENTION=8 \
    MINECRAFT_SERVER_BACKUP_SCOPE=world \
    MINECRAFT_SERVER_BACKUP_QUIESCE_SECONDS=5 \
    MINECRAFT_SERVER_WHITELIST_ENABLED=false \
    MINECRAFT_SERVER_RATE_LIMIT=0 \
    EULA=TRUE

LABEL org.opencontainers.image.title="minecraft-server-all-the-mods-9-bootstrap" \
      org.opencontainers.image.description="Lightweight ATM9 bootstrap image that downloads official server files at runtime" \
      org.opencontainers.image.source="${PACKAGE_REPOSITORY_URL}" \
      org.opencontainers.image.version="${ATM9_VERSION}" \
      org.opencontainers.image.revision="${PACKAGE_VCS_REF}" \
      io.codex.minecraft.package.mode="${PACKAGE_MODE}" \
      io.codex.minecraft.package.pack="all-the-mods-9" \
      io.codex.minecraft.package.atm9.version="${ATM9_VERSION}" \
      io.codex.minecraft.package.minecraft.version="${MINECRAFT_VERSION}"

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip \
    && rm -rf /var/lib/apt/lists/*

COPY all-the-mods-9.env /opt/minecraft-bootstrap/all-the-mods-9.env
COPY scripts/bootstrap-minecraft-server.sh /usr/local/bin/bootstrap-minecraft-server.sh
COPY scripts/minecraft-backup-loop.sh /usr/local/bin/minecraft-backup-loop.sh

RUN install -d -o minecraft -g minecraft /cache /cache/all-the-mods-9 /opt/minecraft-bootstrap \
    && chown minecraft:minecraft /opt/minecraft-bootstrap/all-the-mods-9.env \
    && chmod +x /usr/local/bin/bootstrap-minecraft-server.sh /usr/local/bin/minecraft-backup-loop.sh

USER minecraft

HEALTHCHECK --interval=30s --timeout=10s --start-period=420s --retries=5 CMD SERVER_HOST=127.0.0.1 SERVER_PORT=${MINECRAFT_SERVER_PORT:-42424} mc-health

EXPOSE 42424

ENTRYPOINT ["/usr/local/bin/bootstrap-minecraft-server.sh"]
