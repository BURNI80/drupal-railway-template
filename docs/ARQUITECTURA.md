# Arquitectura

## Topología

```
                        Internet (HTTPS)
                              │
                    ┌─────────▼─────────┐
                    │  Railway edge/TLS  │   *.up.railway.app
                    └─────────┬─────────┘
                              │ HTTP (proxy de confianza)
              ┌───────────────▼───────────────┐
              │        servicio Drupal        │
              │  Apache + PHP 8.4 + Drupal 11 │
              │  healthcheck: /healthz.php    │
              └───────┬───────────────┬───────┘
                      │               │
         volumen 1 GB │               │ red privada (.railway.internal)
     sites/default    │               │ postgres.railway.internal:5432
   ├── settings.php   │    ┌──────────▼────────┐
   ├── files/         │    │ servicio Postgres │  postgres:17.6-alpine
   └── files-private/ │    │ volumen 1 GB      │  NO expuesto a internet
                      │    └───────────────────┘
```

- **Drupal** se construye desde el `Dockerfile` de este repo sobre la imagen oficial `drupal:11.4.5-php8.4-apache-bookworm` con Drush `13.7.6` añadido.
- **Postgres** es la imagen oficial fijada; solo accesible por red privada.
- Todo lo persistente vive en volúmenes: el filesystem del contenedor es efímero.

## Layout del docroot (importante)

La imagen oficial de Drupal guarda la aplicación en layout Composer en `/opt/drupal`:

```
/opt/drupal/
├── composer.json      ← proyecto drupal/recommended-project
├── vendor/            ← dependencias PHP + binario de Drush
└── web/               ← docroot real (index.php, core/, sites/, ...)
    └── sites/default  ← aquí monta Railway el volumen persistente
```

Este `Dockerfile` respeta ese layout nativo en vez de aplanarlo:

1. Instala Drush dentro del proyecto (`composer require --working-dir=/opt/drupal`), tal como recomienda la documentación upstream — así el preflight de Drush encuentra `drupal/core` y nunca se queja de "globally installed".
2. Sustituye el vhost por defecto de Apache por `docker/railway-site.conf`, que apunta `DocumentRoot` a `/opt/drupal/web`.
3. El volumen persistente se monta en `/opt/drupal/web/sites/default`.

No tocar estos tres puntos: aplanar el docroot rompe las rutas relativas del autoloader de Composer, y copiar un `composer.json` ajeno al docroot hace que Drush resuelva una raíz inexistente (`<root>/web/web`).

## Secuencia de arranque (`docker/docker-entrypoint.sh`)

El script corre en cada arranque y es idempotente:

1. **Credenciales**: usa las variables discretas `PG*`. Si solo existe `DATABASE_URL`, la parsea y exporta.
2. **Espera activa**: sondea Postgres con PDO hasta 180 s (Railway arranca ambos servicios a la vez).
3. **Directorio del sitio**: crea `files/` y `files-private/`; copia `settings.template.php` → `sites/default/settings.php` si no existe.
4. **¿Instalado?**: consulta PDO directa buscando la fila `uid=1` en `users_field_data` (sin depender del binario `psql`, que no viene en la imagen).
   - *No instalado* → `drush site:install standard --db-url=...` con nombre del sitio, email y credenciales admin de variables de entorno (~1 min). La `--db-url` explícita evita el parseo frágil de especificaciones dentro del validador de Drush.
   - *Ya instalado* → `drush updatedb` + rebuild de caché (aplica actualizaciones al cambiar de versión de Drupal).
5. **Cron key**: sincroniza `system.cron_key` con `DRUPAL_CRON_KEY` para que la URL `/cron/<clave>` sea estable.
6. **Permisos**: `chown www-data` recursivo en `sites/default` (Drush corre como root; Apache como www-data).
7. `exec apache2-foreground`.

Todas las llamadas a Drush pasan `--root` y `--uri` explícitos: elimina cualquier ambigüedad de resolución de raíz y genera URLs correctas desde CLI.

## Decisiones de diseño

### settings.php lee variables de entorno en tiempo de ejecución
El archivo se genera una vez y no se reescribe nunca: contiene `getenv(...)` en vez de valores literales. Rotar la contraseña de la base de datos o cambiar cualquier variable surte efecto en el siguiente despliegue sin regenerar nada, y evita problemas de inyección/escaping.

### Volumen montado en `sites/default`
Es la única ruta bajo el docroot que Drupal escribe en producción: subidas públicas (`files/`), ficheros privados (`files-private/`) y metadatos generados (twig compilado). Montar ahí el volumen garantiza que todo sobreviva redeployments con un único mount point. En esta imagen la ruta física es `/opt/drupal/web/sites/default` (ver layout arriba).

### Un único MPM de Apache
El módulo `mod_php` no es thread-safe: exige MPM `prefork`. El Dockerfile deshabilita explícitamente `mpm_event`/`mpm_worker` y habilita `mpm_prefork`; si la capa base trajese más de un MPM activo, Apache moriría con `AH00534: More than one MPM loaded`.

### Apache escucha en IPv4 y en el puerto que Railway espera
Dos detalles de red que evitan el clásico **502 "connection refused"**:

1. **IPv4 explícito.** El `ports.conf` por defecto de Debian escucha en `[::]:80`, que en algunos entornos resuelve a IPv6-only, mientras que el proxy edge de Railway conecta por IPv4. El Dockerfile copia `docker/ports.conf` con `Listen 0.0.0.0:80` (ver `/proc/1/net/tcp` como diagnóstico: el listener de IPv4 estaba vacío).
2. **`PORT=80`.** Railway enruta el tráfico público y el healthcheck al puerto de la variable `PORT`, cuyo valor por defecto es **8080** (no 80, que es donde escucha Drupal). Si no se define `PORT=80`, el proxy recibe *connection refused* y devuelve 502, aunque el deploy figure como `SUCCESS`. Esta variable debe venir preconfigurada en la plantilla.

Ambos son requisitos para que "funcione a un clic" sin que el usuario final toque nada.

### Healthcheck honesto (`healthz.php`)
Devuelve **200 solo cuando el sitio es plenamente usable** (PDO conecta Y `users_field_data` existe). Durante la primera instalación responde 503 y Railway sigue esperando dentro del timeout de 300 s. No arranca Drupal (bootstrap cero): es barato y funciona incluso antes de instalar.

### Proxy inverso confiable
Railway termina TLS en su edge. `settings.php` activa `reverse_proxy` con rangos privados (RFC1918 + CGNAT) y `mod_remoteip` hace lo mismo en Apache: Drupal ve IPs reales de cliente, genera URLs https correctas y los logs no muestran la IP del proxy.

### Secretos
Ningún valor sensible va hardcodeado: `DRUPAL_ADMIN_PASSWORD`, `DRUPAL_HASH_SALT` y `DRUPAL_CRON_KEY` usan funciones `${{secret(...)}}` de la sintaxis de plantillas de Railway, así cada despliegue de la plantilla recibe secretos únicos.

## Actualizar Drupal

Sube el pin del `Dockerfile` (ej. `drupal:11.x.y-php8.4-apache-bookworm`) y redespliega: el entrypoint ejecutará `updatedb` automáticamente. La base de datos y los archivos no se tocan.

## Limitaciones conocidas

- Una sola réplica de Drupal (el volumen montado impide escalar horizontal sin storage compartido tipo S3 — módulo contrib `s3fs` si algún día hace falta).
- Sin Redis/Memcached: caché en base de datos (suficiente para sitios pequeños/medianos).
- Emails: sin MTA local; configura un módulo SMTP (contrib) para correo saliente real.
