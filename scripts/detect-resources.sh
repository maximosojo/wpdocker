#!/bin/bash
# Detecta recursos del sistema (CPU y RAM) y calcula límites dinámicos para Docker.
# Se ejecuta desde setup.sh o manualmente para generar valores recomendados en .env.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Detectar CPU (cores lógicos)
if command -v nproc >/dev/null 2>&1; then
  CPU_CORES=$(nproc)
elif [ -f /proc/cpuinfo ]; then
  CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
elif [[ "$OSTYPE" == "darwin"* ]]; then
  CPU_CORES=$(sysctl -n hw.ncpu)
else
  CPU_CORES=2  # Fallback conservador
fi

# Detectar RAM total (en MB)
if [ -f /proc/meminfo ]; then
  RAM_MB=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
elif [[ "$OSTYPE" == "darwin"* ]]; then
  RAM_MB=$(($(sysctl -n hw.memsize) / 1024 / 1024))
else
  RAM_MB=1024  # Fallback conservador
fi

# Perfil "mínimo" para servidores con <1GB RAM: MySQL 8 necesita ~320M para arrancar estable
# y WordPress/PHP necesitan margen o darán 502 (OOM). Se usan mínimos fijos y se avisa de swap.
MIN_RAM_SERVER_MB=1000
MYSQL_MIN_MB=320
WP_MIN_MB=256
NGINX_MIN_MB=64

if [ "$RAM_MB" -lt "$MIN_RAM_SERVER_MB" ]; then
  # Servidor muy justo (<1GB): mínimos fijos para evitar 502 y MySQL unhealthy
  AVAILABLE_RAM=$((RAM_MB * 70 / 100))
  MYSQL_LIMIT_MB=$MYSQL_MIN_MB
  WP_LIMIT_MB=$WP_MIN_MB
  NGINX_LIMIT_MB=$NGINX_MIN_MB
  MYSQL_RESERVE_MB=$((MYSQL_MIN_MB * 40 / 100))
  WP_RESERVE_MB=$((WP_MIN_MB * 40 / 100))
  NGINX_RESERVE_MB=$((NGINX_MIN_MB * 50 / 100))
elif [ "$RAM_MB" -lt 2048 ]; then
  # Servidor pequeño (1–2GB): dejar 40% libre, pero MySQL no bajar de 320M
  AVAILABLE_RAM=$((RAM_MB * 60 / 100))
  MYSQL_LIMIT_MB=$((AVAILABLE_RAM * 40 / 100))
  [ "$MYSQL_LIMIT_MB" -lt "$MYSQL_MIN_MB" ] && MYSQL_LIMIT_MB=$MYSQL_MIN_MB
  WP_LIMIT_MB=$((AVAILABLE_RAM * 35 / 100))
  [ "$WP_LIMIT_MB" -lt "$WP_MIN_MB" ] && WP_LIMIT_MB=$WP_MIN_MB
  NGINX_LIMIT_MB=$((AVAILABLE_RAM * 15 / 100))
  [ "$NGINX_LIMIT_MB" -lt "$NGINX_MIN_MB" ] && NGINX_LIMIT_MB=$NGINX_MIN_MB
  MYSQL_RESERVE_MB=$((MYSQL_LIMIT_MB * 50 / 100))
  WP_RESERVE_MB=$((WP_LIMIT_MB * 50 / 100))
  NGINX_RESERVE_MB=$((NGINX_LIMIT_MB * 50 / 100))
else
  # Servidor normal: dejar 30% libre
  AVAILABLE_RAM=$((RAM_MB * 70 / 100))
  MYSQL_LIMIT_MB=$((AVAILABLE_RAM * 45 / 100))
  WP_LIMIT_MB=$((AVAILABLE_RAM * 40 / 100))
  NGINX_LIMIT_MB=$((AVAILABLE_RAM * 15 / 100))
  MYSQL_RESERVE_MB=$((MYSQL_LIMIT_MB * 50 / 100))
  WP_RESERVE_MB=$((WP_LIMIT_MB * 50 / 100))
  NGINX_RESERVE_MB=$((NGINX_LIMIT_MB * 50 / 100))
fi

