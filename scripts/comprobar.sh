#!/usr/bin/env bash

# Comprobaciones de la AE6
# Si cambia la IP de dpl-lab se puede ejecutar:
# IP_DPL_LAB=otra_ip ./comprobar.sh

set -u

IP_DPL_LAB="${IP_DPL_LAB:-172.18.0.2}"
BASE_DN="dc=dpl,dc=local"
USER_DN="uid=alumno,ou=usuarios,${BASE_DN}"
USER_PASSWORD="${USER_PASSWORD:-CAMBIAR_ESTO}"
ZONE_FILE="/etc/bind/db.dpl.local"

FALLOS=0

ok() {
    echo "[OK]   $1"
}

fallo() {
    echo "[FALLO] $1"
    FALLOS=$((FALLOS + 1))
}

echo "== DNS =="

docker exec dpl-lab named-checkconf \
    && ok "named-checkconf" \
    || fallo "named-checkconf"

docker exec dpl-lab named-checkzone dpl.local "$ZONE_FILE" | grep -q "OK" \
    && ok "zona dpl.local válida" \
    || fallo "zona dpl.local"

docker exec dpl-lab pgrep -a named >/dev/null \
    && ok "named activo" \
    || fallo "named no está activo"

for nombre in www.dpl.local app.dpl.local; do
    ip="$(docker exec dpl-cliente dig +short "@${IP_DPL_LAB}" "$nombre" A)"

    if [ -n "$ip" ]; then
        ok "$nombre -> $ip"
    else
        fallo "$nombre no resuelve"
    fi
done

docker exec dpl-cliente grep -q "dpl.local" /etc/hosts \
    && fallo "hay entradas dpl.local en /etc/hosts" \
    || ok "sin entradas dpl.local en /etc/hosts"


echo
echo "== Directorio LDAP =="

docker exec dpl-lab pgrep -a slapd >/dev/null \
    && ok "slapd activo" \
    || fallo "slapd no está activo"

docker exec dpl-lab ldapsearch -x -LLL \
    -b "$BASE_DN" "(uid=alumno)" dn | grep -q "dn:" \
    && ok "usuario alumno encontrado" \
    || fallo "usuario alumno no encontrado"

docker exec dpl-cliente ldapwhoami -x \
    -H "ldap://${IP_DPL_LAB}" \
    -D "$USER_DN" \
    -w "$USER_PASSWORD" | grep -q "dn:" \
    && ok "autenticación LDAP correcta" \
    || fallo "autenticación LDAP correcta rechazada"

docker exec dpl-cliente ldapwhoami -x \
    -H "ldap://${IP_DPL_LAB}" \
    -D "$USER_DN" \
    -w "incorrecta" >/dev/null 2>&1 \
    && fallo "LDAP ha aceptado una contraseña incorrecta" \
    || ok "LDAP rechaza la contraseña incorrecta"


echo
echo "== Integración =="

docker exec dpl-cliente curl -s -o /dev/null -w '%{http_code}' \
    http://www.dpl.local | grep -q '^200$' \
    && ok "Web por nombre (200)" \
    || fallo "Web por nombre"

docker exec dpl-cliente curl -s \
    http://app.dpl.local:8000/api/mensaje | grep -q '"mensaje"' \
    && ok "aplicación por nombre" \
    || fallo "aplicación por nombre"

docker exec dpl-cliente curl -s -o /dev/null -w '%{http_code}' \
    -X POST \
    -d "usuario=alumno&password=${USER_PASSWORD}" \
    http://www.dpl.local/api/login | grep -q '^200$' \
    && ok "login LDAP correcto (200)" \
    || fallo "login LDAP correcto"

docker exec dpl-cliente curl -s -o /dev/null -w '%{http_code}' \
    -X POST \
    -d "usuario=alumno&password=incorrecta" \
    http://www.dpl.local/api/login | grep -q '^401$' \
    && ok "login LDAP incorrecto rechazado (401)" \
    || fallo "login LDAP incorrecto"


echo

if [ "$FALLOS" -eq 0 ]; then
    echo "Resultado: todas las comprobaciones han pasado."
    exit 0
else
    echo "Resultado: $FALLOS comprobación(es) fallida(s)."
    exit 1
fi
