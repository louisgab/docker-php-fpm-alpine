ARG ALPINE_VERSION=3.19
ARG PHP_VERSION=8.3
ARG COMPOSER_VERSION=2.7
ARG EXTENSION_INSTALLER_VERSION=2.2

FROM composer/composer:${COMPOSER_VERSION}-bin as composer
FROM mlocati/php-extension-installer:${EXTENSION_INSTALLER_VERSION} as extension-installer

# --------------------------------------------------------------------------------------- #

FROM php:${PHP_VERSION}-fpm-alpine${ALPINE_VERSION} as base

# Add alpine dependencies
RUN --mount=type=cache,target=/var/cache/apk \
    ln -s /var/cache/apk /etc/apk/cache \
    && apk update && apk add --no-cache  \
    icu \
    musl-locales \
    supervisor \
    tzdata;
 
# Configure PHP
ENV PHP_EXTENSIONS "bcmath intl opcache pcntl redis zip"
COPY --from=extension-installer /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions $PHP_EXTENSIONS \
    && php -m;

# Add composer
ENV COMPOSER_ALLOW_SUPERUSER 1
ENV COMPOSER_HOME /tmp
COPY --from=composer /composer /usr/bin/composer

# Add locales
ENV MUSL_LOCPATH /usr/share/i18n/locales/musl
RUN LC_ALL=fr_FR.UTF-8 date -d "1970-01-01" +%B | grep "Janvier";

# Set timezone
ENV TZ UTC
RUN cp /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && { echo "date.timezone = $TZ"; } | tee "$PHP_INI_DIR"/conf.d/zz-timezone.ini \
    && date +"%Z" | grep "$TZ";

# --------------------------------------------------------------------------------------- #

FROM base as dev

# Additional PHP extensions and config
ENV PHP_DEV_EXTENSIONS "pcov xdebug"
RUN install-php-extensions $PHP_DEV_EXTENSIONS
    && mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini";
    && php -m;
   
# Install composer dependencies
RUN --mount=type=bind,source=composer.json,target=composer.json \
    --mount=type=bind,source=composer.lock,target=composer.lock \
    --mount=type=cache,target=/root/.composer \
    composer install --no-autoloader --no-interaction --no-progress --no-scripts --prefer-dist
COPY . .
RUN composer dump-autoload --optimize --strict-psr

# --------------------------------------------------------------------------------------- #

FROM base as prod

# Additional PHP config
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini";
    
# Install composer production dependencies
RUN --mount=type=bind,source=composer.json,target=composer.json \
    --mount=type=bind,source=composer.lock,target=composer.lock \
    --mount=type=cache,target=/root/.composer \
    composer install --no-autoloader --no-dev --no-interaction --no-progress --no-scripts --prefer-dist
COPY . .
RUN composer dump-autoload --no-dev --optimize --strict-psr
