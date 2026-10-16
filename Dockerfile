###############################################################################
# Stage 1 — Build: composer-install & artisan setup on the fat base image
###############################################################################
FROM dreamfactorysoftware/df-base-img:v7 AS builder

ARG BRANCH=master

# Clone DreamFactory source
RUN git clone --depth 1 --branch $BRANCH \
    https://github.com/dreamfactorysoftware/dreamfactory.git /opt/dreamfactory && \
    rm -rf /opt/dreamfactory/.git

WORKDIR /opt/dreamfactory

# Overlay our Mini composer.json and install deps
COPY composer.json /opt/dreamfactory/
RUN rm -f composer.lock && \
    sed -i '/MongoDB.*MongoDBServiceProvider/d' config/app.php && \
    sed -i '/Add MongoDB Provider/d' config/app.php && \
    rm -f bootstrap/cache/packages.php bootstrap/cache/services.php && \
    git config --global url."https://github.com/".insteadOf "git@github.com:" && \
    COMPOSER_MEMORY_LIMIT=-1 composer update --no-dev --ignore-platform-reqs --no-scripts && \
    # Strip MongoDB from df-core
    sed -i '/use MongoDB/d' vendor/dreamfactory/df-core/src/LaravelServiceProvider.php && \
    sed -i '/MongoDBServiceProvider/d' vendor/dreamfactory/df-core/src/LaravelServiceProvider.php && \
    # Run artisan setup
    php artisan package:discover --ansi && \
    php artisan df:env --db_connection=sqlite --df_install=Docker || true && \
    [ -f .env ] || cp .env-dist .env && \
    mkdir -p storage/app storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs bootstrap/cache && \
    # Clean up build artifacts
    rm -rf /root/.composer /root/.cache /tmp/* /var/tmp/* && \
    find vendor -type d \( -name "tests" -o -name "test" -o -name "Tests" -o -name "docs" -o -name ".git" \) -exec rm -rf {} + 2>/dev/null || true

# Copy PECL .so files we need (sqlsrv, pdo_sqlsrv) — built in the fat image
RUN PHP_EXT_DIR=$(php -r 'echo PHP_EXTENSION_DIR;') && \
    mkdir -p /tmp/php-exts && \
    cp "$PHP_EXT_DIR/pdo_sqlsrv.so" /tmp/php-exts/ && \
    cp "$PHP_EXT_DIR/sqlsrv.so" /tmp/php-exts/

###############################################################################
# Stage 2 — Runtime: slim Ubuntu + only the PHP extensions we need
###############################################################################
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install all runtime deps in a single layer
RUN apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common gnupg curl ca-certificates && \
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php && \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/ubuntu/24.04/prod noble main" > /etc/apt/sources.list.d/mssql-release.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        nginx \
        php8.3-fpm \
        php8.3-bcmath \
        php8.3-curl \
        php8.3-mbstring \
        php8.3-mysql \
        php8.3-pgsql \
        php8.3-soap \
        php8.3-sqlite3 \
        php8.3-xml \
        php8.3-zip \
        php8.3-sybase \
        php8.3-opcache \
        sqlite3 \
        unixodbc libodbc2 libltdl7 && \
    ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 && \
    # Strip build-only packages
    apt-get purge -y software-properties-common gnupg python3-launchpadlib && \
    apt-get autoremove -y --purge && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
           /usr/share/doc /usr/share/man /usr/share/info /usr/share/lintian \
           /usr/share/bug /var/log/*.log /var/cache/debconf/*

# Copy PECL extensions and enable them
COPY --from=builder /tmp/php-exts/*.so /usr/lib/php/20230831/
# Note: runtime PHP ext dir is known to be 20230831 for PHP 8.3 on ubuntu:24.04
RUN echo "extension=sqlsrv.so" > /etc/php/8.3/mods-available/sqlsrv.ini && \
    echo "extension=pdo_sqlsrv.so" > /etc/php/8.3/mods-available/pdo_sqlsrv.ini && \
    ln -s /etc/php/8.3/mods-available/sqlsrv.ini /etc/php/8.3/fpm/conf.d/20-sqlsrv.ini && \
    ln -s /etc/php/8.3/mods-available/pdo_sqlsrv.ini /etc/php/8.3/fpm/conf.d/20-pdo_sqlsrv.ini && \
    ln -s /etc/php/8.3/mods-available/sqlsrv.ini /etc/php/8.3/cli/conf.d/20-sqlsrv.ini && \
    ln -s /etc/php/8.3/mods-available/pdo_sqlsrv.ini /etc/php/8.3/cli/conf.d/20-pdo_sqlsrv.ini

# Copy the built DreamFactory app
COPY --from=builder --chown=www-data:www-data /opt/dreamfactory /opt/dreamfactory

# Copy ODBC config
COPY --from=builder /etc/odbcinst.ini /etc/odbcinst.ini

# Configure Nginx
COPY dreamfactory.conf /etc/nginx/sites-available/dreamfactory.conf
RUN rm -f /etc/nginx/sites-enabled/default && \
    ln -sf /dev/stderr /var/log/nginx/error.log

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

WORKDIR /opt/dreamfactory

EXPOSE 80

CMD ["/docker-entrypoint.sh"]
