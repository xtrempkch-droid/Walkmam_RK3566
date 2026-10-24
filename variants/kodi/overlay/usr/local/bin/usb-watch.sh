#!/bin/sh
# Registra o que o kernel vê quando o cabo USB é plugado/desplugado.
#
# Motivo: no X35H o PC não acusa NEM "dispositivo desconhecido", ou seja, não há
# enumeração no fio. Isso pode ser (a) porta só de carga, (b) dados ligados a
# outro controlador/PHY, (c) cabo só de carga, ou (d) VBUS não detectado. Sem
# evidência é chute, então este script grava um retrato a cada mudança e as
# últimas linhas do dmesg no instante da mudança.
#
# Saída: /boot/usb-watch.log (partição FAT, lê-se no PC).
LOG=/boot/usb-watch.log
[ -d /boot ] && [ -w /boot ] || LOG=/var/log/usb-watch.log
# Log por boot: trunca para não crescer sem limite no cartão.
: > "$LOG"
exec >> "$LOG" 2>&1

echo "===== $(date -Is) usb-watch iniciado ====="
echo "modelo: $(tr -d '\000' < /proc/device-tree/model 2>/dev/null)"
echo "dr_mode ativo: $(cat /proc/device-tree/usb@fcc00000/dr_mode 2>/dev/null || echo '?')"

retrato() {
    echo "--- $(date -Is) ---"
    echo -n "udc: "
    ls /sys/class/udc/ 2>/dev/null | tr '\n' ' '; echo
    for f in /sys/class/udc/*/state; do
        [ -e "$f" ] || continue
        printf '  %s = %s\n' "$f" "$(cat "$f" 2>/dev/null)"
    done
    for f in /sys/class/usb_role/*/role; do
        [ -e "$f" ] || continue
        printf '  %s = %s\n' "$f" "$(cat "$f" 2>/dev/null)"
    done
    # Dispositivos vistos no barramento USB (vazio = nada enumerado).
    echo -n "  dispositivos usb: "
    ls /sys/bus/usb/devices/ 2>/dev/null | grep -v '^usb[0-9]*$' | tr '\n' ' '
    echo
    # Alimentação: se plugar o cabo muda isto, há VBUS na porta.
    for ps in /sys/class/power_supply/*/; do
        [ -e "$ps/online" ] || continue
        printf '  %sonline = %s' "$ps" "$(cat "$ps/online" 2>/dev/null)"
        [ -e "$ps/status" ] && printf ' status = %s' "$(cat "$ps/status" 2>/dev/null)"
        echo
    done
}

# Impressão digital do estado: muda quando algo é plugado.
impressao() {
    {
        ls /sys/class/udc/ 2>/dev/null
        cat /sys/class/udc/*/state 2>/dev/null
        cat /sys/class/usb_role/*/role 2>/dev/null
        ls /sys/bus/usb/devices/ 2>/dev/null
        cat /sys/class/power_supply/*/online 2>/dev/null
    } 2>/dev/null | md5sum | cut -d' ' -f1
}

anterior=$(impressao)
retrato

# 5 minutos é suficiente para plugar/desplugar; depois o serviço encerra para
# não escrever no cartão para sempre.
i=0
while [ "$i" -lt 150 ]; do
    sleep 2
    i=$((i + 1))
    atual=$(impressao)
    if [ "$atual" != "$anterior" ]; then
        echo ">>> MUDANCA detectada em $(date -Is)"
        retrato
        echo "--- ultimas linhas do dmesg neste instante ---"
        dmesg | tail -n 40
        echo "--- fim ---"
        anterior=$atual
    fi
done

echo "===== $(date -Is) usb-watch encerrado (5 min) ====="
retrato
