# Contexto de IA — WordPress Docker (wpdocker)

> **Mantenimiento:** Actualiza este archivo siempre que cambies la estructura del proyecto, servicios Docker, scripts, configuración de nginx/PHP, o convenciones del equipo. Es la fuente de verdad para el asistente de IA.

---

## 1. Resumen del proyecto

- **Qué es:** Stack WordPress en Docker con Nginx como proxy reverso, MySQL 8, scripts de backup/restore y tema hijo Astra.
- **Objetivo:** Despliegue en servidores vacíos con mínima configuración: un solo `.env` y `./scripts/setup.sh` + `docker-compose up -d`. Todo el código es genérico y reutilizable.
- **Optimización:** Detecta recursos del sistema (CPU/RAM) y ajusta límites dinámicamente. Optimizado para servidores pequeños (2 cores, 1GB RAM) para evitar errores 503.
- **Ruta del proyecto:** workspace raíz = `wpdocker` (donde está `docker-compose.yml`).

---

## 2. Stack técnico

| Componente   | Versión/Imagen        | Notas |
|-------------|------------------------|-------|
| WordPress   | `wordpress:latest`     | PHP dentro del contenedor oficial |
| Base de datos | MySQL 8.0           | Auth: `mysql_native_password` |
| Proxy web   | Nginx Alpine           | Solo proxy; no sirve PHP |
| Red         | `wpdocker-wordpress-network` (bridge) | Todos los servicios en la misma red |

---

## 3. Estructura de directorios

```
wpdocker/
├── .env.example             # Plantilla de variables (versionado)
├── .env                     # Configuración por entorno (no versionado; obligatorio)
├── docker-compose.yml       # Servicios: db, wordpress, nginx
├── uploads.ini              # PHP: upload_max_filesize, memory_limit, etc. (montado en wordpress)
├── php-config/
│   ├── opcache.ini          # OPcache optimizado (versionado)
│   └── generated/           # Archivos generados desde .env (no versionado)
│       └── memory.ini       # Generado por setup.sh con PHP_MEMORY_LIMIT
├── backups/                 # No versionado; generado por scripts
│   ├── db/                  # .sql.gz por backup
│   ├── wp/                  # .tar.gz por backup
│   └── *.info               # Metadatos por backup
├── nginx/
│   ├── templates/           # Templates versionados (procesados por contenedor Nginx Alpine)
│   │   ├── nginx.conf.template  # Plantilla principal con ${NGINX_WORKER_PROCESSES}
│   │   └── wordpress.conf.template  # Plantilla servidor con ${DOMAIN}
│   ├── generated/           # Archivos generados (no versionado; en .gitignore)
│   │   └── nginx.conf       # Generado por setup.sh desde template
│   ├── conf.d/              # Configs de servidor (wordpress.conf generado por contenedor)
│   │   └── 00-default.conf  # Servidor por defecto (versionado)
│   └── certs/               # SSL (no versionado salvo .gitkeep)
├── scripts/
│   ├── detect-resources.sh  # Detecta CPU/RAM y calcula límites dinámicos recomendados
│   ├── setup.sh             # Genera nginx.conf y wordpress.conf desde .env; detecta recursos
│   ├── backup.sh            # Backup DB + WP; carga .env y usa COMPOSE_PROJECT_NAME para nombres
│   └── restore.sh           # Restore DB + WP; carga .env; contenedor temporal para archivos
└── themes/
    └── astra-child/         # Tema hijo (versionado)
```

- **Volúmenes Docker:** `wpdocker_db_data`, `wpdocker_wp_data` (nombres fijos en compose).
- **Montajes relevantes:** `themes/` → `wp-content/themes`, `uploads.ini` → PHP conf.d, `backups/db` y `backups/wp` en contenedores.

---

## 4. Servicios y nombres de contenedores

Los nombres de contenedores dependen de `COMPOSE_PROJECT_NAME` en `.env` (default: `wpdocker`):

- **db:** `${COMPOSE_PROJECT_NAME:-wpdocker}_wordpress_mysql` — MySQL 8, healthcheck, límites CPU/RAM dinámicos desde `.env` (`DOCKER_MYSQL_*`). Optimizaciones: `innodb_buffer_pool_size`, `max_connections`, `tmp_table_size` desde `.env`.
- **wordpress:** `${COMPOSE_PROJECT_NAME:-wpdocker}_wordpress_app` — Depende de `db` healthy; recibe proxy desde nginx. Límites CPU/RAM desde `.env` (`DOCKER_WP_*`). PHP con OPcache y `memory_limit` optimizado.
- **nginx:** `${COMPOSE_PROJECT_NAME:-wpdocker}_wordpress_nginx` — Puertos `HTTP_PORT`, `HTTPS_PORT` desde `.env`. Límites CPU/RAM desde `.env` (`DOCKER_NGINX_*`). Workers y conexiones desde `.env` (`NGINX_WORKER_*`).

