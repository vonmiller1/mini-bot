#!/bin/bash
set -e

echo "============================================"
echo "  DreamFactory Mini"
echo "  Instant REST APIs from your database"
echo "============================================"

# Create .env from template if missing
if [ ! -f .env ]; then
  cp .env-dist .env 2>/dev/null || php artisan df:env --db_connection=sqlite --df_install=Docker
fi

# Configure NGINX
ln -sf /etc/nginx/sites-available/dreamfactory.conf /etc/nginx/sites-enabled/dreamfactory.conf

# Tune PHP-FPM for mini usage (override file, not fragile sed)
cat > /etc/php/8.3/fpm/pool.d/zz-mini.conf <<'FPMCONF'
[www]
pm = ondemand
pm.max_children = 20
pm.process_idle_timeout = 10s
FPMCONF

# Update site configuration
sed -i "s;%SERVERNAME%;${SERVERNAME:=localhost};g" /etc/nginx/sites-available/dreamfactory.conf
sed -i "s;%HTTPS_HEADER%;${HTTPS_HEADER:=off};g" /etc/nginx/sites-available/dreamfactory.conf

# DF Mini uses SQLite system DB and file cache
sed -i 's/DF_INSTALL=.*/DF_INSTALL=Docker/' .env
sed -i "s/CACHE_DRIVER=.*/CACHE_DRIVER=file/" .env

# Set or generate APP_KEY
if [ -n "$APP_KEY" ]; then
  sed -i "s#APP_KEY=.*#APP_KEY=$APP_KEY#" .env
elif ! grep -q 'APP_KEY=base64:' .env; then
  php artisan key:generate
fi

# Set log level (handles both commented and uncommented forms)
if [ -n "$APP_LOG_LEVEL" ]; then
  sed -i "s/^#\?APP_LOG_LEVEL=.*/APP_LOG_LEVEL=$APP_LOG_LEVEL/" .env
fi

# Clear cached config from build stage
rm -f bootstrap/cache/packages.php bootstrap/cache/services.php

# Create admin user and run migrations
if [ -n "$ADMIN_EMAIL" ] && [ -n "$ADMIN_PASSWORD" ]; then
  echo "Setting up database and creating admin user..."
  php artisan df:setup \
    --admin_email "${ADMIN_EMAIL}" \
    --admin_password "${ADMIN_PASSWORD}" \
    --admin_first_name "${ADMIN_FIRST_NAME:-Admin}" \
    --admin_last_name "${ADMIN_LAST_NAME:-User}" \
    --admin_phone "${ADMIN_PHONE:-5555555555}" 2>&1 | grep -v "password" || true

  # Ensure admin password is correctly set (df:setup doesn't always hash reliably)
  # The User model's password mutator handles hashing via bcrypt
  php artisan tinker --execute='$u = \DreamFactory\Core\Models\User::where("email", env("ADMIN_EMAIL"))->first(); if($u){ $u->password = env("ADMIN_PASSWORD"); $u->save(); echo "Admin ready."; }'
fi

# Remove service types not included in Mini
php artisan tinker --execute='
$remove = ["alloydb","cache_local","cache_memcached","cache_redis","ftp_file","local_file","sftp_file","webdav_file"];
$count = \DB::table("service_type")->whereIn("name", $remove)->delete();
echo "Cleaned $count unused service types.";
' 2>/dev/null || true

# Seed default CORS config if table is empty
php artisan tinker --execute='if(\Schema::hasTable("cors_config") && \DB::table("cors_config")->count() === 0){ \DB::table("cors_config")->insert(["path"=>"*","origin"=>env("CORS_ORIGIN","*"),"header"=>"*","method"=>"*","max_age"=>0,"supports_credentials"=>false,"enabled"=>true]); echo "CORS config seeded."; }'

# Set permissions
chown -R www-data:www-data storage/ bootstrap/cache/

# Stream logs to stdout if requested
# Note: tail --pid $$ works because exec replaces this shell with nginx below
if [ "$LOG_TO_STDOUT" = "true" ]; then
  tail --pid $$ -F /opt/dreamfactory/storage/logs/dreamfactory.log 2>/dev/null &
fi

echo ""
echo "============================================"
echo "  DF Mini is ready!"
echo "  API:     http://localhost/api/v2"
echo "  Swagger: http://localhost/api/v2/api_docs"
echo "============================================"
echo ""

# Start PHP-FPM and Nginx
/usr/sbin/php-fpm8.3 --nodaemonize --fpm-config /etc/php/8.3/fpm/php-fpm.conf &
exec /usr/sbin/nginx -g "daemon off;"
