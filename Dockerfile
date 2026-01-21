# ==============================================================================
# ESTÁGIO 1: Composer (Back-end)
# ==============================================================================
FROM php:8.2-fpm-alpine AS composer_builder
WORKDIR /var/www/html
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer
COPY composer.json composer.lock ./
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
# Copia o vendor para o build do CSS funcionar
COPY --from=composer_builder /var/www/html/vendor ./vendor
RUN npm run build

# ==============================================================================
# ESTÁGIO 3: Imagem Final de Produção
# ==============================================================================
FROM php:8.2-fpm-alpine

ENV TZ=America/Sao_Paulo

# 1. Instalação de Pacotes
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

# 2. Instala e Compila Extensões PHP
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

# 4. Workdir
WORKDIR /var/www/html

# 5. Copia Arquivos
COPY . .
COPY --from=composer_builder /var/www/html/vendor ./vendor
COPY --from=node_builder /app/public/build ./public/build

# 6. Configurações
RUN mkdir -p /run/nginx /var/log/nginx
COPY docker/nginx.conf /etc/nginx/http.d/default.conf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/php/php.ini /usr/local/etc/php/conf.d/custom.ini

# 7. Ajuste PHP-FPM
RUN sed -i 's/user = www-data/user = laravel/g' /usr/local/etc/php-fpm.d/www.conf \
    && sed -i 's/group = www-data/group = laravel/g' /usr/local/etc/php-fpm.d/www.conf

# 8. CRIAÇÃO DO SCRIPT DE INICIALIZAÇÃO (A Mágica acontece aqui)
# Criamos um arquivo start.sh direto no build para garantir a ordem de execução
RUN printf "#!/bin/sh\n\
echo '🚀 Iniciando Container...'\n\
\n\
# 1. Força permissão total (Resolve conflito Root vs Laravel)\n\
chmod -R 777 /var/www/html/storage /var/www/html/bootstrap/cache\n\
\n\
# 2. LIMPA qualquer cache antigo que possa estar corrompido ou com root\n\
php artisan optimize:clear\n\
\n\
# 3. Não rodamos config:cache aqui de propósito, para ler o .env injetado\n\
\n\
# 4. Inicia o Supervisor\n\
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf\n" > /usr/local/bin/start.sh && chmod +x /usr/local/bin/start.sh

EXPOSE 80

# 9. Define o script como comando inicial
CMD ["/usr/local/bin/start.sh"]