**Obligatorios en .env:** `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD` (compose falla si faltan). `DOMAIN` obligatorio para `setup.sh`. Resto con defaults optimizados para servidor pequeño (2 cores, 1GB RAM) en `docker-compose.yml` y `.env.example`.

---

## 5. Scripts

- **detect-resources.sh:** Detecta CPU (cores) y RAM total del sistema. Calcula límites recomendados para Docker (`DOCKER_*`), MySQL (`MYSQL_*`), PHP (`PHP_*`) y Nginx (`NGINX_*`) según recursos disponibles. Muestra valores para copiar a `.env`. Optimizado para servidores pequeños (<2GB RAM: más conservador).
- **setup.sh:** Ejecutar antes del primer `docker-compose up -d`. Crea `.env` desde `.env.example` si no existe (y sale pidiendo editarlo). Valida `DOMAIN`, `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`. Si no hay variables `DOCKER_*` en `.env`, ejecuta `detect-resources.sh` y muestra recomendaciones. Genera `nginx/generated/nginx.conf` desde `nginx/templates/nginx.conf.template` (archivo generado no versionado). Genera `php-config/generated/memory.ini` desde `PHP_MEMORY_LIMIT` del `.env`. El contenedor Nginx procesa automáticamente `nginx/templates/wordpress.conf.template` → `nginx/conf.d/wordpress.conf` usando variables de entorno. Crea `backups/db` y `backups/wp`. Muestra resumen de recursos configurados.
- **backup.sh:** `./scripts/backup.sh [nombre]` — Carga `.env`, usa `COMPOSE_PROJECT_NAME` para nombres de contenedores y `MYSQL_*` para mysqldump. Escribe en `backups/db/`, `backups/wp/`, `backups/<nombre>.info`.
- **restore.sh:** `./scripts/restore.sh <nombre>` — Carga `.env`, restaura DB vía compose, para wordpress, usa contenedor temporal `wordpress:latest` con volumen `wpdocker_wp_data` para extraer el tar, reinicia wordpress.

Todos los scripts se ejecutan desde la **raíz del proyecto** y requieren `.env` (y `docker-compose.yml`).

---

## 6. Nginx

- **Templates:** Los templates están en `nginx/templates/` (versionados). El contenedor Nginx Alpine procesa automáticamente archivos `.template` en `/etc/nginx/templates/` usando `envsubst` y los copia a `/etc/nginx/conf.d/` (sin `.template`).
- **Generado:** `nginx/generated/nginx.conf` se genera con `./scripts/setup.sh` desde `nginx/templates/nginx.conf.template` (no versionado, en `.gitignore`). `nginx/conf.d/wordpress.conf` se genera automáticamente por el contenedor desde `nginx/templates/wordpress.conf.template`.
- **Plantillas:** 
  - `nginx/templates/nginx.conf.template` usa `${NGINX_WORKER_PROCESSES}` y `${NGINX_WORKER_CONNECTIONS}`. Optimizado: buffers aumentados (32k), timeouts aumentados (30s), compresión gzip, cache de archivos estáticos, keepalive 16 en upstream.
  - `nginx/templates/wordpress.conf.template` usa `${DOMAIN}` en `server_name`; buffers de proxy aumentados (32k-128k), timeouts aumentados (90-120s), HTTP/1.1 keepalive. SSL y acme-challenge están comentados.
- **Variables de entorno:** Se pasan vía `environment` en `docker-compose.yml`: `DOMAIN`, `NGINX_WORKER_PROCESSES`, `NGINX_WORKER_CONNECTIONS`.
- Certificados en `nginx/certs/` (no versionados).

---

## 7. PHP / WordPress

- **uploads.ini:** Optimizado para recursos limitados: `upload_max_filesize` y `post_max_size` 64M, `memory_limit` 128M (ajustable con `PHP_MEMORY_LIMIT` en `.env`), `max_execution_time` y `max_input_time` 300, `max_input_vars` 5000, `realpath_cache_size` 2M.
- **opcache.ini:** OPcache habilitado con 64M de memoria, `max_accelerated_files` 10000, `revalidate_freq` 60s, `fast_shutdown` activado. Optimizado para reducir uso de memoria.
- Tema hijo: **Astra Child** en `themes/astra-child` (style.css + functions.php encola estilos con dependencia de Astra).

---

## 8. Reglas para el asistente de IA

