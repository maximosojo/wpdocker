# WordPress con Docker

Proyecto WordPress listo para desplegar en **servidores vacíos** con mínima configuración: solo un archivo `.env` y dos comandos.

## 🚀 Características

- ✅ **Despliegue genérico:** un solo `.env` define dominio, BD, puertos y debug
- ✅ **Optimización automática:** detecta recursos del servidor y ajusta límites de CPU/RAM dinámicamente
- ✅ **Servidores pequeños:** optimizado para 2 cores / 1GB RAM (evita errores 503)
- ✅ Nginx generado desde plantilla (no editar `wordpress.conf` a mano)
- ✅ Backup y restauración que usan el mismo `.env`
- ✅ Configuración SSL lista para Let's Encrypt
- ✅ Nginx como proxy reverso; MySQL 8 + WordPress oficial

## 📋 Requisitos

- Docker (20.10+) y Docker Compose (2.0+)
- En el servidor: solo Docker instalado; el resto se hace con el proyecto

```bash
docker --version
docker-compose --version
```

## 🏁 Despliegue rápido (servidor vacío o local)

Todo se controla con el archivo `.env`. Los archivos de configuración se generan automáticamente.

```bash
# 1. Clonar o copiar el proyecto
git clone <repositorio> wpdocker && cd wpdocker

# 2. Crear y editar .env (dominio y contraseñas obligatorios)
cp .env.example .env
# Editar .env: DOMAIN, MYSQL_ROOT_PASSWORD, MYSQL_PASSWORD (y opcionalmente puertos, recursos, etc.)

# 3. Generar configuración desde .env (obligatorio antes del primer docker compose up)
./scripts/setup.sh

# 4. (Opcional) Validar configuración antes de desplegar
./scripts/test-complete.sh

# 5. Arrancar servicios
docker compose up -d

# 6. Ver logs hasta que WordPress esté listo
docker compose logs -f
```

**Nota importante:** 
- Siempre ejecuta `./scripts/setup.sh` antes de `docker compose up` para generar la configuración correcta desde tu `.env`
- Si ejecutas `docker compose up` sin `setup.sh`, se usarán archivos de configuración por defecto (localhost, valores básicos)
- Usa `./scripts/test-complete.sh` para validar que todo está correcto antes de desplegar

El sitio queda en `http://<DOMAIN>` (o `http://localhost` si `DOMAIN=localhost`). Si cambias `DOMAIN` o `HTTP_PORT` en `.env`, vuelve a ejecutar `./scripts/setup.sh` y reinicia: `docker-compose up -d`.

## 🔧 Variables de entorno (.env)

Copia `.env.example` a `.env` y rellena al menos:

| Variable | Obligatorio | Descripción |
|----------|-------------|-------------|
| `DOMAIN` | Sí | Dominio del sitio (ej. `midominio.com` o `localhost`) |
| `MYSQL_ROOT_PASSWORD` | Sí | Contraseña del usuario root de MySQL |
| `MYSQL_PASSWORD` | Sí | Contraseña del usuario de WordPress (y `WORDPRESS_DB_*`) |
| `COMPOSE_PROJECT_NAME` | No | Identificador del proyecto (default: `wpdocker`); define nombres de contenedores |
| `MYSQL_DATABASE`, `MYSQL_USER` | No | Base de datos y usuario (default: `wordpress_db`, `wordpress_user`) |
| `HTTP_PORT`, `HTTPS_PORT` | No | Puertos en el host (default: 80, 443) |
| `WORDPRESS_DEBUG` | No | `true`/`false` (default: `false`) |

El resto está documentado en `.env.example`. **No subas `.env` a Git.**

## ⚡ Optimización de recursos

El proyecto está optimizado para servidores con recursos limitados (2 cores, 1GB RAM). Los recursos se detectan automáticamente y se ajustan dinámicamente.

### Detección automática

Al ejecutar `./scripts/setup.sh`, se detectan los recursos del sistema y se muestran valores recomendados. Si no defines variables `DOCKER_*` en `.env`, se usan valores por defecto optimizados para servidor pequeño.

### Ajustar recursos manualmente

Para servidores con más recursos, ejecuta:

```bash
./scripts/detect-resources.sh
```

Esto muestra valores recomendados según tu servidor. Copia los valores `DOCKER_*`, `MYSQL_*`, `PHP_*` y `NGINX_*` a tu `.env`.

