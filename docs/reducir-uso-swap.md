# Reducir uso de SWAP para que el sitio no se vuelva lento

Si ves que el servidor ya escribe en SWAP con solo ~900 MB de 2 GB usados, el kernel está intercambiando memoria demasiado pronto (por el valor de **swappiness**). Eso hace todo más lento.

## Bajar la swappiness (recomendado)

En el **servidor** (como root o con sudo):

```bash
# Ver valor actual (suele ser 60)
cat /proc/sys/vm/swappiness

# Ponerlo en 10: solo usar swap cuando falte RAM de verdad
sudo sysctl vm.swappiness=10

# Hacerlo permanente (Debian/Ubuntu)
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

Con `swappiness=10` el sistema usará mucho menos swap y mantendrá más datos en RAM, así el sitio responde más rápido.

## No bajar los límites de los contenedores

En un servidor de 2 GB, **no** conviene bajar mucho los límites (p. ej. 400M MySQL, 400M WP) para “ahorrar RAM”: MySQL y PHP se quedan cortos y aparecen 502 y lentitud. El perfil estable es:

- MySQL: 512M, WordPress: 512M, Nginx: 128M (~1.15 GB total).

Para reducir el uso de swap sin empeorar el sitio, lo correcto es **bajar swappiness** (arriba), no quitarle RAM a los contenedores.
