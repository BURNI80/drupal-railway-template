#!/usr/bin/env bash
#
# docker-entrypoint-railway — smart boot for Drupal on Railway.
#
# Responsibilities (idempotent, safe on every redeploy):
#   1. Resolve DB credentials from discrete PG* vars or DATABASE_URL.
#   2. Wait until PostgreSQL accepts connections.
#   3. Prepare sites/default + files dirs (volume mount point).
#   4. Write settings.php if missing (it reads env at runtime, so DB password
#      rotations apply without rewriting the file).
#   5. First boot: drush site:install with env-provided admin credentials.
#      Later boots: drush updatedb + cache rebuild.
#   6. Sync the cron key from env and fix ownership, then start Apache.

set -euo pipefail

log() { printf '[drupal-railway] %s\n' "$*"; }
fail() { printf '[drupal-railway] ERROR: %s\n' "$*" >&2; exit 1; }

DRUPAL_ROOT="${DRUPAL_ROOT:-/opt/drupal/web}"
SITE_DIR="${SITE_DIR:-$DRUPAL_ROOT/sites/default}"
SETTINGS_TEMPLATE="/usr/local/share/drupal-railway/settings.template.php"

# ---------------------------------------------------------------- 1) DB creds
# Preferred: discrete variables referenced in Railway as ${{Postgres.PGHOST}} etc.
# Fallback: parse DATABASE_URL (e.g. ${{Postgres.DATABASE_URL}}).
if [ -z "${PGHOST:-}" ] && [ -n "${DATABASE_URL:-}" ]; then
  # shellcheck disable=SC2046
  eval $(php -r '
    $u = parse_url(getenv("DATABASE_URL"));
    echo "PGHOST=", escapeshellarg($u["host"] ?? ""), " ",
         "PGPORT=", escapeshellarg((string)($u["port"] ?? "5432")), " ",
         "PGUSER=", escapeshellarg(urldecode($u["user"] ?? "")), " ",
         "PGPASSWORD=", escapeshellarg(urldecode($u["pass"] ?? "")), " ",
         "PGDATABASE=", escapeshellarg(urldecode(ltrim($u["path"] ?? "/railway", "/")));
  ')
fi

# Make parsed values visible to child processes (pdo_probe reads them via getenv).
export PGHOST PGUSER PGPASSWORD PGDATABASE

: "${PGHOST:?PGHOST is required (reference Postgres.PGHOST in Railway)}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${PGDATABASE:?PGDATABASE is required}"
export PGPORT="${PGPORT:-5432}"

db_dsn() {
  printf 'pgsql:host=%s;port=%s;dbname=%s' "$PGHOST" "$PGPORT" "$PGDATABASE"
}

pdo_probe() {
  php -r 'try{new PDO(getenv("DSN"),getenv("PGUSER"),getenv("PGPASSWORD"),[PDO::ATTR_TIMEOUT=>3]);exit(0);}catch(Throwable $e){fwrite(STDERR,$e->getMessage()."\n");exit(1);}'
}

# ------------------------------------------------------- 2) Wait for Postgres
export DSN="$(db_dsn)"
log "Waiting for PostgreSQL at ${PGHOST}:${PGPORT} (database ${PGDATABASE})..."
READY=0
for i in $(seq 1 90); do
  if pdo_probe 2>/dev/null; then READY=1; break; fi
  sleep 2
done
[ "$READY" = "1" ] || { pdo_probe || true; fail "PostgreSQL not reachable after 180s. Check the Postgres service logs."; }
log "PostgreSQL is up."

# ------------------------------------------- 3) Prepare site dir & settings
mkdir -p "$SITE_DIR/files" "$SITE_DIR/files-private"
if [ ! -f "$SITE_DIR/settings.php" ]; then
  cp "$SETTINGS_TEMPLATE" "$SITE_DIR/settings.php"
  log "settings.php generated (values are read from environment at runtime)."
fi

drush() {
  # Explicit --root kills any ambiguity about the Drupal directory (the official
  # image uses symlinked docroots); --uri keeps CLI-generated URLs correct.
  local uri="https://${RAILWAY_PUBLIC_DOMAIN:-localhost}"
  (cd "$DRUPAL_ROOT" && /usr/local/bin/drush --root="$DRUPAL_ROOT" --uri="$uri" --yes "$@")
}

installed() {
  # Pure PDO check (no psql client needed): the site is "installed" once the
  # super user row exists. Mirrors the logic of docker/healthz.php.
  php -r '
    try {
      $pdo = new PDO(getenv("DSN"), getenv("PGUSER"), getenv("PGPASSWORD"), [PDO::ATTR_TIMEOUT => 3]);
      $stmt = $pdo->query("SELECT 1 FROM users_field_data WHERE uid = 1");
      exit($stmt && $stmt->fetchColumn() ? 0 : 1);
    } catch (Throwable $e) { exit(1); }
  '
}

# --------------------------------------------------- 4) Install or update
DRUPAL_SITE_NAME="${DRUPAL_SITE_NAME:-My Drupal Site}"
DRUPAL_SITE_MAIL="${DRUPAL_SITE_MAIL:-admin@example.com}"
DRUPAL_ADMIN_USER="${DRUPAL_ADMIN_USER:-admin}"
DRUPAL_ADMIN_MAIL="${DRUPAL_ADMIN_MAIL:-${DRUPAL_SITE_MAIL}}"
CRON_KEY="${DRUPAL_CRON_KEY:-$(php -r 'echo bin2hex(random_bytes(32));')}"

if ! installed; then
  : "${DRUPAL_ADMIN_PASSWORD:?DRUPAL_ADMIN_PASSWORD is required for first install (use a template secret)}"
  log "Fresh database detected — installing Drupal (${DRUPAL_SITE_NAME}). This takes about a minute."
  # Explicit db-url avoids fragile settings-based spec parsing inside Drush's validator.
  DB_URL="$(php -r 'printf("pgsql://%s:%s@%s:%s/%s",
    urlencode(getenv("PGUSER")),
    urlencode(getenv("PGPASSWORD")),
    getenv("PGHOST"),
    getenv("PGPORT"),
    urlencode(getenv("PGDATABASE")));')"
  drush site:install standard \
    --db-url="$DB_URL" \
    --site-name="$DRUPAL_SITE_NAME" \
    --site-mail="$DRUPAL_SITE_MAIL" \
    --account-name="$DRUPAL_ADMIN_USER" \
    --account-pass="$DRUPAL_ADMIN_PASSWORD" \
    --account-mail="$DRUPAL_ADMIN_MAIL" \
    --no-interaction
  log "Drupal installed."