### Variables de recursos en .env

| Variable | Descripción | Default (servidor pequeño) |
|----------|-------------|----------------------------|
| `DOCKER_MYSQL_CPU_LIMIT` | Límite de CPU para MySQL | `0.7` |
| `DOCKER_MYSQL_MEMORY_LIMIT` | Límite de RAM para MySQL | `240M` |
| `DOCKER_WP_CPU_LIMIT` | Límite de CPU para WordPress | `0.7` |
| `DOCKER_WP_MEMORY_LIMIT` | Límite de RAM para WordPress | `210M` |
| `DOCKER_NGINX_CPU_LIMIT` | Límite de CPU para Nginx | `0.4` |
| `DOCKER_NGINX_MEMORY_LIMIT` | Límite de RAM para Nginx | `90M` |
| `MYSQL_INNODB_BUFFER_POOL_SIZE` | Buffer pool de InnoDB | `168M` |
| `MYSQL_MAX_CONNECTIONS` | Conexiones máximas MySQL | `30` |
| `PHP_MEMORY_LIMIT` | Memoria PHP | `128M` |
| `NGINX_WORKER_PROCESSES` | Workers de Nginx | `2` |

### Optimizaciones aplicadas

- **MySQL:** Buffer pool ajustado según RAM, conexiones limitadas, flush optimizado
- **PHP:** OPcache habilitado, memory_limit reducido, realpath cache optimizado
- **Nginx:** Workers según CPU, buffers pequeños, timeouts reducidos, compresión gzip
- **Docker:** Límites de CPU y RAM por contenedor para evitar OOM

### Solución de problemas de rendimiento

Si experimentas errores 503 o el servidor se cuelga:

1. **Verifica recursos disponibles:**
   ```bash
   free -h
   nproc
   ```

2. **Ejecuta detección de recursos:**
   ```bash
   ./scripts/detect-resources.sh
   ```

3. **Ajusta valores en `.env`** según las recomendaciones

4. **Reinicia servicios:**
   ```bash
   docker-compose down
   ./scripts/setup.sh
   docker-compose up -d
   ```

### Nginx

Los archivos de configuración se generan desde templates en el host:

- **`nginx/templates/`** (versionados): Contiene las plantillas `.template` con variables `${DOMAIN}`, `${NGINX_WORKER_PROCESSES}`, etc.
- **`nginx/generated/`** (no versionado, en `.gitignore`): Contiene archivos generados por `setup.sh`:
  - `nginx.conf` → generado desde `nginx/templates/nginx.conf.template`
  - `wordpress.conf` → generado desde `nginx/templates/wordpress.conf.template`

**No edites archivos generados** (`nginx/generated/*`). Para cambios permanentes, modifica los templates en `nginx/templates/` y ejecuta `./scripts/setup.sh` para regenerarlos.

### Configuración inicial de WordPress

1. Abre el navegador en `http://<DOMAIN>` (o el puerto que hayas puesto en `HTTP_PORT`).
2. Sigue el asistente de instalación de WordPress (idioma, usuario administrador, etc.).
3. La base de datos se crea automáticamente la primera vez.

## 💾 Backup y Restauración

### Realizar un Backup

El script de backup crea un respaldo completo de:
- Base de datos MySQL
- Archivos de WordPress (themes, plugins, uploads, etc.)

```bash
# Backup con nombre automático (timestamp)
./scripts/backup.sh

# Backup con nombre personalizado
./scripts/backup.sh mi_backup_enero_2024
```

Los backups se guardan en:
- Base de datos: `backups/db/nombre_backup.sql.gz`
- WordPress: `backups/wp/nombre_backup.tar.gz`
- Información: `backups/nombre_backup.info`

### Restaurar un Backup

⚠️ **ADVERTENCIA**: La restauración sobrescribirá todos los datos actuales.

```bash
# Listar backups disponibles (si no recuerdas el nombre)
ls backups/*.info

# Restaurar un backup específico
./scripts/restore.sh backup_20240101_120000

# O con nombre personalizado
./scripts/restore.sh mi_backup_enero_2024
```

**Proceso de restauración**:
1. Se restaura la base de datos
2. Se detiene WordPress temporalmente
3. Se restauran todos los archivos
4. Se reinicia WordPress

## 🌐 Migración a un Nuevo Servidor

