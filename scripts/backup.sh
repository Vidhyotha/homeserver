#!/usr/bin/env bash
# Homeserver data backup.
# Configs under /srv are already versioned in git; this backs up the data,
# secrets, and state that are NOT in the repo. Media (movies/music) is excluded.
# Some runtime files are root-owned, so parts of the backup run as root inside
# a throwaway container (dry-run needs the `redis:8.2` helper image locally).
set -euo pipefail

BACKUP_DIR="/srv/backups"
KEEP="7"                       # number of backups to retain
HELPER_IMAGE="redis:8.2"       # has a shell + tar, already present on the host
TS="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUP_DIR/homeserver-$TS"

mkdir -p "$DEST"

warn() { echo "WARN: $*" >&2; }

# 1) Env/secrets files (kept out of git) - needed to recover dashboards & services.
tar czf "$DEST/env-files.tgz" 2>/dev/null \
  -C /srv homepage/.env npm/.env watchtower/.env arcane/.env || warn "env files"

# 2) Root-owned host data, tarred as root via a throwaway container.
if docker image inspect "$HELPER_IMAGE" >/dev/null 2>&1; then
  docker run --rm -v /srv:/srv -e DEST="$DEST" --entrypoint /bin/sh "$HELPER_IMAGE" -c '
    set -e
    tar czf "$DEST/npm.tgz"       -C /srv/npm data letsencrypt || exit 10
    tar czf "$DEST/adguard.tgz"   -C /srv/adguard conf work    || exit 11
    tar czf "$DEST/tailscale.tgz" -C /srv/tailscale state      || exit 12
    tar czf "$DEST/arcane.tgz"    -C /srv/arcane data          || exit 13
    tar czf "$DEST/stremio.tgz"   -C /srv stremio              || exit 14
  ' || warn "root-owned data backup step failed"
else
  warn "helper image $HELPER_IMAGE not available; skipping root-owned data"
fi

# 3) Navidrome app database (media lives in /data/music and is excluded).
tar czf "$DEST/navidrome.tgz" 2>/dev/null \
  -C /data navidrome.db navidrome.db-shm navidrome.db-wal || warn "navidrome.db"

# 4) NPM MySQL dump straight out of the running DB container.
if docker inspect npm-db >/dev/null 2>&1; then
  docker exec npm-db sh -c 'mariadb-dump -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases --no-tablespaces' 2>/dev/null \
    | gzip > "$DEST/npm-db.sql.gz" || warn "mysql dump"
else
  warn "npm-db container not running; skipping MySQL dump"
fi

# 5) Open-WebUI named volume, copied out of the running container.
if docker inspect open-webui >/dev/null 2>&1; then
  docker cp open-webui:/app/backend/data "$DEST/open-webui" >/dev/null
  tar czf "$DEST/open-webui.tgz" -C "$DEST" open-webui
  rm -rf "$DEST/open-webui"
else
  warn "open-webui container not running; skipping its volume"
fi

# 6) Rotate old backups.
ls -1dt "$BACKUP_DIR"/homeserver-* 2>/dev/null | tail -n +"$((KEEP + 1))" | xargs -r rm -rf

echo "Backup complete: $DEST"