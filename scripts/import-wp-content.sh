#!/bin/bash
set -e

# 1. Configuración (extraída de tu .env y docker-compose)
CONTAINER_NAME="wpdocker_wordpress_app"
BACKUP_FILE="$1"

if [ -z "$1" ]; then
    echo "Uso: ./scripts/import-wp-content.sh mi_archivo.tar.gz"
    exit 1
fi

echo "--- 1. Copiando archivo al contenedor ---"
docker cp "$BACKUP_FILE" "$CONTAINER_NAME":/tmp/backup.tar.gz

echo "--- 2. Limpiando y Descomprimiendo ---"
# Ejecutamos todo dentro del contenedor como root para evitar problemas de permisos
docker exec -u root "$CONTAINER_NAME" sh -c '
    # Entramos a la ruta de WordPress
    cd /var/www/html

    # Borramos el contenido de wp-content. 
    # NO borramos la carpeta themes (porque es un montaje de Docker), borramos su CONTENIDO.
    echo "Limpiando wp-content actual..."
    find wp-content -mindepth 1 -maxdepth 1 ! -name "themes" -exec rm -rf {} +
    rm -rf wp-content/themes/* 2>/dev/null || true

    # Descomprimimos en una carpeta temporal
    mkdir -p /tmp/restore
    tar -xzf /tmp/backup.tar.gz -C /tmp/restore

    # Identificamos si el tar trae la carpeta "wp-content" o los archivos sueltos
    if [ -d "/tmp/restore/wp-content" ]; then
        cp -a /tmp/restore/wp-content/. wp-content/
    else
        cp -a /tmp/restore/. wp-content/
    fi

    # Ajustamos permisos para que WordPress (www-data) pueda escribir
    chown -R www-data:www-data wp-content
    
    # Limpieza final
    rm /tmp/backup.tar.gz
    rm -rf /tmp/restore
    echo "¡Proceso terminado con éxito!"
'