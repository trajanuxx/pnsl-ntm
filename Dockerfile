# ==============================================================================
# ESTÁGIO 1: Composer (Back-end)
# ==============================================================================
FROM php:8.2-fpm-alpine AS composer_builder
WORKDIR /var/www/html
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer
COPY composer.json composer.lock ./
# Instala libs necessárias para o composer
RUN apk add --no-cache libzip-dev libpng-dev
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-scripts

# ==============================================================================
# ESTÁGIO 2: Node.js (Front-end)
# ==============================================================================
FROM node:20-alpine AS node_builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install 
COPY . .
# Copia a pasta vendor para que o Vite encontre o CSS do Flux
COPY --from=composer_builder /var/www/html/vendor ./vendor
RUN npm run build

# ==============================================================================
# ESTÁGIO 3: Imagem Final de Produção
# ==============================================================================
FROM php:8.2-fpm-alpine

ENV TZ=America/Sao_Paulo

# 1. Instala Nginx, Supervisor e Dependências de Runtime
RUN apk add --no-cache \
    nginx \
    supervisor \
    libzip \
    libpng \
    libjpeg-turbo \
    mysql-client \
    tzdata \
    icu-libs \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

# 2. Instala Dependências de COMPILAÇÃO (Temporárias)
# Adicionamos libzip-dev, libpng-dev, etc para o docker-php-ext-install funcionar
RUN apk add --no-cache --virtual .build-deps \
    libzip-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    zlib-dev \
    && docker-php-ext-configure gd --with-jpeg \
    && docker-php-ext-install pdo pdo_mysql bcmath opcache zip gd \
    && apk del .build-deps

# 3. Usuário Laravel
RUN addgroup -g 1000 laravel && adduser -D -u 1000 -G laravel laravel

# 4. Configura Workdir
WORKDIR /var/www/html

# 5. Copia App
COPY . .

# 6. Copia Vendor e Assets (dos estágios anteriores)
COPY --from=composer_builder /var/www/html/vendor ./vendor
COPY --from=node_builder /app/public/build ./public/build

# 7. Permissões
RUN mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache \
    && chown -R laravel:laravel storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

# Logs Nginx e Configs
RUN mkdir -p /run/nginx /var/log/nginx
COPY docker/nginx.conf /etc/nginx/http.d/default.conf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/php/php.ini /usr/local/etc/php/conf.d/custom.ini

# Ajuste PHP-FPM
RUN sed -i 's/user = www-data/user = laravel/g' /usr/local/etc/php-fpm.d/www.conf \
    && sed -i 's/group = www-data/group = laravel/g' /usr/local/etc/php-fpm.d/www.conf

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