# CPU: distribuir entre servicios (usar aritmética entera para portabilidad)
# Para servidores pequeños: usar máximo 80% de CPU
if [ "$CPU_CORES" -le 2 ]; then
  # Servidor pequeño: usar máximo 80% de CPU
  MYSQL_CPU_LIMIT_NUM=$((CPU_CORES * 35 / 100))
  MYSQL_CPU_LIMIT="${MYSQL_CPU_LIMIT_NUM}.0"
  if [ "$MYSQL_CPU_LIMIT_NUM" -eq 0 ]; then
    MYSQL_CPU_LIMIT="0.5"
  fi
  
  WP_CPU_LIMIT_NUM=$((CPU_CORES * 35 / 100))
  WP_CPU_LIMIT="${WP_CPU_LIMIT_NUM}.0"
  if [ "$WP_CPU_LIMIT_NUM" -eq 0 ]; then
    WP_CPU_LIMIT="0.5"
  fi
  
  NGINX_CPU_LIMIT_NUM=$((CPU_CORES * 20 / 100))
  NGINX_CPU_LIMIT="${NGINX_CPU_LIMIT_NUM}.0"
  if [ "$NGINX_CPU_LIMIT_NUM" -eq 0 ]; then
    NGINX_CPU_LIMIT="0.25"
  fi
  
  MYSQL_CPU_RESERVE_NUM=$((CPU_CORES * 15 / 100))
  MYSQL_CPU_RESERVE="${MYSQL_CPU_RESERVE_NUM}.0"
  if [ "$MYSQL_CPU_RESERVE_NUM" -eq 0 ]; then
    MYSQL_CPU_RESERVE="0.25"
  fi
  
  WP_CPU_RESERVE_NUM=$((CPU_CORES * 15 / 100))
  WP_CPU_RESERVE="${WP_CPU_RESERVE_NUM}.0"
  if [ "$WP_CPU_RESERVE_NUM" -eq 0 ]; then
    WP_CPU_RESERVE="0.25"
  fi
  
  NGINX_CPU_RESERVE_NUM=$((CPU_CORES * 10 / 100))
  NGINX_CPU_RESERVE="${NGINX_CPU_RESERVE_NUM}.0"
  if [ "$NGINX_CPU_RESERVE_NUM" -eq 0 ]; then
    NGINX_CPU_RESERVE="0.1"
  fi
else
  # Servidor normal: dejar 1 core libre
  AVAILABLE_CPU=$((CPU_CORES - 1))
  MYSQL_CPU_LIMIT_NUM=$((AVAILABLE_CPU * 40 / 100))
  MYSQL_CPU_LIMIT="${MYSQL_CPU_LIMIT_NUM}.0"
  
  WP_CPU_LIMIT_NUM=$((AVAILABLE_CPU * 40 / 100))
  WP_CPU_LIMIT="${WP_CPU_LIMIT_NUM}.0"
  
  NGINX_CPU_LIMIT_NUM=$((AVAILABLE_CPU * 20 / 100))
  NGINX_CPU_LIMIT="${NGINX_CPU_LIMIT_NUM}.0"
  
  MYSQL_CPU_RESERVE_NUM=$((AVAILABLE_CPU * 20 / 100))
  MYSQL_CPU_RESERVE="${MYSQL_CPU_RESERVE_NUM}.0"
  
  WP_CPU_RESERVE_NUM=$((AVAILABLE_CPU * 20 / 100))
  WP_CPU_RESERVE="${WP_CPU_RESERVE_NUM}.0"
  
  NGINX_CPU_RESERVE_NUM=$((AVAILABLE_CPU * 10 / 100))
  NGINX_CPU_RESERVE="${NGINX_CPU_RESERVE_NUM}.0"
fi

# MySQL: innodb_buffer_pool_size (máx 70% del contenedor; en servidores <1GB no superar 128M)
INNODB_BUFFER_MB=$((MYSQL_LIMIT_MB * 70 / 100))
if [ "$RAM_MB" -lt "$MIN_RAM_SERVER_MB" ]; then
  INNODB_BUFFER_MB=128
  MYSQL_TMP_HEAP_MB=16
  MAX_CONNECTIONS=25
