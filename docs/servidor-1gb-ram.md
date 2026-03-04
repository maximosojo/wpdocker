# WordPress en servidor 1 GB RAM y 2 CPU

## ¿Es rentable usar WordPress con 1 GB de RAM?

**Sí, es posible**, pero está en el **límite mínimo**. En la práctica:

| Escenario | 1 GB RAM | Recomendación |
|-----------|----------|----------------|
| Sitio muy bajo tráfico, pocos plugins, tema ligero | Viable con configuración estricta | Aceptable |
| Sitio con tráfico moderado o varios plugins | Inestable, cuelgues, 502/504 | Mejor 2 GB |
| Cliente que paga hosting “profesional” | Riesgo de quejas y reinicios constantes | **Recomendable 2 GB** |

Con **swap** se pueden absorber picos, pero el swap no sustituye la RAM: si el sistema usa swap de forma continua, el servidor irá lento y puede colgarse.

**Conclusión:** Para un cliente es más rentable ofrecer al menos **2 GB RAM** y evitar soporte y reinicios. 1 GB sirve para desarrollo, pruebas o sitios muy sencillos.

---

## Por qué se colgaba tu servidor: sobreasignación de memoria

En un servidor con **1 GB = 1024 MB** de RAM, el sistema operativo, el kernel y Docker ya consumen parte. Si asignas a los contenedores **más** de lo que hay, el sistema:

1. Usa swap masivamente → todo va muy lento  
2. El kernel mata procesos (OOM Killer) → MySQL o PHP caen  
3. Docker reinicia contenedores → “tengo que reiniciar Docker a cada rato”

En tu `.env` tenías (ejemplo):

- MySQL: **460 MB**
- WordPress: **450 MB**
- Nginx: **360 MB**  
- **Total: 1270 MB** → **por encima de 1 GB**

Además, `NGINX_WORKER_PROCESSES=10` en un equipo de 2 CPUs hace que Nginx use más memoria (varios workers) sin ganar rendimiento.

Por eso el sitio iba lento y se quedaba colgado.

---

## Valores correctos para 1 GB RAM + 2 CPU (con swap)

La suma de los **límites** de los tres contenedores debe quedar **por debajo de 1 GB** (por ejemplo ~740 MB), dejando el resto para el sistema y picos.

Perfil recomendado para **1 GB**:

| Servicio   | Límite RAM | Límite CPU | Motivo |
|------------|------------|------------|--------|
| MySQL      | 360 M      | 0.8        | Mínimo para que arranque estable |
| WordPress  | 300 M      | 0.8        | PHP + Apache; suficiente para pocas peticiones |
| Nginx      | 80 M       | 0.5        | Proxy ligero |
| **Total**  | **740 M**  | —          | Deja ~280 M para sistema + picos |

Además:

- **NGINX_WORKER_PROCESSES=2** (no 10): 1 worker por CPU.
- **MYSQL_INNODB_BUFFER_POOL_SIZE=160M** (no más en 1 GB).
- **PHP_MEMORY_LIMIT=160M** (dentro del límite del contenedor WP).
- Reservas bajas para no “reservar” más de lo que cabe.

Con swap (por ejemplo 512 MB–1 GB), los picos ocasionales se pueden absorber sin que el servidor se caiga, pero el uso normal debe caber en RAM.

---

## Qué hacer ahora

1. **Sustituir el `.env`** por un perfil para 1 GB (o pegar solo las variables de recursos).  
2. **Regenerar configuración y reiniciar:**
   ```bash
   ./scripts/setup.sh
   docker compose down
   docker compose up -d
   ```
3. **Comprobar** que no haya OOM ni reinicios:
   ```bash
   docker compose ps
   free -h
   ```

Si aun así el sitio va muy lento o sigue inestable con tráfico real, la opción viable es **subir a 2 GB RAM**.

---

## Cuándo recomendar un servidor mejor

Conviene recomendar **al menos 2 GB RAM** si:

- El cliente espera un sitio “profesional” y estable.
- Hay varios plugins (WooCommerce, formularios, seguridad, etc.).
- El tráfico no es trivial (varias visitas simultáneas).
- Quieres evitar soporte por cuelgues y reinicios.

En 2 GB puedes usar límites más holgados (por ejemplo MySQL 512M, WP 512M, Nginx 128M) y el mismo stack será mucho más estable sin tocar tanto el .env.
