FROM php:8.3-fpm

RUN apt-get update && apt-get install -y \
    nginx \
    libicu-dev \
    libzip-dev \
    zip \
    unzip \
    curl \
    git \
    && docker-php-ext-configure intl \
    && docker-php-ext-install pdo pdo_mysql intl zip opcache \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

RUN { \
    echo 'opcache.enable=1'; \
    echo 'opcache.memory_consumption=256'; \
    echo 'opcache.max_accelerated_files=20000'; \
    echo 'opcache.validate_timestamps=0'; \
    echo 'opcache.revalidate_freq=0'; \
} > /usr/local/etc/php/conf.d/opcache.ini

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

ENV COMPOSER_ALLOW_SUPERUSER=1

WORKDIR /var/www/html

# Copy dependency files first — layer is cached until composer files change
COPY composer.json composer.lock symfony.lock importmap.php ./

# Download packages only, no autoloader/scripts yet
RUN composer install \
    --no-dev \
    --no-autoloader \
    --no-scripts \
    --no-interaction \
    --prefer-dist

# Copy full application
COPY . .

# Set build-time env vars so Symfony console commands work without a real DB
ENV APP_ENV=prod
ENV APP_SECRET=build-placeholder
ENV DATABASE_URL="mysql://placeholder:placeholder@placeholder:3306/placeholder?serverVersion=8.0.32&charset=utf8mb4"

# Generate optimized autoloader WITH scripts — this triggers the symfony/runtime
# plugin via post-autoload-dump, creating vendor/autoload_runtime.php,
# and runs assets:install, importmap:install, cache:clear via composer scripts
RUN composer install \
    --no-dev \
    --optimize-autoloader \
    --no-interaction \
    --prefer-dist

RUN chown -R www-data:www-data var \
    && chmod -R 775 var

COPY nginx-main.conf /etc/nginx/nginx.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