else
  if [ "$INNODB_BUFFER_MB" -lt 64 ]; then
    INNODB_BUFFER_MB=64
  fi
  if [ "$INNODB_BUFFER_MB" -gt 256 ]; then
    INNODB_BUFFER_MB=256
  fi
  MYSQL_TMP_HEAP_MB=16
  if [ "$MYSQL_LIMIT_MB" -gt 512 ]; then
    MYSQL_TMP_HEAP_MB=32
  fi
  # Conexiones: en servidores pequeños pocas para ahorrar RAM
  MAX_CONNECTIONS=$((AVAILABLE_RAM / 4))
  if [ "$MAX_CONNECTIONS" -lt 20 ]; then
    MAX_CONNECTIONS=20
  elif [ "$MAX_CONNECTIONS" -gt 50 ]; then
    MAX_CONNECTIONS=50
  fi
fi

# PHP memory_limit: en servidores <1GB usar 128M máximo para que 2 peticiones simultáneas
# quepan en el contenedor (256M - Apache ~50M = ~206M; 2×128M encaja). Más de 128M → OOM → 502.
if [ "$RAM_MB" -lt "$MIN_RAM_SERVER_MB" ]; then
  PHP_MEMORY_MB=128
else
  PHP_MEMORY_MB=$((WP_LIMIT_MB * 60 / 100))
  if [ "$PHP_MEMORY_MB" -lt 128 ]; then
    PHP_MEMORY_MB=128
  fi
  if [ "$PHP_MEMORY_MB" -gt 256 ]; then
    PHP_MEMORY_MB=256
  fi
fi

# Nginx workers: igual a CPU cores, máximo 4 para servidores pequeños
NGINX_WORKERS=$CPU_CORES
if [ "$NGINX_WORKERS" -gt 4 ]; then
  NGINX_WORKERS=4
fi

# Output
cat << EOF
# =============================================================================
# Recursos detectados del sistema
# =============================================================================
CPU Cores: $CPU_CORES
RAM Total: ${RAM_MB}MB
RAM Disponible para Docker: ${AVAILABLE_RAM}MB

# =============================================================================
# Valores recomendados para .env
# =============================================================================
# Recursos Docker (CPU y memoria)
DOCKER_MYSQL_CPU_LIMIT=${MYSQL_CPU_LIMIT}
DOCKER_MYSQL_CPU_RESERVE=${MYSQL_CPU_RESERVE}
DOCKER_MYSQL_MEMORY_LIMIT=${MYSQL_LIMIT_MB}M
DOCKER_MYSQL_MEMORY_RESERVE=${MYSQL_RESERVE_MB}M

DOCKER_WP_CPU_LIMIT=${WP_CPU_LIMIT}
DOCKER_WP_CPU_RESERVE=${WP_CPU_RESERVE}
DOCKER_WP_MEMORY_LIMIT=${WP_LIMIT_MB}M
DOCKER_WP_MEMORY_RESERVE=${WP_RESERVE_MB}M

DOCKER_NGINX_CPU_LIMIT=${NGINX_CPU_LIMIT}
DOCKER_NGINX_CPU_RESERVE=${NGINX_CPU_RESERVE}
DOCKER_NGINX_MEMORY_LIMIT=${NGINX_LIMIT_MB}M
DOCKER_NGINX_MEMORY_RESERVE=${NGINX_RESERVE_MB}M

# MySQL optimizaciones
MYSQL_INNODB_BUFFER_POOL_SIZE=${INNODB_BUFFER_MB}M
MYSQL_MAX_CONNECTIONS=${MAX_CONNECTIONS}
MYSQL_TMP_TABLE_SIZE=${MYSQL_TMP_HEAP_MB:-16}M
MYSQL_MAX_HEAP_TABLE_SIZE=${MYSQL_TMP_HEAP_MB:-16}M

# PHP optimizaciones
PHP_MEMORY_LIMIT=${PHP_MEMORY_MB}M
PHP_MAX_EXECUTION_TIME=300
PHP_MAX_INPUT_VARS=5000

# Nginx optimizaciones
NGINX_WORKER_PROCESSES=${NGINX_WORKERS}
NGINX_WORKER_CONNECTIONS=512
EOF

# Aviso para servidores con muy poca RAM
if [ "$RAM_MB" -lt "$MIN_RAM_SERVER_MB" ]; then
  echo ""
  echo "# NOTA: Servidor con menos de 1GB RAM. Se usan mínimos fijos para evitar 502 y MySQL inestable."
  echo "# Total contenedores: ~$((MYSQL_LIMIT_MB + WP_LIMIT_MB + NGINX_LIMIT_MB))MB. Se recomienda tener swap (ej: 512MB)."
fi
