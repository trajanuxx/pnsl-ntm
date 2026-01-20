# ==============================================================================
# ESTÁGIO 1: Composer (Back-end) - AGORA VEM PRIMEIRO
# ==============================================================================
FROM php:8.2-fpm-alpine AS composer_builder
WORKDIR /var/www/html
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer
COPY composer.json composer.lock ./
# Instala libs do sistema necessárias para o composer (zip, png, etc)
RUN apk add --no-cache libzip-dev libpng-dev
# Instala dependências do PHP
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-scripts

# ==============================================================================
# ESTÁGIO 2: Node.js (Front-end)
# ==============================================================================
FROM node:20-alpine AS node_builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install 
COPY . .

# 🔥 O PULO DO GATO: Copia a pasta 'vendor' do estágio 1 para cá
# Isso permite que o Vite encontre o CSS do Livewire Flux
COPY --from=composer_builder /var/www/html/vendor ./vendor

# Agora sim, o build vai funcionar
RUN npm run build

# ==============================================================================
# ESTÁGIO 3: Imagem Final de Produção
# ==============================================================================
FROM php:8.2-fpm-alpine

ENV TZ=America/Sao_Paulo

# 1. Instala Nginx, Supervisor e Dependências
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

# 2. Extensões PHP
RUN docker-php-ext-install pdo pdo_mysql bcmath opcache zip gd

# 3. Usuário Laravel
RUN addgroup -g 1000 laravel && adduser -D -u 1000 -G laravel laravel

# 4. Configura Workdir
WORKDIR /var/www/html

# 5. Copia App
COPY . .

# 6. Copia Vendor (do Estágio 1)
COPY --from=composer_builder /var/www/html/vendor ./vendor

# 7. Copia Assets Compilados (do Estágio 2)
COPY --from=node_builder /app/public/build ./public/build

# 8. Permissões
RUN mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache \
    && chown -R laravel:laravel storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

# Logs Nginx
RUN mkdir -p /run/nginx /var/log/nginx

# Configs (Arquivos devem existir no repo)
COPY docker/nginx.conf /etc/nginx/http.d/default.conf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/php/php.ini /usr/local/etc/php/conf.d/custom.ini

# Ajuste PHP-FPM
RUN sed -i 's/user = www-data/user = laravel/g' /usr/local/etc/php-fpm.d/www.conf \
    && sed -i 's/group = www-data/group = laravel/g' /usr/local/etc/php-fpm.d/www.conf

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
