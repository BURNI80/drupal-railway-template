# Drupal en Railway

Plantilla de producción para desplegar **Drupal 11** en [Railway](https://railway.com) con un clic: instalación automática, base de datos PostgreSQL privada, archivos persistentes y healthcheck integrado. Sin asistentes web ni configuración manual — despliegas y entras con tu usuario administrador.

> **English quick summary:** One-click production template for Drupal 11 on Railway. Deploys two services — a pinned `drupal:11.4.5` Apache image and PostgreSQL 17.6 — auto-installs Drupal on first boot with generated admin credentials, persists uploads on a volume at `sites/default`, exposes `/healthz.php` for Railway's healthcheck, and wires trusted hosts + reverse proxy automatically. **Key networking detail:** Apache listens on plain IPv4 and the service sets `PORT=80` so Railway routes traffic to it (see [Networking en Railway](#networking-en-railway)) — this avoids the classic 502 "connection refused" that happens when the image binds to `[::]:80` or to a port Railway isn't expecting. Full docs below are in Spanish; see [docs/PUBLICAR.md](docs/PUBLICAR.md) for the marketplace overview text in English.

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

## Networking en Railway (importante)

La imagen oficial de Drupal expone Apache en el puerto **80**, pero Railway decide por dónde enrutar el tráfico público y el healthcheck según dos cosas:

1. **`PORT`:** Railway inyecta una variable `PORT` con un valor por defecto (habitualmente **8080**) y enruta a ese puerto. Como Drupal escucha en el 80, hay que definir `PORT=80` explícitamente en el servicio; si no, el proxy de Railway recibe *connection refused* y devuelve **502**.
2. **Bind de Apache:** el `ports.conf` por defecto de Debian escucha en `[::]:80`, que en algunos entornos resuelve a **IPv6-only**. El proxy de Railway conecta por **IPv4**, así que también falla con *connection refused*. Por eso el `Dockerfile` copia `docker/ports.conf` con `Listen 0.0.0.0:80`.

Si despliegas y el sitio responde **502** es casi seguro una de estas dos causas; ver [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Después del despliegue

1. Espera a que el servicio **Drupal** esté en verde (el primer arranque instala el sitio, tarda ~2 min).
2. Abre tu dominio `<algo>.up.railway.app`.
3. Entra con usuario **admin** y la contraseña de la variable **`DRUPAL_ADMIN_PASSWORD`** (servicio Drupal → pestaña *Variables*).
4. Cambia la contraseña desde tu perfil si lo prefieres y configura el email del sitio.
5. *(Opcional)* Programa cron externo (p. ej. cron-job.org) apuntando a la URL `/cron/...` que aparece en los logs de despliegue.

## Variables

Todas vienen preconfiguradas en la plantilla — no tienes que crear ninguna. El servicio **Drupal** consume la base de datos por la **red privada** de Railway referenciando al servicio **Postgres**, así que si renombras el servicio Postgres solo hay que actualizar las referencias.

| Variable (servicio Drupal) | Valor / valor de referencia | Descripción |
|---|---|---|
| `PORT` | `80` | **Puerto donde escucha Apache** y el que Railway usa para enrutar HTTP y hacer el healthcheck. Sin esta variable Railway enruta a su puerto por defecto (8080) y da error 502. |
| `PGHOST` | `${{Postgres.RAILWAY_PRIVATE_DOMAIN}}` | Host de la base (hostname privado `.railway.internal` del servicio Postgres) |
| `PGPORT` | `5432` | Puerto interior de Postgres |
| `PGUSER` | `postgres` | Usuario superusuario de Postgres |
| `PGPASSWORD` | `${{Postgres.POSTGRES_PASSWORD}}` | Contraseña de Postgres (generada en el servicio Postgres) |
| `PGDATABASE` | `postgres` | Nombre de la base por defecto de la imagen |
| `DRUPAL_HASH_SALT` | generado (`secret`) | Salt de hash de Drupal |
| `DRUPAL_CRON_KEY` | generado (`secret`) | Clave de la URL de cron |
| `DRUPAL_ADMIN_USER` | `admin` | Usuario administrador inicial |
| `DRUPAL_ADMIN_PASSWORD` | generado (`secret`) | Contraseña del admin — **mírala en Variables** |
| `DRUPAL_ADMIN_MAIL` | `admin@example.com` | Email del admin (cámbialo por el tuyo) |
| `DRUPAL_SITE_NAME` | `My Drupal Site` | Nombre del sitio |
| `DRUPAL_SITE_MAIL` | `admin@example.com` | Email remitente del sitio |
| `TRUSTED_HOSTS` | *(vacío)* | Opcional: patrones extra de hosts confiables separados por coma (regex sin delimitadores), para dominios propios |
| `DRUPAL_ERROR_LEVEL` | `hide` | Pon `verbose` para depurar errores en pantalla |

> **Nota sobre las referencias:** esta plantilla usa la imagen oficial de Postgres como servicio *image-based*. A diferencia del Postgres "gestionado" de Railway, esa imagen **no** expone automáticamente `PGHOST`/`PGPORT`/`PGUSER`/`PGDATABASE`; por eso se referencian `RAILWAY_PRIVATE_DOMAIN` y `POSTGRES_PASSWORD` y los valores fijos se asignan en la propia plantilla. Si prefieres un Postgres gestionado, cambia el servicio por el de Railway y ajusta las referencias a `${{Postgres.PGHOST}}` etc.

## Credenciales

- **Admin de Drupal:** usuario `DRUPAL_ADMIN_USER` (por defecto `admin`) y contraseña `DRUPAL_ADMIN_PASSWORD` (se generan por despliegue; mírala en el servicio Drupal → pestaña *Variables*).
- **Base de datos:** solo accesible por red privada (nunca expuesta a internet). Las credenciales las resuelve automáticamente el entrypoint desde las variables `PG*` de la sección anterior.
- Cada despliegue de la plantilla genera secretos únicos (`DRUPAL_ADMIN_PASSWORD`, `DRUPAL_HASH_SALT`, `DRUPAL_CRON_KEY`, `POSTGRES_PASSWORD`) con `${{secret(...)}}` — nada hardcodeado ni compartido entre instancias.

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
│   ├── ports.conf                # obliga Apache a escuchar en IPv4 (0.0.0.0:80)
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
- **502 Bad Gateway**: casi siempre es el enrutado. Comprueba que existe `PORT=80` en el servicio Drupal y que Apache escucha en IPv4 (ver [Networking en Railway](#networking-en-railway-importante)).

## Licencia

GPL-2.0-or-later, igual que Drupal. Este repo solo añade pegamento (entrypoint, settings, healthcheck) sobre la imagen oficial de [Drupal](https://www.drupal.org), cuya marca y logo pertenecen a la Drupal Association.
