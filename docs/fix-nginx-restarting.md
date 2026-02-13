# Solución: Nginx en bucle de reinicio

## Problema
Nginx se reiniciaba continuamente porque los archivos de configuración (`nginx/generated/nginx.conf`, `nginx/generated/wordpress.conf`) no existían cuando Docker intentaba montarlos.

## Solución implementada

1. **Archivos por defecto**: Se crearon archivos `.default` que siempre existen y se pueden usar como respaldo:
   - `nginx/generated/nginx.conf.default`
   - `nginx/generated/wordpress.conf.default`
   - `php-config/generated/memory.ini.default`

2. **Script de inicialización**: Se creó `scripts/init-generated-files.sh` que copia automáticamente los archivos por defecto si los generados no existen.

3. **Integración en setup.sh**: `setup.sh` ahora llama automáticamente a `init-generated-files.sh` al inicio, asegurando que los archivos siempre existan.

## Pasos para aplicar en el servidor

```bash
# 1. Actualizar el proyecto (pull o copiar cambios)
cd /ruta/al/proyecto
git pull  # o copiar los archivos nuevos

# 2. Asegurar que los archivos generados existan
./scripts/init-generated-files.sh

# 3. Regenerar configuración desde .env (importante: usa tu dominio y configuración)
./scripts/setup.sh

# 4. Verificar que los archivos se generaron correctamente
ls -la nginx/generated/*.conf php-config/generated/*.ini

# 5. Reiniciar servicios
docker compose down
docker compose up -d

# 6. Verificar que Nginx arrancó correctamente
docker compose ps
docker compose logs nginx | tail -20
```

## Verificación

Después de aplicar los cambios, verifica:

```bash
# Estado de contenedores (todos deben estar "Up", no "Restarting")
docker compose ps

# Logs de Nginx (no debe haber errores de "Read-only file system" o "not found")
docker compose logs nginx | grep -i error

# Validar sintaxis de configuración (si nginx está disponible en el host)
docker compose exec nginx nginx -t
```

## Si sigue fallando

1. Verifica que los archivos existen:
   ```bash
   ls -la nginx/generated/ php-config/generated/
   ```

2. Verifica permisos:
   ```bash
   chmod 755 nginx/generated php-config/generated
   chmod 644 nginx/generated/*.conf php-config/generated/*.ini
   ```

3. Verifica que `.env` tiene los valores correctos:
   ```bash
   grep -E "DOMAIN|NGINX_WORKER" .env
   ```

4. Revisa logs completos:
   ```bash
   docker compose logs nginx
   ```
