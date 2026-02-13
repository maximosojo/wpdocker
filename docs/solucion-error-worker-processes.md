# Solución: Error "invalid number of arguments in worker_processes directive"

## Problema
Nginx falla con el error:
```
nginx: [emerg] invalid number of arguments in "worker_processes" directive in /etc/nginx/nginx.conf:4
```

## Causa
El archivo `nginx/generated/nginx.conf` tenía variables sin sustituir (`${NGINX_WORKER_PROCESSES}`) porque `envsubst` no tenía acceso a las variables exportadas.

## Solución implementada

### 1. Mejoras en `setup.sh`
- **Exportación explícita de variables**: Las variables se exportan antes de usar `envsubst`
- **Validación post-generación**: Se verifica que no queden variables sin sustituir
- **Eliminación previa**: Se elimina el archivo existente antes de generar para evitar conflictos

### 2. Mejoras en `init-generated-files.sh`
- **Validación de archivos por defecto**: Se verifica que los archivos `.default` no tengan variables sin sustituir antes de copiarlos

### 3. Script de prueba completo
- Se creó `scripts/test-complete.sh` para validar todo el flujo antes de desplegar

## Pasos para aplicar en el servidor

```bash
# 1. Actualizar el proyecto
cd /ruta/al/proyecto
git pull  # o copiar los archivos nuevos

# 2. Limpiar archivos generados antiguos
rm -rf nginx/generated/*.conf php-config/generated/*.ini

# 3. Ejecutar script de inicialización
./scripts/init-generated-files.sh

# 4. Generar configuración desde .env
./scripts/setup.sh

# 5. Validar que los archivos están correctos
head -5 nginx/generated/nginx.conf
# Debe mostrar: worker_processes 2; (o el valor de tu .env)
# NO debe mostrar: worker_processes ${NGINX_WORKER_PROCESSES};

# 6. Verificar que no hay variables sin sustituir
grep -c '\${' nginx/generated/nginx.conf
# Debe devolver: 0

# 7. Reiniciar servicios
docker compose down
docker compose up -d

# 8. Verificar logs
docker compose logs nginx | tail -20
# NO debe aparecer el error "invalid number of arguments"
```

## Verificación

Después de aplicar los cambios:

```bash
# Estado de contenedores (todos deben estar "Up")
docker compose ps

# Logs de Nginx (no debe haber errores)
docker compose logs nginx | grep -i error

# Validar sintaxis dentro del contenedor
docker compose exec nginx nginx -t

# Verificar acceso web
curl -I http://localhost/
```

## Si sigue fallando

1. **Verificar que setup.sh se ejecutó correctamente**:
   ```bash
   bash -x scripts/setup.sh 2>&1 | grep -E "(envsubst|sed|Generado)"
   ```

2. **Verificar contenido del archivo generado**:
   ```bash
   cat nginx/generated/nginx.conf | head -10
   ```

3. **Verificar variables en .env**:
   ```bash
   grep NGINX_WORKER .env
   ```

4. **Regenerar manualmente si es necesario**:
   ```bash
   export NGINX_WORKER_PROCESSES=2
   export NGINX_WORKER_CONNECTIONS=512
   envsubst '\$NGINX_WORKER_PROCESSES \$NGINX_WORKER_CONNECTIONS' < nginx/templates/nginx.conf.template > nginx/generated/nginx.conf
   ```

## Prevención

Siempre ejecuta `./scripts/test-complete.sh` antes de desplegar para validar que todo está correcto.
