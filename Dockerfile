# Stage 1: Builder (Igual ao seu)
FROM php:8.2-fpm-alpine AS builder
WORKDIR /var/www/html
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer
COPY composer.json composer.lock ./
RUN apk add --no-cache --virtual .build-deps \
    libzip-dev libpng-dev libjpeg-turbo-dev zlib-dev linux-headers \
    && docker-php-ext-configure gd --with-jpeg \
    && docker-php-ext-install -j$(nproc) pdo_mysql opcache bcmath zip gd sockets exif pcntl pdo
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-scripts
COPY . .
RUN composer dump-autoload --optimize

# Stage 2: Produção (Com Nginx + Supervisor)
FROM php:8.2-fpm-alpine

ENV TZ=America/Sao_Paulo

# 1. Instala Nginx e Supervisor
RUN apk add --no-cache \
    nginx \
    supervisor \
    libzip libpng libjpeg-turbo mysql-client tzdata \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

# 2. Copia extensões do Builder
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# 3. Configurações
WORKDIR /var/www/html
COPY --from=builder /var/www/html /var/www/html

# Cria usuário Laravel
RUN addgroup -g 1000 laravel && adduser -D -u 1000 -G laravel laravel

# Permissões
RUN mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache \
    && chown -R laravel:laravel storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

# 4. Configuração do Nginx (Cria diretórios necessários)
RUN mkdir -p /run/nginx /var/log/nginx

# 5. Copia arquivos de configuração (VOCÊ PRECISA CRIAR ESSES ARQUIVOS NO REPO)
COPY docker/nginx.conf /etc/nginx/http.d/default.conf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/php/php.ini /usr/local/etc/php/conf.d/custom.ini

# 6. Ajusta PHP-FPM para rodar como 'laravel' mas o processo pai será root (Supervisor)
RUN sed -i 's/user = www-data/user = laravel/g' /usr/local/etc/php-fpm.d/www.conf \
    && sed -i 's/group = www-data/group = laravel/g' /usr/local/etc/php-fpm.d/www.conf

EXPOSE 80

# O Supervisor inicia o Nginx e o PHP
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
