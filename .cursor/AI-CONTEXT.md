# Contexto de IA — WordPress Docker (wpdocker)

> **Mantenimiento:** Actualiza este archivo siempre que cambies la estructura del proyecto, servicios Docker, scripts, configuración de nginx/PHP, o convenciones del equipo. Es la fuente de verdad para el asistente de IA.

---

## 1. Resumen del proyecto

- **Qué es:** Stack WordPress en Docker con Nginx como proxy reverso, MySQL 8, scripts de backup/restore y tema hijo Astra.
- **Objetivo:** Despliegue en servidores vacíos con mínima configuración: un solo `.env` y `./scripts/setup.sh` + `docker-compose up -d`. Todo el código es genérico y reutilizable.
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
├── backups/                 # No versionado; generado por scripts
│   ├── db/                  # .sql.gz por backup
│   ├── wp/                  # .tar.gz por backup
│   └── *.info               # Metadatos por backup
├── nginx/
│   ├── nginx.conf           # Incluye conf.d
│   ├── conf.d/
│   │   ├── wordpress.conf.template  # Plantilla con ${DOMAIN} (versionada)
│   │   └── wordpress.conf   # Generado por setup.sh (no versionado; en .gitignore)
│   └── certs/               # SSL (no versionado salvo .gitkeep)
├── scripts/
│   ├── setup.sh             # Genera wordpress.conf desde .env; valida DOMAIN y contraseñas
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

- **db:** `${COMPOSE_PROJECT_NAME:-wpdocker}_wordpress_mysql` — MySQL 8, healthcheck, límites CPU/RAM.
- **wordpress:** `${COMPOSE_PROJECT_NAME:-wpdocker}_wordpress_app` — Depende de `db` healthy; recibe proxy desde nginx.
- **nginx:** `${COMPOSE_PROJECT_NAME:-wpdocker}_wordpress_nginx` — Puertos `HTTP_PORT`, `HTTPS_PORT` desde `.env`.

**Obligatorios en .env:** `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD` (compose falla si faltan). `DOMAIN` obligatorio para `setup.sh`. Resto con defaults en `docker-compose.yml` y `.env.example`.

---

## 5. Scripts

- **setup.sh:** Ejecutar antes del primer `docker-compose up -d`. Crea `.env` desde `.env.example` si no existe (y sale pidiendo editarlo). Valida `DOMAIN`, `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`. Genera `nginx/conf.d/wordpress.conf` desde la plantilla con `envsubst '$DOMAIN'` (o `sed` si no hay envsubst). Crea `backups/db` y `backups/wp`.
- **backup.sh:** `./scripts/backup.sh [nombre]` — Carga `.env`, usa `COMPOSE_PROJECT_NAME` para nombres de contenedores y `MYSQL_*` para mysqldump. Escribe en `backups/db/`, `backups/wp/`, `backups/<nombre>.info`.
- **restore.sh:** `./scripts/restore.sh <nombre>` — Carga `.env`, restaura DB vía compose, para wordpress, usa contenedor temporal `wordpress:latest` con volumen `wpdocker_wp_data` para extraer el tar, reinicia wordpress.

Todos los scripts se ejecutan desde la **raíz del proyecto** y requieren `.env` (y `docker-compose.yml`).

---

## 6. Nginx

- **Generado:** `nginx/conf.d/wordpress.conf` se genera con `./scripts/setup.sh` a partir de `wordpress.conf.template` y la variable `DOMAIN` del `.env`. No se versiona (está en `.gitignore`).
- **Plantilla:** `wordpress.conf.template` usa `${DOMAIN}` en `server_name`; SSL y acme-challenge están comentados; para HTTPS hay que descomentar el bloque en la plantilla (o en el conf generado) y poner certificados en `nginx/certs/`.
- Certificados en `nginx/certs/` (no versionados).

---

## 7. PHP / WordPress

- **uploads.ini:** `upload_max_filesize` y `post_max_size` 128M, `memory_limit` 512M, `max_execution_time` y `max_input_time` 300, `max_input_vars` 5000.
- Tema hijo: **Astra Child** en `themes/astra-child` (style.css + functions.php encola estilos con dependencia de Astra).

---

## 8. Reglas para el asistente de IA

- **Docker / Compose**
  - Nombres de contenedores desde `COMPOSE_PROJECT_NAME` en `.env`; no hardcodear nombres en scripts.
  - Mantener `depends_on` con `condition: service_healthy` para `wordpress` respecto a `db`.
  - No dar valores por defecto a secretos en compose (`MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`); usar `:?` para fallar si faltan.

- **Scripts (Bash)**
  - Ejecutar desde raíz del proyecto; cargar `.env` con `set -a; . ./.env; set +a` (o validar que exista).
  - Usar `COMPOSE_PROJECT_NAME` para construir nombres de contenedores; usar `MYSQL_*` desde `.env` para backup/restore.
  - Usar `set -e` y definir `RED`/`GREEN`/`YELLOW`/`NC` cuando se muestren errores.
  - Mantener compatibilidad macOS/Linux (p. ej. envsubst opcional con fallback sed en setup.sh).

- **Nginx**
  - El dominio y la config activa salen de la plantilla y de `DOMAIN` en `.env`; no editar `wordpress.conf` a mano si se quiere despliegue genérico.
  - Cambios de estructura HTTPS o server_name hacerlos en `wordpress.conf.template` y volver a ejecutar `setup.sh`.

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
3. **Dominio:** Definir `DOMAIN` en `.env` y ejecutar `./scripts/setup.sh`; no editar `wordpress.conf` a mano para no romper el flujo genérico.
4. **Debug:** En producción `WORDPRESS_DEBUG=false` en `.env`; en desarrollo se puede poner `true`.
5. **Mantenimiento de este archivo:** Al añadir servicios, volúmenes, scripts, variables en `.env.example` o convenciones, actualizar las secciones correspondientes.

---

## 10. Referencias rápidas

- **Primer despliegue:** `cp .env.example .env` → editar `.env` (DOMAIN, MYSQL_ROOT_PASSWORD, MYSQL_PASSWORD) → `./scripts/setup.sh` → `docker-compose up -d`
- **Levantar:** `docker-compose up -d`
- **Backup:** `./scripts/backup.sh [nombre]`
- **Restaurar:** `./scripts/restore.sh <nombre>`
- **Logs:** `docker-compose logs -f [servicio]`
- **WP en contenedor:** `docker-compose exec wordpress bash`
- **MySQL:** `docker-compose exec db mysql -u <MYSQL_USER> -p <MYSQL_DATABASE>` (credenciales en `.env`)
