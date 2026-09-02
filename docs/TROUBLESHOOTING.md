# Solución de problemas

## "Free-tier deploys to europe-west4-drams3a are not available during peak hours"
Railway bloquea los despliegues del plan gratuito en la región de Ámsterdam en horario pico (**8:00–20:00, hora de Ámsterdam**).
- Opción gratuita: espera a que termine la ventana y redespliega (los builds nocturnos funcionan sin problema).
- Opción instantánea: cambia la región del servicio (o la `preferredRegion` del workspace) fuera de esa ventana — vía dashboard (Settings → Region) o CLI.
- Nota: el gate aplica aunque el servicio esté en otra región, si el builder asignado vive en `drams3a`.

## "More than one MPM loaded" (AH00534) — Apache no arranca
`mod_php` exige MPM `prefork`. El Dockerfile ya normaliza esto (`a2dismod mpm_event/worker` + `a2enmod mpm_prefork`). Si lo ves tras tocar los módulos de Apache, revisa que no hayas habilitado un segundo MPM.

## "[preflight] Globally installed Drush is no longer supported"
Drush 13 debe vivir dentro del proyecto Drupal. Esta imagen lo instala con `composer require --working-dir=/opt/drupal drush/drush` — no muevas el binario fuera de `/opt/drupal/vendor`.

## El docroot fue "aplanado" y ahora Drush falla con rutas `../../web/...`
No aplastes el layout Composer de la imagen oficial: las rutas relativas del autoloader apuntan a `<proyecto>/web/core`. Respeta `/opt/drupal/{composer.json,vendor/,web/}` y monta el volumen en `/opt/drupal/web/sites/default`.

## El despliegue falla el healthcheck en la primera instalación
- La instalación corre dentro del timeout de healthcheck (**300 s**). En instancias muy lentas puede quedarse corto.
- Síntoma: logs de Drupal muestran `Installing Drupal` y al final el deploy se marca unhealthy.
- Solución: sube el timeout (Variables → `RAILWAY_HEALTHCHECK_TIMEOUT_SEC=600`) y redespliega. Solo afecta al primer arranque; los siguientes son rápidos.
- Si la instalación quedó a medias por un corte, borra las tablas de la base (o borra el volumen de Postgres) y redespliega para empezar limpia.

## "The provided host name is not valid for this server"
Estás accediendo por un dominio que no está en `trusted_host_patterns`.
- Con dominios `*.up.railway.app` no debería pasar (viene cubierto).
- Dominio propio: añade a la variable `TRUSTED_HOSTS` del servicio Drupal:
  ```
  ^www\.midominio\.com$
  ```
  (varios patrones separados por coma) y redespliega.

## Error de conexión a la base de datos / "Connection refused"
1. ¿El servicio **Postgres** está en verde? Revisa sus logs.
2. ¿Borraste y recreaste Postgres? Las referencias `${{Postgres.*}}` siguen siendo válidas tras recreate; si cambiaste el nombre del servicio, actualiza las variables del servicio Drupal.
3. Contraseña rotada: se aplica al reiniciar Drupal (el settings lee env en runtime) — solo redespliega.

## Recuperar la contraseña del admin
Abre un shell en el despliegue (Railway → servicio Drupal → ⋯ → *Shell*):

```bash
drush upwd admin 'NuevaContraseñaSegura!'
```

## Página en blanco o errores 500
Pon temporalmente `DRUPAL_ERROR_LEVEL=verbose` en Variables y redespliega: Drupal mostrará el error real. Vuelve a `hide` después.

## "Drupal already installed" al redesplegar
No debería ocurrir: el entrypoint comprueba la fila `uid=1` de `users_field_data` por PDO antes de instalar. Si lo ves, alguien borró `settings.php` del volumen pero la BD sigue llena — restaura settings.php desde el template (`cp /usr/local/share/drupal-railway/settings.template.php sites/default/settings.php`) o vacía la BD.

## Subidas grandes fallan
Límite actual: 64 MB (`upload_max_filesize`/`post_max_size` en `docker/zz-railway.ini`). Para más, edita el ini y redespliega (rebuild). También vigila la RAM asignada.

## Permisos raros en files/
Si entraste por Shell como root y tocaste archivos, arregla con:

```bash
chown -R www-data:www-data sites/default
```

(el entrypoint ya lo hace en cada arranque).

## Copias de seguridad
- **Base de datos**: Railway hace snapshots del volumen, pero para exportar lógico usa Shell:
  ```bash
  drush sql-dump --gzip --result-file=/tmp/backup.sql.gz
  ```
  y descárgalo (o súbelo a S3).
- **Archivos**: están en el volumen `sites/default`; usa snapshots del volumen de Railway.

## Actualizar Drupal a una versión nueva
1. Edita el pin en el `Dockerfile` (ej. `drupal:11.5.x-php8.4-apache-bookworm`).
2. Commit + push → Railway reconstruye.
3. El entrypoint ejecuta `drush updatedb` automáticamente en ese arranque.

## Ver la URL de cron
Aparece en los logs de arranque (`Cron URL: ...`). También puedes reconstruirla: `https://<tu-dominio>/cron/<DRUPAL_CRON_KEY>`. La clave está en la variable `DRUPAL_CRON_KEY`.
