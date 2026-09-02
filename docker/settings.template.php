<?php

/**
 * Drupal on Railway — settings.php
 *
 * Generated once by the entrypoint into sites/default/settings.php.
 * All values are read from environment variables at RUNTIME, so rotating a
 * database password or changing any variable in Railway takes effect on the
 * next deploy without touching this file.
 */

// ---------------------------------------------------------------------------
// Database (PostgreSQL).
// ---------------------------------------------------------------------------
$databases['default']['default'] = [
  'driver'   => 'pgsql',
  'database' => getenv('PGDATABASE') ?: 'railway',
  'username' => getenv('PGUSER') ?: 'postgres',
  'password' => getenv('PGPASSWORD') ?: '',
  'host'     => getenv('PGHOST') ?: 'postgres.railway.internal',
  'port'     => (int) (getenv('PGPORT') ?: 5432),
  'prefix'   => '',
  'isolation_level' => 'REPEATABLE READ',
];

// ---------------------------------------------------------------------------
// Security.
// ---------------------------------------------------------------------------
$settings['hash_salt'] = getenv('DRUPAL_HASH_SALT') ?: 'INSECURE-FALLBACK-CHANGE-ME';

$settings['update_free_access'] = FALSE;
$settings['rebuild_access'] = FALSE;
$settings['skip_permissions_hardening'] = FALSE;

// Trusted host patterns: localhost, Railway public/internal domains plus any
// extra patterns provided via the TRUSTED_HOSTS variable (comma separated,
// each entry is a regex without delimiters, e.g. ^www\.example\.com$).
$trusted = ['^localhost$', '^.+\.railway\.app$', '^.+\.railway\.internal$'];
if ($domain = getenv('RAILWAY_PUBLIC_DOMAIN')) {
  $trusted[] = '^' . preg_quote($domain, '/') . '$';
}
if ($extra = getenv('TRUSTED_HOSTS')) {
  foreach (explode(',', $extra) as $pattern) {
    if ($pattern = trim($pattern)) {
      $trusted[] = $pattern;
    }
  }
}
$settings['trusted_host_patterns'] = array_values(array_unique($trusted));

// ---------------------------------------------------------------------------
// Reverse proxy — Railway terminates TLS at its edge proxy.
// Private ranges cover Railway's internal network and proxy fleet.
// ---------------------------------------------------------------------------
$settings['reverse_proxy'] = TRUE;
$settings['reverse_proxy_addresses'] = [
  '10.0.0.0/8',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '100.64.0.0/10',
];

// ---------------------------------------------------------------------------
// File system. Everything lives under the volume mounted at sites/default so
// uploads survive redeploys. Temp files use the ephemeral /tmp (fast + safe).
// ---------------------------------------------------------------------------
$settings['file_public_path'] = 'sites/default/files';
$settings['file_private_path'] = 'sites/default/files-private';
$settings['file_temp_path'] = '/tmp';

// Config sync directory (unused in production but Drush warns without it).
$settings['config_sync_directory'] = '/tmp/config-sync';

// ---------------------------------------------------------------------------
// Error reporting: 'hide' for production, set DRUPAL_ERROR_LEVEL=verbose to debug.
// ---------------------------------------------------------------------------
$config['system.logging']['error_level'] = getenv('DRUPAL_ERROR_LEVEL') ?: 'hide';
