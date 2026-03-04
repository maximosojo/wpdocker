# WordPress con Docker

WordPress listo para desplegar en **servidores vacíos** (Debian, Ubuntu, etc.) con mínima configuración: un archivo `.env` y unos pocos comandos.

---

## Índice

1. [Requisitos](#-requisitos)
2. [Instalación de Docker](#-instalación-de-docker)
3. [Despliegue paso a paso](#-despliegue-paso-a-paso)
4. [Configuración (.env)](#-configuración-env)
5. [Optimización de recursos](#-optimización-de-recursos)
6. [Backup y restauración](#-backup-y-restauración)
7. [Migración e importación](#-migración-e-importación)
8. [SSL (HTTPS)](#-ssl-https)
9. [Comandos útiles](#-comandos-útiles)
10. [Estructura del proyecto](#-estructura-del-proyecto)
11. [Solución de problemas](#-solución-de-problemas)

---

## 📋 Requisitos

- **Docker** 20.10 o superior  
- **Docker Compose** 2.0 o superior (plugin `docker compose` o binario `docker-compose`)  
- Sistema: **Debian**, **Ubuntu** u otra distro Linux; también funciona en **macOS** y **Windows** con Docker Desktop  

Comprobar instalación:

```bash
docker --version
docker compose version
# o, según instalación: docker-compose --version
```

Si no tienes Docker instalado, sigue la sección [Instalación de Docker](#-instalación-de-docker).

---

## 🔧 Instalación de Docker

### Debian / Ubuntu

```bash
# Actualizar e instalar dependencias
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

# Añadir clave y repositorio oficial de Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# En Debian, sustituir "ubuntu" por "debian" en la URL anterior y usar:
# echo "deb [arch=...] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalar Docker Engine y Docker Compose
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# (Opcional) Ejecutar Docker sin sudo
sudo usermod -aG docker $USER
# Cerrar sesión y volver a entrar para que aplique
```

### Otras distros / método genérico

- **Fedora / RHEL / CentOS:** [Install Docker Engine](https://docs.docker.com/engine/install/fedora/)  
- **macOS / Windows:** [Docker Desktop](https://www.docker.com/products/docker-desktop/)  
- **Script oficial (cualquier Linux):** `curl -fsSL https://get.docker.com | sh`

---

## 🏁 Despliegue paso a paso

Sigue estos pasos en orden para levantar WordPress sin errores.

### Paso 1: Obtener el proyecto

```bash
git clone <url-del-repositorio> wpdocker
cd wpdocker
```

Si no usas Git, copia la carpeta del proyecto en el servidor y entra en ella.

---

### Paso 2: Crear y editar el archivo `.env`

```bash
cp .env.example .env
nano .env   # o vim, vi, etc.
```

**Mínimo obligatorio:** define estas variables:

| Variable | Ejemplo | Descripción |
|----------|---------|-------------|
| `DOMAIN` | `midominio.com` o `localhost` | Dominio del sitio |
| `MYSQL_ROOT_PASSWORD` | Una contraseña segura | Contraseña root de MySQL |
| `MYSQL_PASSWORD` | Otra contraseña segura | Contraseña del usuario de WordPress en la BD |

El resto (puertos, base de datos, recursos) tiene valores por defecto; puedes dejarlos o ajustarlos más adelante.

---

### Paso 3: Generar la configuración

Este script genera la configuración de Nginx y PHP a partir del `.env`. **Debe ejecutarse antes del primer `docker compose up`.**

```bash
./scripts/setup.sh
```

Si aparece algún error (por ejemplo falta `DOMAIN` o contraseñas), corrige el `.env` y vuelve a ejecutar `./scripts/setup.sh`.

---

### Paso 4: (Opcional) Validar antes de arrancar

```bash
./scripts/test-complete.sh
```

Si todo es correcto, el script termina sin errores y puedes seguir.

---

### Paso 5: Arrancar los servicios (con límites de RAM aplicados)

Para que los contenedores usen la RAM definida en `.env` (y no se queden en ~900M ni den 502), arranca con:

```bash
./scripts/up.sh
```

O bien: `docker compose --compatibility up -d`. Si usas solo `docker compose up -d`, Docker **no aplica** los límites de memoria y el sitio puede ir lento o dar 502.

Espera a que MySQL marque *healthy* y WordPress y Nginx estén *Up*. Puedes seguir los logs:

```bash
docker compose logs -f
```

Pulsa `Ctrl+C` para salir de los logs (los contenedores siguen en marcha).

---

### Paso 6: Completar WordPress en el navegador

1. Abre `http://<DOMAIN>` (o `http://localhost` si `DOMAIN=localhost`).  
2. Si usas otro puerto (p. ej. `HTTP_PORT=8080` en `.env`), usa `http://localhost:8080`.  
3. Sigue el asistente de instalación (idioma, usuario administrador, etc.).

Cuando termines, ya tienes WordPress funcionando con Docker.

---

### Resumen de comandos (despliegue rápido)

```bash
cd wpdocker
cp .env.example .env
nano .env                    # Definir DOMAIN, MYSQL_ROOT_PASSWORD, MYSQL_PASSWORD
./scripts/setup.sh
./scripts/test-complete.sh   # opcional
docker compose up -d
# Abrir en navegador: http://<DOMAIN> o http://localhost
```

---

## 🔧 Configuración (.env)

Copia `.env.example` a `.env` y ajusta lo que necesites. Variables principales:

| Variable | Obligatorio | Descripción |
|----------|-------------|-------------|
| `DOMAIN` | Sí | Dominio del sitio (ej. `midominio.com` o `localhost`) |
| `MYSQL_ROOT_PASSWORD` | Sí | Contraseña del usuario root de MySQL |
| `MYSQL_PASSWORD` | Sí | Contraseña del usuario de WordPress en la BD |
| `COMPOSE_PROJECT_NAME` | No | Identificador del proyecto (default: `wpdocker`) |
| `MYSQL_DATABASE`, `MYSQL_USER` | No | Base de datos y usuario (default: `wordpress_db`, `wordpress_user`) |
| `HTTP_PORT`, `HTTPS_PORT` | No | Puertos en el host (default: 80, 443) |
| `WORDPRESS_DEBUG` | No | `true` o `false` (default: `false`) |

Más opciones (recursos, MySQL, PHP, Nginx) están documentadas en `.env.example`. **No subas `.env` a Git** (ya está en `.gitignore`).

Si cambias `DOMAIN` o `HTTP_PORT`/`HTTPS_PORT`, vuelve a ejecutar `./scripts/setup.sh` y reinicia:

```bash
./scripts/setup.sh
docker compose up -d
```

---

## ⚡ Optimización de recursos

El proyecto está pensado para servidores con pocos recursos (p. ej. 2 cores, 1 GB RAM). Los límites por defecto ya están ajustados para reducir 503 y cuelgues.

### Detección automática

Al ejecutar `./scripts/setup.sh`, si no tienes variables `DOCKER_*` en `.env`, se muestran valores recomendados según el sistema. Puedes copiarlos al `.env` o usar los valores por defecto.

### Ajustar recursos manualmente

```bash
./scripts/detect-resources.sh
```

Copia las variables que imprima (DOCKER_*, MYSQL_*, PHP_*, NGINX_*) a tu `.env` y vuelve a ejecutar `./scripts/setup.sh` y `docker compose up -d`.

### Variables de recursos (resumen)

| Variable | Descripción | Default (servidor pequeño) |
|----------|-------------|-----------------------------|
| `DOCKER_MYSQL_MEMORY_LIMIT` | RAM máxima MySQL | `360M` |
| `DOCKER_WP_MEMORY_LIMIT` | RAM máxima WordPress | `300M` |
| `DOCKER_NGINX_MEMORY_LIMIT` | RAM máxima Nginx | `80M` |
| `MYSQL_INNODB_BUFFER_POOL_SIZE` | Buffer InnoDB | `160M` |
| `PHP_MEMORY_LIMIT` | Memoria PHP | `160M` |
| `NGINX_WORKER_PROCESSES` | Workers Nginx | `2` |

Si ves 503 o el servidor muy lento, ejecuta `./scripts/detect-resources.sh`, ajusta según las recomendaciones y reinicia los contenedores.

**Servidor con 1 GB RAM:** Si tienes solo 1 GB de RAM, no asignes a los contenedores más de ~740 MB en total o el sistema se colgará o reiniciará. Usa el perfil preparado para 1 GB: [docs/servidor-1gb-ram.md](docs/servidor-1gb-ram.md) y [docs/env-1gb-ram.example](docs/env-1gb-ram.example).

### Nginx (archivos generados)

- **`nginx/templates/`** (en el repo): plantillas con variables como `${DOMAIN}`, `${NGINX_WORKER_PROCESSES}`.
- **`nginx/generated/`** (no en Git): archivos generados por `./scripts/setup.sh`.

No edites los archivos en `nginx/generated/`. Para cambios permanentes, modifica los templates en `nginx/templates/` y vuelve a ejecutar `./scripts/setup.sh`.

---

## 💾 Backup y restauración

### Hacer backup

```bash
# Con nombre automático (fecha/hora)
./scripts/backup.sh

# Con nombre propio
./scripts/backup.sh mi_backup_enero_2024
```

Se crean:

- Base de datos: `backups/db/<nombre>.sql.gz`
- Archivos WordPress: `backups/wp/<nombre>.tar.gz`
- Metadatos: `backups/<nombre>.info`

### Restaurar un backup

⚠️ **Sobrescribe** la base de datos y los archivos actuales.

```bash
# Ver backups disponibles
ls backups/*.info

# Restaurar uno
./scripts/restore.sh backup_20240101_120000
# o
./scripts/restore.sh mi_backup_enero_2024
```

---

## 🌐 Migración e importación

### Migrar a otro servidor (backup de este proyecto)

1. En el servidor actual: `./scripts/backup.sh migracion_20240101`
2. Copiar la carpeta del proyecto (y `backups/`) al nuevo servidor.
3. En el nuevo servidor: crear/editar `.env`, ejecutar `./scripts/setup.sh`, `docker compose up -d`.
4. Cuando todo esté arriba: `./scripts/restore.sh migracion_20240101`

### Importar desde un WordPress no dockerizado

Si tienes un **.sql** (o .sql.gz) y un **.tar.gz** con **wp-content** de otro servidor:

```bash
docker compose up -d
./scripts/import-external.sh /ruta/al/archivo.sql /ruta/al/wp-content.tar.gz
```

Si la URL del sitio ha cambiado, actualiza las URLs en la base de datos (por ejemplo con WP-CLI o un plugin de búsqueda/reemplazo).

Guía detallada: [docs/importar-backup-externo.md](docs/importar-backup-externo.md).

---

## 🔒 SSL (HTTPS)

### Let's Encrypt con Certbot (en el host)

1. Instalar Certbot (ej. en Ubuntu/Debian: `sudo apt-get install certbot`).
2. Obtener certificados:  
   `sudo certbot certonly --standalone -d tudominio.com -d www.tudominio.com`
3. Copiar certificados al proyecto:  
   `fullchain.pem` y `privkey.pem` en `nginx/certs/`.
4. Configurar el bloque HTTPS en la configuración de Nginx (plantilla o generada) y reiniciar:  
   `docker compose restart nginx`

### Certificados propios

Coloca `fullchain.pem` y `privkey.pem` en `nginx/certs/` y configura el bloque `server` HTTPS en la configuración de Nginx (según tus templates o `wordpress.conf`).

---

## 🛠️ Comandos útiles

### Contenedores

```bash
docker compose up -d          # Arrancar
docker compose stop           # Parar
docker compose down           # Parar y eliminar contenedores
docker compose down -v        # Además eliminar volúmenes (¡borra datos!)
docker compose logs -f        # Logs de todos los servicios
docker compose logs -f wordpress
docker compose restart nginx  # Reiniciar un servicio
docker compose ps             # Estado
```

### Acceso a contenedores

```bash
docker compose exec wordpress bash
docker compose exec db bash
docker compose exec db mysql -u wordpress_user -p wordpress_db
```

### Limpieza

```bash
docker compose down -v
docker image prune
```

---

## 📁 Estructura del proyecto

```
wpdocker/
├── .env.example              # Plantilla → copiar a .env
├── .env                     # Tu configuración (no versionado)
├── docker-compose.yml       # Servicios: db, wordpress, nginx
├── uploads.ini              # Límites PHP (subidas, memoria)
├── backups/                 # No versionado
│   ├── db/                  # .sql.gz
│   └── wp/                  # .tar.gz
├── nginx/
│   ├── templates/           # Plantillas (versionadas)
│   ├── generated/           # Generados por setup.sh (no versionado)
│   ├── conf.d/              # 00-default.conf + wordpress.conf
│   └── certs/               # SSL
├── php-config/
│   ├── opcache.ini
│   └── generated/           # memory.ini (generado)
├── scripts/
│   ├── setup.sh             # Obligatorio antes del primer up
│   ├── test-complete.sh     # Validación opcional
│   ├── detect-resources.sh  # Recomendaciones de recursos
│   ├── backup.sh
│   ├── restore.sh
│   └── import-external.sh   # Importar .sql + wp-content externos
└── themes/
    └── astra-child/
```

---

## 🐛 Solución de problemas

### WordPress no conecta con la base de datos

- Comprueba que los contenedores estén en marcha: `docker compose ps`
- Revisa que `MYSQL_PASSWORD` y `MYSQL_ROOT_PASSWORD` en `.env` coincidan con lo que usa el proyecto
- Revisa logs: `docker compose logs db` y `docker compose logs wordpress`

### Nginx en bucle "Restarting"

- Revisa logs: `docker compose logs nginx`
- Asegúrate de haber ejecutado `./scripts/setup.sh` antes de `docker compose up -d`
- Valida la configuración: `docker compose exec nginx nginx -t`

### Puerto 80 o 443 en uso

En `.env` define otros puertos, por ejemplo:

```env
HTTP_PORT=8080
HTTPS_PORT=8443
```

Luego: `./scripts/setup.sh` y `docker compose up -d`.

### Error al restaurar backup

- Comprueba que existan `backups/db/<nombre>.sql.gz` y `backups/wp/<nombre>.tar.gz`
- El nombre que pasas a `./scripts/restore.sh` debe coincidir con el del backup (sin extensión)

### Permisos en WordPress

```bash
docker compose exec wordpress chown -R www-data:www-data /var/www/html
docker compose exec wordpress chmod -R 755 /var/www/html
```

---

## 🔒 Seguridad

- No subas `.env` a Git.
- Cambia las contraseñas por defecto en producción.
- Usa HTTPS en producción.
- Mantén WordPress y plugins actualizados.
- Haz backups antes de actualizaciones importantes.

---

## 📄 Licencia

Configuración personalizada para WordPress con Docker.

**¿Problemas?** Revisa la sección [Solución de problemas](#-solución-de-problemas) o la documentación de [Docker](https://docs.docker.com/) y [WordPress](https://wordpress.org/support/).
