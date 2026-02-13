#!/bin/bash
# Script de prueba completa: valida todo el flujo desde cero
# Ejecutar antes de desplegar para asegurar que todo funciona

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

ERRORS=0

echo -e "${BLUE}=== PRUEBA COMPLETA DEL PROYECTO ===${NC}"
echo ""

# 1. Verificar que estamos en el proyecto
if [ ! -f "docker-compose.yml" ]; then
  echo -e "${RED}✗ Error: No se encuentra docker-compose.yml${NC}"
  exit 1
fi
echo -e "${GREEN}✓ docker-compose.yml encontrado${NC}"

# 2. Verificar Docker
if ! command -v docker >/dev/null 2>&1; then
  echo -e "${RED}✗ Error: Docker no está instalado${NC}"
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo -e "${RED}✗ Error: Docker no está corriendo${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Docker disponible${NC}"

# 3. Verificar .env
if [ ! -f ".env" ]; then
  echo -e "${YELLOW}⚠ .env no existe, creando desde .env.example${NC}"
  if [ -f ".env.example" ]; then
    cp .env.example .env
    echo -e "${YELLOW}Edita .env con tus valores antes de continuar${NC}"
    exit 1
  else
    echo -e "${RED}✗ Error: No existe .env ni .env.example${NC}"
    exit 1
  fi
fi
echo -e "${GREEN}✓ .env encontrado${NC}"

# 4. Limpiar archivos generados anteriores
echo -e "${BLUE}Limpiando archivos generados anteriores...${NC}"
rm -rf nginx/generated/*.conf php-config/generated/*.ini 2>/dev/null || true

# 5. Ejecutar init-generated-files.sh
echo -e "${BLUE}Ejecutando init-generated-files.sh...${NC}"
if ! bash scripts/init-generated-files.sh >/dev/null 2>&1; then
  echo -e "${RED}✗ Error al ejecutar init-generated-files.sh${NC}"
  ERRORS=$((ERRORS + 1))
else
  echo -e "${GREEN}✓ Archivos por defecto creados${NC}"
fi

# 6. Ejecutar setup.sh
echo -e "${BLUE}Ejecutando setup.sh...${NC}"
if ! bash scripts/setup.sh >/dev/null 2>&1; then
  echo -e "${RED}✗ Error al ejecutar setup.sh${NC}"
  ERRORS=$((ERRORS + 1))
else
  echo -e "${GREEN}✓ Configuración generada${NC}"
fi

# 7. Verificar archivos generados
echo -e "${BLUE}Verificando archivos generados...${NC}"
MISSING_FILES=0

if [ ! -f "nginx/generated/nginx.conf" ]; then
  echo -e "${RED}✗ nginx/generated/nginx.conf no existe${NC}"
  MISSING_FILES=$((MISSING_FILES + 1))
  ERRORS=$((ERRORS + 1))
else
  # Verificar que no tiene variables sin sustituir
  if grep -q '\${' nginx/generated/nginx.conf 2>/dev/null; then
    echo -e "${RED}✗ nginx.conf tiene variables sin sustituir${NC}"
    grep '\${' nginx/generated/nginx.conf | head -3
    ERRORS=$((ERRORS + 1))
  else
    echo -e "${GREEN}✓ nginx/generated/nginx.conf válido${NC}"
  fi
fi

if [ ! -f "nginx/generated/wordpress.conf" ]; then
  echo -e "${RED}✗ nginx/generated/wordpress.conf no existe${NC}"
  MISSING_FILES=$((MISSING_FILES + 1))
  ERRORS=$((ERRORS + 1))
else
  if grep -q '\${DOMAIN}' nginx/generated/wordpress.conf 2>/dev/null; then
    echo -e "${RED}✗ wordpress.conf tiene variables sin sustituir${NC}"
    grep '\${DOMAIN}' nginx/generated/wordpress.conf | head -3
    ERRORS=$((ERRORS + 1))
  else
    echo -e "${GREEN}✓ nginx/generated/wordpress.conf válido${NC}"
  fi
fi

if [ ! -f "php-config/generated/memory.ini" ]; then
  echo -e "${RED}✗ php-config/generated/memory.ini no existe${NC}"
  MISSING_FILES=$((MISSING_FILES + 1))
  ERRORS=$((ERRORS + 1))
else
  echo -e "${GREEN}✓ php-config/generated/memory.ini válido${NC}"
fi

# 8. Validar sintaxis de nginx (si es posible)
echo -e "${BLUE}Validando sintaxis de nginx.conf...${NC}"
if docker run --rm -v "$PROJECT_ROOT/nginx/generated/nginx.conf:/tmp/nginx.conf:ro" nginx:alpine sh -c "cat /tmp/nginx.conf > /etc/nginx/nginx.conf && nginx -t" >/dev/null 2>&1; then
  echo -e "${GREEN}✓ Sintaxis de nginx.conf válida${NC}"
else
  echo -e "${YELLOW}⚠ No se pudo validar sintaxis de nginx (puede requerir servicios corriendo)${NC}"
fi

# 9. Validar docker-compose config
echo -e "${BLUE}Validando docker-compose.yml...${NC}"
if docker compose config >/dev/null 2>&1; then
  echo -e "${GREEN}✓ docker-compose.yml válido${NC}"
else
  echo -e "${RED}✗ docker-compose.yml tiene errores${NC}"
  docker compose config 2>&1 | head -10
  ERRORS=$((ERRORS + 1))
fi

# 10. Verificar que los archivos tienen permisos correctos
echo -e "${BLUE}Verificando permisos...${NC}"
if [ -r "nginx/generated/nginx.conf" ] && [ -r "nginx/generated/wordpress.conf" ] && [ -r "php-config/generated/memory.ini" ]; then
  echo -e "${GREEN}✓ Permisos correctos${NC}"
else
  echo -e "${RED}✗ Problemas con permisos${NC}"
  ERRORS=$((ERRORS + 1))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}=== TODAS LAS PRUEBAS PASARON ===${NC}"
  echo ""
  echo "Puedes proceder con:"
  echo "  docker compose up -d"
  exit 0
else
  echo -e "${RED}=== FALLARON $ERRORS PRUEBAS ===${NC}"
  echo ""
  echo "Revisa los errores arriba antes de desplegar."
  exit 1
fi
