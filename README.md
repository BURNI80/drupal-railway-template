# Drupal en Railway

Plantilla de producción para desplegar **Drupal 11** en [Railway](https://railway.com) con un clic: instalación automática, base de datos PostgreSQL privada, archivos persistentes y healthcheck integrado. Sin asistentes web ni configuración manual — despliegas y entras con tu usuario administrador.

> **English quick summary:** One-click production template for Drupal 11 on Railway. Deploys two services — a pinned `drupal:11.4.5` Apache image and PostgreSQL 17.6 — auto-installs Drupal on first boot with generated admin credentials (see the `DRUPAL_ADMIN_PASSWORD` variable), persists uploads on a volume at `sites/default`, exposes `/healthz.php` for Railway's healthcheck, and wires trusted hosts + reverse proxy automatically. Full docs below are in Spanish; see [docs/PUBLICAR.md](docs/PUBLICAR.md) for the marketplace overview text in English.

---

## Qué incluye

| Servicio | Imagen / fuente | Versión fijada | Volúmenes |
|---|---|---|---|
| **Drupal** | Este repo (`Dockerfile`, basado en imagen oficial) | `drupal:11.4.5-php8.4-apache-bookworm`, Drush `13.7.6` | `/opt/drupal/web/sites/default` |
| **Postgres** | Imagen oficial | `postgres:17.6-alpine` | `/var/lib/postgresql/data` |

Los dos servicios se comunican por la **red privada de Railway** (`postgres.railway.internal`); la base de datos nunca queda expuesta a internet.

## Qué pasa al desplegar

1. Railway levanta Postgres y el contenedor de Drupal.
2. El entrypoint espera a que Postgres acepte conexiones.
3. Genera `sites/default/settings.php` leyendo las credenciales de variables de entorno (nada hardcodeado).
4. Detecta una base de datos vacía y ejecuta la instalación completa con Drush (~1 minuto): perfil *standard*, usuario admin y contraseña generados.
5. El healthcheck `/healthz.php` pasa a verde solo cuando el sitio es totalmente funcional, y Railway enruta el tráfico.

En redespliegues posteriores el arranque ejecuta `drush updatedb` + rebuild de caché: tus subidas y contenido sobreviven porque viven en el volumen.

## Después del despliegue

1. Espera a que el servicio **Drupal** esté en verde (el primer arranque instala el sitio, tarda ~2 min).
2. Abre tu dominio `<algo>.up.railway.app`.
3. Entra con usuario **admin** y la contraseña de la variable **`DRUPAL_ADMIN_PASSWORD`** (servicio Drupal → pestaña *Variables*).
4. Cambia la contraseña desde tu perfil si lo prefieres y configura el email del sitio.
5. *(Opcional)* Programa cron externo (p. ej. cron-job.org) apuntando a la URL `/cron/...` que aparece en los logs de despliegue.

## Variables

Todas vienen preconfiguradas en la plantilla — no tienes que crear ninguna:

| Variable | Valor en la plantilla | Descripción |
|---|---|---|
| `PGHOST` | `${{Postgres.PGHOST}}` | Host de la base de datos (red privada) |
| `PGPORT` | `${{Postgres.PGPORT}}` | Puerto de Postgres |
| `PGUSER` | `${{Postgres.PGUSER}}` | Usuario de Postgres |
| `PGPASSWORD` | `${{Postgres.PGPASSWORD}}` | Contraseña de Postgres |
| `PGDATABASE` | `${{Postgres.PGDATABASE}}` | Nombre de la base |
| `DRUPAL_HASH_SALT` | generado (`secret`) | Salt de hash de Drupal |
| `DRUPAL_CRON_KEY` | generado (`secret`) | Clave de la URL de cron |
| `DRUPAL_ADMIN_USER` | `admin` | Usuario administrador inicial |
| `DRUPAL_ADMIN_PASSWORD` | generado (`secret`) | Contraseña del admin — **mírala en Variables** |
| `DRUPAL_ADMIN_MAIL` | `admin@example.com` | Email del admin (cámbialo por el tuyo) |
| `DRUPAL_SITE_NAME` | `My Drupal Site` | Nombre del sitio |
| `DRUPAL_SITE_MAIL` | `admin@example.com` | Email remitente del sitio |
| `TRUSTED_HOSTS` | *(vacío)* | Opcional: patrones extra de hosts confiables separados por coma (regex sin delimitadores), para dominios propios |
| `DRUPAL_ERROR_LEVEL` | `hide` | Pon `verbose` para depurar errores en pantalla |

## Coste estimado

Con los tamaños por defecto (512 MB RAM en Drupal, volumen 1 GB): aproximadamente **5–8 USD/mes**, dentro del crédito del plan Hobby con margen estrecho. Detalles y trucos para reducirlo en [docs/COSTOS.md](docs/COSTOS.md).

## Desarrollo local

```bash
cp .env.example .env      # edita la contraseña si quieres
docker compose up --build
# abre http://localhost:8080
```

## Estructura del repo

```
├── Dockerfile                    # imagen final (drupal oficial + drush + tuning)
├── railway.json                  # builder Dockerfile + healthcheck
├── docker-compose.yml            # stack local equivalente
├── docker/
│   ├── docker-entrypoint.sh      # arranque inteligente (espera BD, instala, actualiza)
│   ├── settings.template.php     # settings.php que lee TODO de variables de entorno
│   ├── healthz.php               # endpoint de salud para Railway
│   ├── zz-railway.ini            # tuning PHP (memoria, uploads, opcache)
│   └── remoteip.conf             # confianza en el proxy edge de Railway
└── docs/
    ├── ARQUITECTURA.md           # cómo funciona todo por dentro
    ├── COSTOS.md                 # presupuesto en Railway
    ├── TROUBLESHOOTING.md        # problemas comunes
    └── PUBLICAR.md               # checklist para publicar la plantilla
```

## Solución de problemas

Ver [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). Lo más común:

- **El primer despliegue tarda**: la instalación corre durante el healthcheck (timeout 300 s). Si falla, revisa logs del servicio Drupal.
- **"The provided host name is not valid"**: añade tu dominio a `TRUSTED_HOSTS` (ej. `^www\.midominio\.com$`).

## Licencia

GPL-2.0-or-later, igual que Drupal. Este repo solo añade pegamento (entrypoint, settings, healthcheck) sobre la imagen oficial de [Drupal](https://www.drupal.org), cuya marca y logo pertenecen a la Drupal Association.
