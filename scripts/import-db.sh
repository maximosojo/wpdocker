#!/bin/bash
set -e

# 1. Cargar variables del .env
if [ -f ".env" ]; then source .env; else echo "Error: .env no encontrado"; exit 1; fi

# Configuración
DB_CONTAINER="${COMPOSE_PROJECT_NAME:-wpdocker}_wordpress_mysql"
APP_CONTAINER="${COMPOSE_PROJECT_NAME:-wpdocker}_wordpress_app"
SQL_FILE="$1"
OLD_URL="$2"

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Uso: ./scripts/import-db.sh <archivo.sql> <url_antigua>"
    echo "Ejemplo: ./scripts/import-db.sh backup.sql http://3.131.201.65"
    exit 1
fi

# Detectar si usamos puerto o HTTPS estándar
if [ "$HTTP_PORT" == "80" ]; then
    NEW_URL="https://${DOMAIN}"
else
    # Si el puerto no es 80, usamos HTTP con el puerto específico
    NEW_URL="http://${DOMAIN}:${HTTP_PORT}"
fi

echo "--- 1. Importando SQL a MySQL ---"
docker exec -i "$DB_CONTAINER" mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < "$SQL_FILE"

echo "--- 2. Instalando WP-CLI temporalmente en el contenedor ---"
# Lo bajamos directamente al contenedor para que use la conexión interna perfecta
docker exec -u root "$APP_CONTAINER" sh -c '
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp
'

echo "--- 3. Reemplazando dominio ($OLD_URL -> $NEW_URL) ---"
# Ejecutamos el reemplazo. WP-CLI detecta automáticamente los datos serializados.
docker exec -u www-data "$APP_CONTAINER" wp search-replace "$OLD_URL" "$NEW_URL" --allow-root --skip-columns=guid

echo "--- 4. Actualizando opciones básicas (SiteURL y Home) ---"
docker exec -u www-data "$APP_CONTAINER" wp option update siteurl "$NEW_URL" --allow-root
docker exec -u www-data "$APP_CONTAINER" wp option update home "$NEW_URL" --allow-root

echo "--- 5. Limpieza ---"
# Opcional: puedes dejar wp instalado o borrarlo. Aquí lo borramos para dejarlo limpio.
docker exec -u root "$APP_CONTAINER" rm /usr/local/bin/wp

echo "✅ ¡Base de datos actualizada! El sitio ahora responde en $NEW_URL"