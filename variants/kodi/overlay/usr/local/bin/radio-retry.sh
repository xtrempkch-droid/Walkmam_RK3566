#!/bin/sh
# Rede de seguranca para o RTL8821CS no boot.
#
# Observado no X55: o probe inicial do Wi-Fi pode falhar com timeouts de SDIO
# (erro -110) e o modulo so passar a funcionar depois de recarregado; o
# Bluetooth, idem, as vezes fica sem endereco. Isso roda depois do boot, tenta
# algumas vezes e para assim que os dispositivos aparecem.
#
# O fix "de verdade" e no device tree (sdmmc1 no-mmc/no-sd/sd-uhs-sdr50 e
# uart1 com dma-names), aplicado no build; este script cobre a corrida restante.
LOG=/boot/radio-retry.log
[ -d /boot ] || LOG=/var/log/radio-retry.log
exec >> "$LOG" 2>&1
echo "===== $(date -Is) radio-retry ====="

try_wifi() {
    i=0
    while [ "$i" -lt 3 ]; do
        if [ -e /sys/class/net/wlan0 ]; then
            echo "wlan0 presente (tentativa $i)"
            nmcli dev set wlan0 managed yes >/dev/null 2>&1 || true
            return 0
        fi
        i=$((i + 1))
        echo "wlan0 ausente; recarregando rtw88_8821cs ($i/3)"
        modprobe -r rtw88_8821cs 2>/dev/null || true
        sleep 1
        modprobe rtw88_8821cs 2>/dev/null || true
        sleep 4
    done
    [ -e /sys/class/net/wlan0 ] && return 0
    echo "!!! wlan0 nao apareceu apos 3 tentativas"
    dmesg | grep -iE 'rtw|8821' | tail -10
    return 1
}

try_bt() {
    # Endereco 00:00:00:00:00:00 indica controlador nao inicializado.
    addr=$(cat /sys/class/bluetooth/hci0/address 2>/dev/null)
    if [ -n "$addr" ] && [ "$addr" != "00:00:00:00:00:00" ]; then
        echo "hci0 ok ($addr)"
        return 0
    fi
    echo "hci0 sem endereco; recarregando hci_uart"
    systemctl restart bluetooth >/dev/null 2>&1 || true
    modprobe -r hci_uart 2>/dev/null || true
    sleep 1
    modprobe hci_uart 2>/dev/null || true
    sleep 5
    systemctl restart bluetooth >/dev/null 2>&1 || true
    addr=$(cat /sys/class/bluetooth/hci0/address 2>/dev/null)
    echo "hci0 endereco: ${addr:-ausente}"
    [ -n "$addr" ] && [ "$addr" != "00:00:00:00:00:00" ]
}

# Da tempo de os modulos serem carregados pelo udev no boot.
sleep 5
try_wifi || true
try_bt || true
echo "===== fim ====="
