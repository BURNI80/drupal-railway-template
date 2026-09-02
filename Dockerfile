# Drupal on Railway — production image
# Upstream: official Drupal image (Debian bookworm, Apache + PHP 8.4)
# Pinned to an exact patch version per Railway template best practices.
#
# LAYOUT NOTE: the official image keeps the app in composer layout at
# /opt/drupal ({composer.json, vendor/, web/}) and exposes /var/www/html as a
# symlink to /opt/drupal/web. We embrace the native layout instead of fighting
# it: Drush is installed inside the project (as upstream documents), Apache's
# DocumentRoot points at /opt/drupal/web, and the persistent volume moves to
# /opt/drupal/web/sites/default. No flattening, no autoloader surgery.
FROM drupal:11.4.5-php8.4-apache-bookworm

ENV COMPOSER_HOME=/opt/composer \
    DRUPAL_PROJECT=/opt/drupal \
    DRUPAL_ROOT=/opt/drupal/web \
    SITE_DIR=/opt/drupal/web/sites/default

# Apache must load exactly ONE MPM (prefork — required by the thread-unsafe
# mod_php). The base image ships mpm_event AND mpm_prefork enabled, causing
# AH00534. Disable all, then enable only prefork — forcefully remove load
# files to survive any layer re-enabling them.
RUN set -eux; \
    a2dismod -f mpm_event mpm_worker 2>/dev/null || true; \
    rm -f /etc/apache2/mods-enabled/mpm_event.load /etc/apache2/mods-enabled/mpm_event.conf \
          /etc/apache2/mods-enabled/mpm_worker.load /etc/apache2/mods-enabled/mpm_worker.conf; \
    a2enmod mpm_prefork

# Drush, installed inside the Drupal project exactly as upstream recommends,
# pinned for reproducible builds.
RUN set -eux; \
    composer require --working-dir="$DRUPAL_PROJECT" --no-interaction --no-progress \
      drush/drush:13.7.6; \
    ln -sf "$DRUPAL_PROJECT/vendor/bin/drush" /usr/local/bin/drush

# Serve the real composer docroot: replace Debian's default vhost with one
# whose DocumentRoot is /opt/drupal/web.
COPY docker/railway-site.conf /etc/apache2/sites-available/railway.conf
RUN a2dissite 000-default && a2ensite railway && a2enmod rewrite

# PHP runtime tuning for Drupal (uploads, memory, opcache).
COPY docker/zz-railway.ini /usr/local/etc/php/conf.d/zz-railway.ini

# Trust Railway's edge proxy (RFC1918 + CGNAT ranges) so Drupal/logs see real client IPs.
COPY docker/remoteip.conf /etc/apache2/conf-available/zz-railway-remoteip.conf
RUN a2enmod remoteip && a2enconf zz-railway-remoteip

# Lightweight readiness endpoint used by the Railway healthcheck.
COPY docker/healthz.php $DRUPAL_ROOT/healthz.php

# Settings template: copied into sites/default by the entrypoint.
COPY docker/settings.template.php /usr/local/share/drupal-railway/settings.template.php

# Boot script: wait for DB, write settings.php, install or update Drupal, then start Apache.
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint-railway
RUN chmod +x /usr/local/bin/docker-entrypoint-railway

EXPOSE 80

# Chain through the base image entrypoint (keeps upstream init behavior intact),
# then run our script which finally execs apache2-foreground.
ENTRYPOINT ["docker-php-entrypoint", "docker-entrypoint-railway"]
CMD ["apache2-foreground"]
