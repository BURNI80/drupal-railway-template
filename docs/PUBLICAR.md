# Checklist de publicación de la plantilla

> ⚠️ Este documento describe los pasos **futuros**. Según las reglas acordadas: NO crear repo en GitHub, NO hacer push y NO desplegar en Railway hasta que el propietario lo ordene explícitamente.

## Estado actual

- [x] Dockerfile + entrypoint + settings + healthcheck escritos y revisados
- [x] Sintaxis bash validada (`bash -n`)
- [x] Fallos corregidos: export de PG* tras parsear `DATABASE_URL`, literal `${{ }}` eliminado del mensaje de error (provocaba *bad substitution*), generador aleatorio vía PHP en vez de openssl
- [ ] Prueba end-to-end real (requiere desplegar en Railway)
- [ ] Repo público creado y push
- [ ] Plantilla publicada

## Fase 1 — Repo público

1. Crear repo GitHub (nombre sugerido: `drupal-railway-template`), público.
2. `git init`, commit inicial, push a `main`. No subir `.env`.
3. Verificar que GitHub Actions no interfiera (repo sin workflows).

## Fase 2 — Proyecto real en Railway

1. Nuevo proyecto vacío en el workspace.
2. Añadir servicio **GitHub Repo** → apuntar al repo (raíz = raíz del repo). Railway detecta `railway.json` (builder Dockerfile, healthcheck `/healthz.php`, timeout 300 s).
3. Añadir base de datos: **Add → Database → PostgreSQL** (así hereda las variables mágicas `PG*`/`DATABASE_URL`).
4. Variables del servicio Drupal:

   | Variable | Valor |
   |---|---|
   | `PGHOST` | `${{Postgres.PGHOST}}` |
   | `PGPORT` | `${{Postgres.PGPORT}}` |
   | `PGUSER` | `${{Postgres.PGUSER}}` |
   | `PGPASSWORD` | `${{Postgres.PGPASSWORD}}` |
   | `PGDATABASE` | `${{Postgres.PGDATABASE}}` |
   | `DRUPAL_HASH_SALT` | `${{secret(64,"abcdef0123456789")}}` |
   | `DRUPAL_CRON_KEY` | `${{secret(32,"abcdef0123456789")}}` |
   | `DRUPAL_ADMIN_USER` | `admin` |
   | `DRUPAL_ADMIN_PASSWORD` | `${{secret(24)}}` |
   | `DRUPAL_ADMIN_MAIL` | `admin@example.com` |
   | `DRUPAL_SITE_NAME` | `My Drupal Site` |
   | `DRUPAL_SITE_MAIL` | `admin@example.com` |

5. Generar dominio público en el servicio Drupal (Settings → Networking → Generate Domain).
6. Adjuntar volúmenes:
   - Drupal → mount path `/opt/drupal/web/sites/default`
   - Postgres → mount path `/var/lib/postgresql/data`
7. Desplegar y validar E2E:
   - [ ] Healthcheck verde (primer arranque ≈ 1–3 min)
   - [ ] Login con `admin` / valor de `DRUPAL_ADMIN_PASSWORD`
   - [ ] Crear un artículo con imagen → subida OK
   - [ ] Redesploy (Deploy → Redeploy) → artículo e imagen siguen ahí
   - [ ] `/healthz.php` devuelve `{"status":"ok"}`
   - [ ] Capturas de pantalla para el marketplace

## Fase 3 — Convertir en plantilla

1. En el proyecto: Settings → **Generate Template from Project**.
2. Revisar la topología capturada (servicios, variables con referencias `${{...}}` intactas, volúmenes, healthcheck).
3. Metadatos:
   - **Name**: `Drupal`
   - **Icon**: subir `assets/icon.svg` exportado a PNG 512×512 fondo transparente
   - **Category**: CMS / Websites & Blogs (la que ofrezca el composer)
4. Overview: pegar textos EN de la sección siguiente.

## Textos para el overview del marketplace (EN, listos para pegar)

### H1
**Deploy and Host Drupal with Railway**

Drupal is a leading open-source content management system powering millions of websites, from personal blogs to enterprise platforms. This template deploys Drupal 11 with a managed PostgreSQL database on Railway in one click — fully installed, configured and ready to build your site on.

### H2 — About Hosting Drupal

Hosting Drupal involves running its PHP application behind a web server, connecting it to a database, and persisting uploaded files across deployments. On Railway this template handles all of it automatically: the first boot waits for PostgreSQL, installs Drupal via Drush using generated admin credentials, mounts a volume for all uploads, and exposes a readiness endpoint so traffic only arrives once your site is truly usable. Updates are applied automatically on each redeploy.

### H2 — Common Use Cases

- Corporate websites and marketing sites with structured content
- Blogs, magazines and news portals with editorial workflows
- Intranets and member portals with role-based access control
- E-commerce storefronts built on Drupal Commerce
- Government, education and NGO sites requiring accessibility and multilingual content

### H2 — Dependencies for Drupal Hosting

- **Apache + PHP 8.4** — serves Drupal from the official pinned image (`drupal:11.4.5`)
- **PostgreSQL 17** — primary data store, private-networked, never exposed publicly
- **Drush 13** — Drupal's CLI, used by the boot script to install and update the site
- **Railway Volumes** — persistent storage for uploads and database files
- **Railway Healthchecks** — readiness gating via `/healthz.php`

### H3 — Deployment Dependencies

- [Drupal](https://www.drupal.org) (GPL-2.0+)
- [Official Drupal Docker image](https://hub.docker.com/_/drupal)
- [PostgreSQL Docker image](https://hub.docker.com/_/postgres)

### H3 — Implementation Details

The container entrypoint is idempotent: it waits for PostgreSQL, generates `settings.php` that reads every credential from environment variables at runtime, detects whether the database already contains an installation, and either runs `drush site:install` (first boot) or `drush updatedb && drush cache:rebuild` (subsequent boots). Admin password, hash salt and cron key are injected as template secrets — no default credentials anywhere.

```yaml
# Variable wiring example (set at template level)
PGHOST: ${{Postgres.PGHOST}}
PGPASSWORD: ${{Postgres.PGPASSWORD}}
DRUPAL_ADMIN_PASSWORD: ${{secret(24)}}
```

### H2 — Why Deploy Drupal on Railway?

[Railway boilerplate — ver docs de best practices]

## Fase 4 — Publicar y monetizar

1. Publish → copiar URL de la plantilla → probarla con "Deploy" desde otra ventana anónima.
2. Aplicar a [railway.com/partners](https://railway.com/partners) (proyecto open source → badge + placement).
3. Activarse en la **Template Queue** ([station.railway.com/my-template-queue](https://station.railway.com/my-template-queue)) para el kickback del 25 % respondiendo preguntas de usuarios.
4. Vigilar issues del repo GitHub relacionados con la plantilla.

## Recordatorio de reglas

- Versiones SIEMPRE fijadas por patch (ya hecho en Dockerfile).
- Nada expuesto fuera de HTTP/TCP; Postgres solo red privada (ya hecho).
- Si Railway cambia sintaxis de funciones `${{secret(...)}}` o del composer de plantillas, revisar [docs.railway.com/templates/best-practices](https://docs.railway.com/templates/best-practices) antes de publicar.
