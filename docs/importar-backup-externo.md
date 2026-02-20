# Importar backup desde un WordPress no dockerizado

Si tienes un archivo **.sql** (o .sql.gz) de la base de datos y un **.tar.gz** con la carpeta **wp-content** de un servidor anterior, puedes importarlos en este WordPress dockerizado.

## Requisitos previos

1. **Proyecto ya configurado y corriendo**
   ```bash
   cp .env.example .env
   # Editar .env: DOMAIN, MYSQL_ROOT_PASSWORD, MYSQL_PASSWORD
   ./scripts/setup.sh
   docker compose up -d
   ```

2. **Tener los archivos a mano**
   - Un export de la base de datos: `sitio_antiguo.sql` o `sitio_antiguo.sql.gz`
   - Un comprimido con wp-content: `wp-content.tar.gz` (puede ser la carpeta `wp-content` completa o solo su contenido: plugins, themes, uploads, etc.)

## Pasos rápidos

### 1. Colocar los archivos

Puedes poner los archivos en la raíz del proyecto o en `backups/`:

```bash
# Ejemplo: en la raíz
/path/to/wpdocker/mi_backup.sql
/path/to/wpdocker/wp-content.tar.gz

# O en backups
/path/to/wpdocker/backups/db/mi_backup.sql.gz
/path/to/wpdocker/backups/wp/wp-content.tar.gz
```

### 2. Ejecutar el script de importación

```bash
./scripts/import-external.sh <archivo.sql o .sql.gz> <archivo_wp-content.tar.gz>
```

**Ejemplos:**

```bash
# SQL sin comprimir y wp-content en la raíz
./scripts/import-external.sh mi_backup.sql wp-content.tar.gz

# SQL comprimido y archivos en backups/
./scripts/import-external.sh backups/db/export.sql.gz backups/wp/wp-content.tar.gz

# Con rutas absolutas
./scripts/import-external.sh /home/user/backups/sitio.sql.gz /home/user/backups/wp-content.tar.gz
```

### 3. Actualizar URLs (si el sitio antiguo tenía otro dominio)

Si el sitio anterior usaba por ejemplo `https://misitio.com` y ahora usas `http://localhost` (o tu nuevo dominio), hay que actualizar las URLs en la base de datos.

**Opción A – WP-CLI dentro del contenedor (recomendado):**

```bash
# Reemplazar URL antigua por la nueva
docker compose exec wordpress wp search-replace 'https://misitio.com' 'http://localhost' --all-tables --allow-root

# Si también tenías www
docker compose exec wordpress wp search-replace 'https://www.misitio.com' 'http://localhost' --all-tables --allow-root
```

Si la imagen no trae WP-CLI, puedes instalar el plugin **Better Search Replace** desde el panel de WordPress y usarlo para buscar y reemplazar las URLs.

**Opción B – Plugin desde el panel**

- Instalar un plugin de búsqueda y reemplazo de URLs (ej. Better Search Replace, WP Migrate DB).
- Ejecutar el reemplazo de la URL antigua por la nueva (por ejemplo la que tengas en `DOMAIN` en tu `.env`).

### 4. Revisar en el navegador

- Abre `http://localhost` (o tu `DOMAIN`).
- Comprueba la web y el escritorio.
- Revisa que medios, temas y plugins se vean correctos.

## Formato del .tar.gz de wp-content

El script admite dos formatos:

1. **El .tar.gz contiene una carpeta `wp-content`**  
   Al descomprimir se ve algo como: `wp-content/plugins/`, `wp-content/themes/`, `wp-content/uploads/`.  
   El script detecta esa carpeta y copia solo su contenido al `wp-content` del contenedor.

2. **El .tar.gz contiene directamente el contenido de wp-content**  
   Al descomprimir se ve: `plugins/`, `themes/`, `uploads/`.  
   El script copia todo eso dentro de `wp-content/` del contenedor.

## Base de datos: nombre y usuario

En el `.env` de este proyecto se usan por defecto:

- Base de datos: `wordpress_db`
- Usuario: `wordpress_user`

El script importa el .sql en la base de datos definida en `MYSQL_DATABASE` del `.env`.  
Si tu export antiguo fue de otra base (por ejemplo `wp_misitio`), no hace falta renombrarla: se importan las tablas en la base actual. Solo asegúrate de que el .sql no cree ni use otra base de datos si quieres que todo quede en la misma que usa este proyecto. Si tu .sql tiene al inicio `CREATE DATABASE ...; USE otra_base;`, puedes editarlo y quitar o cambiar esas líneas para que todo quede en la base de este proyecto.

## Si algo falla

- **Error al importar la base de datos**  
  - Comprueba que el contenedor de MySQL esté en marcha: `docker compose ps`  
  - Comprueba usuario y contraseña en `.env` (MYSQL_ROOT_PASSWORD, MYSQL_PASSWORD, MYSQL_DATABASE).

- **El sitio muestra la URL antigua o enlaces rotos**  
  - Haz el reemplazo de URLs (WP-CLI o plugin) como en el paso 3.

- **Faltan plugins o temas**  
  - Verifica que el .tar.gz de wp-content incluya `plugins/` y `themes/` (o `wp-content/plugins/` y `wp-content/themes/`).  
  - Vuelve a ejecutar el script de importación si fue necesario regenerar el .tar.gz.

- **Permisos o errores 500**  
  - El script ya ejecuta `chown -R www-data:www-data wp-content` dentro del contenedor.  
  - Si usas el volumen `./themes` para un tema hijo, asegúrate de que el tema esté ahí y que no entre en conflicto con lo que importaste en `wp-content/themes`.

## Resumen de comandos

```bash
# 1. Servicios levantados
docker compose up -d

# 2. Importar
./scripts/import-external.sh mi_backup.sql wp-content.tar.gz

# 3. (Opcional) Cambiar URLs
docker compose exec wordpress wp search-replace 'https://url-antigua.com' 'http://tu-dominio' --all-tables --allow-root

# 4. Revisar
docker compose logs -f wordpress
```
