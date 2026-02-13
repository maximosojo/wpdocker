#!/bin/bash
# Script de inicialización: asegura que los archivos generados existan
# Se puede ejecutar manualmente o llamar desde setup.sh
# Si los archivos no existen, los copia desde los defaults

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

mkdir -p nginx/generated php-config/generated
chmod 755 nginx/generated php-config/generated 2>/dev/null || true

# Copiar archivos por defecto si no existen
if [ ! -f "nginx/generated/nginx.conf" ] && [ -f "nginx/generated/nginx.conf.default" ]; then
  cp nginx/generated/nginx.conf.default nginx/generated/nginx.conf
  echo "Copiado nginx/generated/nginx.conf desde default"
fi

if [ ! -f "nginx/generated/wordpress.conf" ] && [ -f "nginx/generated/wordpress.conf.default" ]; then
  cp nginx/generated/wordpress.conf.default nginx/generated/wordpress.conf
  echo "Copiado nginx/generated/wordpress.conf desde default"
fi

if [ ! -f "php-config/generated/memory.ini" ] && [ -f "php-config/generated/memory.ini.default" ]; then
  cp php-config/generated/memory.ini.default php-config/generated/memory.ini
  echo "Copiado php-config/generated/memory.ini desde default"
fi

# Asegurar permisos correctos
chmod 644 nginx/generated/*.conf php-config/generated/*.ini 2>/dev/null || true