else
  log "Existing installation detected — running database updates."
  if ! drush -vvv updatedb; then
    log "updatedb failed — bootstrap diagnostics:"
    drush -vvv status || true
    fail "Drush could not bootstrap the existing installation."
  fi
  drush cache:rebuild
fi

# Keep the cron key in sync with the environment (used by external cron pings).
drush state:set system.cron_key "$CRON_KEY" >/dev/null

# Ensure config sync directory exists (Drush warns without it).
mkdir -p /tmp/config-sync

# ------------------------------------------------------------ 5) Permissions
# Drush runs as root; hand everything under sites/ to Apache's user.
chown -R www-data:www-data "$SITE_DIR"
chmod 0644 "$SITE_DIR/settings.php"

# --------------------------------------------------------------- 6) Banner
PUBLIC_URL="https://${RAILWAY_PUBLIC_DOMAIN:-localhost}"
log "=============================================================="
log " Drupal is ready: ${PUBLIC_URL}"
log " Admin user : ${DRUPAL_ADMIN_USER}"
log " Admin pass : stored in the DRUPAL_ADMIN_PASSWORD variable."
log " Cron URL   : ${PUBLIC_URL}/cron/${CRON_KEY}"
log " Health     : ${PUBLIC_URL}/healthz"
log "=============================================================="

# Ensure only ONE MPM is loaded — the base image may ship both mpm_event and
# mpm_prefork, causing AH00534 at Apache startup. Fix at runtime to be safe.
a2dismod -f mpm_event mpm_worker 2>/dev/null || true
rm -f /etc/apache2/mods-enabled/mpm_event.* /etc/apache2/mods-enabled/mpm_worker.*
a2enmod mpm_prefork 2>/dev/null || true

exec "$@"