### Paso 1: Realizar Backup en el Servidor Original

```bash
./scripts/backup.sh migracion_servidor_fecha
```

### Paso 2: Transferir los Backups al Nuevo Servidor

Usa `scp`, `rsync`, o cualquier método de transferencia:

```bash
# Ejemplo con scp
scp -r backups/ usuario@nuevo-servidor:/ruta/al/proyecto/wordpress/

# O comprimir primero
tar -czf backups.tar.gz backups/
scp backups.tar.gz usuario@nuevo-servidor:/ruta/al/proyecto/wordpress/
```

### Paso 3: Configurar el nuevo servidor

1. **Copiar el proyecto** (y la carpeta `backups/` si vas a restaurar):
   ```bash
   git clone <repositorio> wpdocker && cd wpdocker
   ```

2. **Crear `.env`** con el mismo dominio, contraseñas y opciones que necesites (puedes copiar el `.env` del servidor anterior o crear desde `.env.example`).

3. **Generar Nginx y arrancar**:
   ```bash
   ./scripts/setup.sh
   docker-compose up -d
   ```

4. **Si trajiste backups**, restaurar cuando los servicios estén listos:
   ```bash
   docker-compose logs -f   # Ctrl+C cuando WordPress esté listo
   ./scripts/restore.sh migracion_servidor_fecha
   ```

### Paso 4: Restaurar el Backup

```bash
# Asegúrate de que los backups estén en la carpeta backups/
./scripts/restore.sh migracion_servidor_fecha
```

### Paso 5: Configurar SSL (Opcional)

#### Opción A: Let's Encrypt con Certbot

1. **Instalar Certbot** (en el host, no en el contenedor):
   ```bash
   # Ubuntu/Debian
   sudo apt-get update
   sudo apt-get install certbot

   # macOS
   brew install certbot
   ```

2. **Obtener certificados**:
   ```bash
   sudo certbot certonly --standalone -d tudominio.com -d www.tudominio.com
   ```

3. **Copiar certificados a la carpeta del proyecto**:
   ```bash
   sudo cp /etc/letsencrypt/live/tudominio.com/fullchain.pem nginx/certs/
   sudo cp /etc/letsencrypt/live/tudominio.com/privkey.pem nginx/certs/
   sudo chown $USER:$USER nginx/certs/*.pem
   ```

4. **Habilitar SSL en nginx**:
   - Edita `nginx/conf.d/wordpress.conf`
   - Descomenta la sección `server` de HTTPS (puerto 443)
   - Descomenta la redirección de HTTP a HTTPS en la sección del puerto 80
   - Actualiza las rutas de los certificados si es necesario

5. **Reiniciar nginx**:
   ```bash
   docker-compose restart nginx
   ```

#### Opción B: Certificados SSL Propios

Si tienes tus propios certificados SSL:

1. Coloca los certificados en `nginx/certs/`:
   - `fullchain.pem` (certificado completo)
   - `privkey.pem` (clave privada)
   - `chain.pem` (cadena, opcional)

2. Edita `nginx/conf.d/wordpress.conf`:
   - Descomenta y configura la sección HTTPS
   - Actualiza las rutas si los nombres de archivo son diferentes

3. Reinicia nginx:
   ```bash
   docker-compose restart nginx
   ```

## 🛠️ Comandos Útiles

### Gestión de Contenedores

```bash
# Iniciar servicios
docker-compose up -d

# Detener servicios
docker-compose stop

# Detener y eliminar contenedores
docker-compose down

# Ver logs
docker-compose logs -f

# Ver logs de un servicio específico
docker-compose logs -f wordpress

# Reiniciar un servicio
docker-compose restart nginx

# Reconstruir servicios
docker-compose up -d --build
```

### Acceso a Contenedores

```bash
# Acceder al contenedor de WordPress
docker-compose exec wordpress bash

# Acceder al contenedor de MySQL
docker-compose exec db bash

# Acceder a MySQL directamente
docker-compose exec db mysql -u wordpress_user -p wordpress_db
```

### Limpieza

```bash
# Eliminar contenedores, redes y volúmenes
docker-compose down -v

# Eliminar imágenes no utilizadas
docker image prune

# Limpiar todo (¡cuidado! elimina contenedores, imágenes, volúmenes)
docker system prune -a --volumes
```

## 📁 Estructura del proyecto