- **Docker / Compose**
  - Nombres de contenedores desde `COMPOSE_PROJECT_NAME` en `.env`; no hardcodear nombres en scripts.
  - Mantener `depends_on` con `condition: service_healthy` para `wordpress` respecto a `db`.
  - No dar valores por defecto a secretos en compose (`MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`); usar `:?` para fallar si faltan.
  - Recursos dinámicos desde `.env`: `DOCKER_*_CPU_LIMIT`, `DOCKER_*_MEMORY_LIMIT`, `DOCKER_*_CPU_RESERVE`, `DOCKER_*_MEMORY_RESERVE`. Valores por defecto optimizados para servidor pequeño (2 cores, 1GB RAM).
  - MySQL: parámetros desde `.env`: `MYSQL_INNODB_BUFFER_POOL_SIZE`, `MYSQL_MAX_CONNECTIONS`, `MYSQL_TMP_TABLE_SIZE`, `MYSQL_MAX_HEAP_TABLE_SIZE`. Optimizaciones adicionales: `innodb-flush-log-at-trx-commit=2`, `innodb-flush-method=O_DIRECT`.

- **Scripts (Bash)**
  - Ejecutar desde raíz del proyecto; cargar `.env` con `set -a; . ./.env; set +a` (o validar que exista).
  - Usar `COMPOSE_PROJECT_NAME` para construir nombres de contenedores; usar `MYSQL_*` desde `.env` para backup/restore.
  - Usar `set -e` y definir `RED`/`GREEN`/`YELLOW`/`NC` cuando se muestren errores.
  - Mantener compatibilidad macOS/Linux (p. ej. envsubst opcional con fallback sed en setup.sh).

- **Nginx**
  - Los templates están en `nginx/templates/` (versionados). El contenedor procesa automáticamente `.template` usando variables de entorno. Los archivos generados (`nginx/generated/`, `nginx/conf.d/wordpress.conf`) no se versionan (en `.gitignore`).
  - Cambios de estructura HTTPS, server_name, workers o buffers hacerlos en las plantillas (`nginx/templates/nginx.conf.template`, `nginx/templates/wordpress.conf.template`). Para aplicar cambios: ejecutar `setup.sh` (regenera `nginx.conf`) y reiniciar contenedor (regenera `wordpress.conf` automáticamente).
  - Optimizaciones aplicadas: buffers aumentados (32k-128k), timeouts aumentados (30-120s), compresión gzip, cache de archivos estáticos, keepalive 16 en upstream. Ajustar según recursos del servidor.

- **WordPress / temas**
  - Cambios en tema hijo solo en `themes/astra-child/`; no modificar temas en el volumen de WordPress.
  - Si se añaden constantes o configuraciones que afecten a backup/restore o a scripts, documentarlas aquí.

- **Seguridad**
  - `.env` y `nginx/certs/*` no se versionan. No añadir excepciones que suban secretos o certificados.
  - En producción: HTTPS, contraseñas fuertes y `WORDPRESS_DEBUG=false`.

---

## 9. Buenas prácticas del proyecto

1. **Backups:** Hacer backup antes de actualizar WordPress/plugins o antes de restauraciones.
2. **Migraciones:** Backup con nombre descriptivo → copiar proyecto y `backups/` → en destino: crear `.env` (mismo dominio/credenciales o los del nuevo sitio) → `./scripts/setup.sh` → `docker-compose up -d` → si aplica, `./scripts/restore.sh <nombre>`.
3. **Dominio:** Definir `DOMAIN` en `.env` y ejecutar `./scripts/setup.sh`; no editar archivos `.conf` generados a mano para no romper el flujo genérico.
4. **Optimización de recursos:** En servidores nuevos, ejecutar `./scripts/detect-resources.sh` y copiar valores recomendados a `.env`. Si hay errores 503 o el servidor se cuelga, reducir límites de memoria (`DOCKER_*_MEMORY_LIMIT`) y CPU (`DOCKER_*_CPU_LIMIT`). Valores por defecto optimizados para 2 cores / 1GB RAM.
5. **Debug:** En producción `WORDPRESS_DEBUG=false` en `.env`; en desarrollo se puede poner `true`.
6. **Mantenimiento de este archivo:** Al añadir servicios, volúmenes, scripts, variables en `.env.example` o convenciones, actualizar las secciones correspondientes.

---

## 10. Referencias rápidas

- **Primer despliegue:** `cp .env.example .env` → editar `.env` (DOMAIN, MYSQL_ROOT_PASSWORD, MYSQL_PASSWORD) → `./scripts/setup.sh` → `docker-compose up -d`
- **Levantar:** `docker-compose up -d`
- **Backup:** `./scripts/backup.sh [nombre]`
- **Restaurar:** `./scripts/restore.sh <nombre>`
- **Logs:** `docker-compose logs -f [servicio]`
- **WP en contenedor:** `docker-compose exec wordpress bash`
- **MySQL:** `docker-compose exec db mysql -u <MYSQL_USER> -p <MYSQL_DATABASE>` (credenciales en `.env`)
