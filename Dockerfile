ARG ALPINE_VERSION=3.17
ARG PHP_VERSION=8.2
ARG COMPOSER_VERSION=2.5
ARG EXTENSION_INSTALLER_VERSION=2.1

FROM composer/composer:${COMPOSER_VERSION}-bin as composer
FROM mlocati/php-extension-installer:${EXTENSION_INSTALLER_VERSION} as extension-installer

# --------------------------------------------------------------------------------------- #

FROM php:${PHP_VERSION}-fpm-alpine${ALPINE_VERSION} as base

# Add alpine dependencies
RUN apk add --no-cache \
    icu \
    musl-locales \
    tzdata;
 
# Configure PHP
ENV PHP_EXTENSIONS "bcmath intl opcache pcntl redis zip"
COPY --from=extension-installer /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions $PHP_EXTENSIONS;

# Add composer
ENV COMPOSER_ALLOW_SUPERUSER 1
ENV COMPOSER_HOME /tmp
COPY --from=composer /composer /usr/bin/composer

# Add locales
ENV MUSL_LOCPATH /usr/share/i18n/locales/musl

# Set timezone
ENV TZ UTC
RUN cp /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && { echo "date.timezone = $TZ"; } | tee "$PHP_INI_DIR"/conf.d/zz-timezone.ini;

# --------------------------------------------------------------------------------------- #

FROM base as dev

# Additional PHP extensions and config
ENV PHP_DEV_EXTENSIONS "pcov xdebug"
RUN install-php-extensions $PHP_DEV_EXTENSIONS
    && mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini";
   
# Install composer dependencies
COPY composer.json composer.lock ./
RUN composer install --no-autoloader --no-interaction --no-progress --no-scripts --prefer-dist
COPY . .
RUN composer dump-autoload --optimize

# --------------------------------------------------------------------------------------- #

FROM base as prod

# Additional PHP config
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini";
    
# Install composer production dependencies
COPY composer.json composer.lock ./
RUN composer install --no-autoloader --no-dev --no-interaction --no-progress --no-scripts --prefer-dist
COPY . .
RUN composer dump-autoload --no-dev --optimize
