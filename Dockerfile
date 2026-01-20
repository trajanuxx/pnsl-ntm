# ==============================================================================
# ESTÁGIO 1: Construção do Front-end (Node.js)
# ==============================================================================
FROM node:20-alpine AS node_builder
WORKDIR /app
# Copia arquivos de dependência primeiro (cache eficiente)
COPY package.json package-lock.json ./
# Se não tiver package-lock.json, remove a linha acima e usa apenas package.json
# RUN npm ci --quiet  <-- Use 'ci' se tiver package-lock, senão use 'install'
RUN npm install 
COPY . .
# Gera os arquivos estáticos em /app/public/build
RUN npm run build

# ==============================================================================
# ESTÁGIO 2: Construção do Back-end (Composer)
# ==============================================================================
FROM php:8.2-fpm-alpine AS composer_builder
WORKDIR /var/www/html
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer
COPY composer.json composer.lock ./
# Instala libs do sistema necessárias para o composer instalar deps
RUN apk add --no-cache libzip-dev libpng-dev
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-scripts

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

# 2. Instala extensões PHP necessárias
RUN docker-php-ext-install pdo pdo_mysql bcmath opcache zip gd

# 3. Cria usuário Laravel
RUN addgroup -g 1000 laravel && adduser -D -u 1000 -G laravel laravel

# 4. Configura Workdir
WORKDIR /var/www/html

# 5. COPIA OS ARQUIVOS DA APLICAÇÃO
COPY . .

# 6. COPIA DEPENDÊNCIAS DO COMPOSER (Do estágio 2)
COPY --from=composer_builder /var/www/html/vendor ./vendor

# 7. COPIA ASSETS COMPILADOS DO NODE (Do estágio 1) - O PULO DO GATO 🐈
COPY --from=node_builder /app/public/build ./public/build

# 8. Permissões e Configurações Finais
RUN mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache \
    && chown -R laravel:laravel storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

# Cria diretórios de log do Nginx
RUN mkdir -p /run/nginx /var/log/nginx

# Copia configurações (Certifique-se que estes arquivos existem no seu repo!)
COPY docker/nginx.conf /etc/nginx/http.d/default.conf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/php/php.ini /usr/local/etc/php/conf.d/custom.ini

# Ajusta usuário do PHP-FPM
RUN sed -i 's/user = www-data/user = laravel/g' /usr/local/etc/php-fpm.d/www.conf \
    && sed -i 's/group = www-data/group = laravel/g' /usr/local/etc/php-fpm.d/www.conf

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
