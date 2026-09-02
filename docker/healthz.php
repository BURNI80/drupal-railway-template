<?php

/**
 * Railway readiness endpoint.
 *
 * Returns 200 only when Drupal is fully usable:
 *   - PostgreSQL is reachable with the configured credentials
 *   - the installation has completed (users_field_data exists)
 *
 * Otherwise it returns 503 so Railway keeps waiting during the first install
 * and can detect real outages afterwards. No Drupal bootstrap is performed,
 * so this endpoint stays cheap and works even before Drupal is installed.
 */

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function json_exit(int $code, array $payload): never
{
    http_response_code($code);
    echo json_encode($payload, JSON_UNESCAPED_SLASHES);
    exit;
}

$host = getenv('PGHOST');
$user = getenv('PGUSER');
$pass = getenv('PGPASSWORD');
$db   = getenv('PGDATABASE') ?: 'railway';
$port = getenv('PGPORT') ?: '5432';

if (!$host || !$user) {
    json_exit(503, ['status' => 'waiting', 'detail' => 'database credentials not set yet']);
}

try {
    $pdo = new PDO(
        sprintf('pgsql:host=%s;port=%s;dbname=%s', $host, $port, $db),
        $user,
        $pass,
        [PDO::ATTR_TIMEOUT => 3, PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );

    $stmt = $pdo->query(
        "SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public' AND tablename = 'users_field_data'"
    );
    $installed = (int) $stmt->fetchColumn() > 0;

    if ($installed) {
        json_exit(200, ['status' => 'ok', 'installed' => true]);
    }

    json_exit(503, ['status' => 'installing', 'installed' => false]);
} catch (Throwable $e) {
    json_exit(503, ['status' => 'waiting', 'detail' => 'database not ready']);
}