```
wpdocker/
├── .env.example         # Plantilla de variables (copiar a .env)
├── .env                 # Tu configuración (no versionado)
├── docker-compose.yml   # Servicios: db, wordpress, nginx
├── uploads.ini          # Límites PHP (uploads, memoria, etc.)
├── backups/             # Generado; no versionado
│   ├── db/              # Backups de base de datos (.sql.gz)
│   └── wp/              # Backups de WordPress (.tar.gz)
├── nginx/
│   ├── templates/       # Templates versionados (procesados por contenedor)
│   │   ├── nginx.conf.template
│   │   └── wordpress.conf.template
│   ├── generated/       # Archivos generados (no versionado)
│   │   └── nginx.conf
│   ├── conf.d/
│   │   ├── 00-default.conf         # Siempre presente (versionado)
│   │   └── wordpress.conf          # Generado automáticamente por contenedor (no versionado)
│   └── certs/           # Certificados SSL (no versionado)
├── php-config/
│   ├── opcache.ini      # OPcache (versionado)
│   └── generated/       # Archivos generados (no versionado)
│       └── memory.ini   # Generado por setup.sh desde PHP_MEMORY_LIMIT
├── scripts/
│   ├── detect-resources.sh  # Detecta recursos y calcula valores recomendados
│   ├── setup.sh         # Genera archivos desde .env; ejecutar antes del primer up
│   ├── backup.sh        # Backup DB + WP (usa .env)
│   └── restore.sh       # Restauración (usa .env)
└── themes/
    └── astra-child/     # Tema hijo
```

## 🔒 Seguridad

- ⚠️ **Nunca** subas el archivo `.env` a Git (ya está en `.gitignore`)
- ⚠️ **Cambia** las contraseñas por defecto en producción
- ⚠️ **Usa HTTPS** en producción con certificados SSL válidos
- ⚠️ **Mantén** WordPress y los plugins actualizados
- ⚠️ **Backup** regularmente antes de actualizaciones importantes

## 🐛 Solución de Problemas

### WordPress no se conecta a la base de datos

1. Verifica que el contenedor de MySQL esté corriendo:
   ```bash
   docker-compose ps
   ```

2. Verifica las variables de entorno en `docker-compose.yml` o `.env`

3. Revisa los logs:
   ```bash
   docker-compose logs db
   docker-compose logs wordpress
   ```

### Error de permisos en WordPress

```bash
# Ajustar permisos en el contenedor
docker-compose exec wordpress chown -R www-data:www-data /var/www/html
docker-compose exec wordpress chmod -R 755 /var/www/html
```

### Puerto 80 o 443 ya en uso

En `.env` define otros puertos, por ejemplo:

```env
HTTP_PORT=8080
HTTPS_PORT=8443
```

Luego `docker-compose up -d`.

### Error al restaurar backup

- Verifica que los archivos de backup existan en `backups/db/` y `backups/wp/`
- Asegúrate de que el nombre del backup sea correcto
- Revisa los logs: `docker-compose logs wordpress`

### Nginx en bucle "Restarting"

Si el contenedor `wpdocker_wordpress_nginx` no arranca (status Restarting):

1. **Comprueba que exista** `nginx/conf.d/00-default.conf` (va en el repo; si falta, copia del proyecto).
2. **Revisa los logs** de Nginx:
   ```bash
   docker compose logs nginx
   ```
   Ahí suele aparecer el error de configuración (sintaxis, ruta, etc.).
3. **Valida la configuración** dentro del contenedor:
   ```bash
   docker compose run --rm nginx nginx -t
   ```
4. Si despliegas sin ejecutar `setup.sh`, Nginx puede usar solo `00-default.conf` (funciona). Para usar tu dominio, ejecuta `./scripts/setup.sh` para generar `wordpress.conf`.

## 📝 Notas Adicionales

- Los volúmenes de Docker persisten los datos incluso si los contenedores se eliminan
- Los backups son independientes de los volúmenes de Docker
- Se recomienda hacer backups antes de actualizar WordPress o plugins
- El proyecto está optimizado para entornos de desarrollo y producción pequeña/mediana

## 📄 Licencia

Este proyecto es una configuración personalizada para WordPress con Docker.

---

**¿Problemas o preguntas?** Revisa la sección de Solución de Problemas o consulta la documentación de [Docker](https://docs.docker.com/) y [WordPress](https://wordpress.org/support/).
