#!/bin/sh
# Ancoragem USB (gadget ethernet) via cabo USB-C.
#
# Com dr_mode="otg" (padrão do SoC), o controlador só vira "device" (aparece um
# UDC) se a detecção de papel funcionar. Neste aparelho isso não acontecia, então
# tentamos forçar o papel para "device" antes de carregar o g_ether. Se o kernel
# não expuser um usb_role switch, o caminho confiável é o DTB com
# dr_mode="peripheral" (ver extlinux/extlinux.conf.x55-peripheral).
LOG=/boot/usb-gadget.log
[ -d /boot ] || LOG=/var/log/usb-gadget.log
exec >> "$LOG" 2>&1

echo "===== $(date -Is) setup-usb-gadget ====="

modprobe libcomposite 2>/dev/null || true

# 1) Best-effort: força o papel OTG para "device".
for r in /sys/class/usb_role/*/role; do
  [ -e "$r" ] || continue
  echo "usb_role $r: era '$(cat "$r" 2>/dev/null)'; forcando 'device'"
  echo device > "$r" 2>/dev/null || echo "  (nao foi possivel escrever em $r)"
done

# 2) Carrega o g_ether (cria a usb0 quando há UDC disponível).
modprobe g_ether dev_addr=02:00:00:00:00:01 host_addr=02:00:00:00:00:02 || \
  echo "modprobe g_ether falhou"

# 3) Espera o UDC aparecer (até ~10s).
i=0
while [ "$i" -lt 20 ]; do
  [ -n "$(ls /sys/class/udc/ 2>/dev/null)" ] && break
  i=$((i + 1))
  sleep 0.5
done
echo "UDC disponiveis: $(ls /sys/class/udc/ 2>/dev/null || echo '(nenhum)')"
ls -la /sys/class/udc/ 2>&1

# 4) Sobe a usb0 com IP fixo (o PC deve usar 10.55.0.2/24).
if ip link show usb0 >/dev/null 2>&1; then
  ip link set dev usb0 up 2>/dev/null || true
  ip addr add 10.55.0.1/24 dev usb0 2>/dev/null || true
  echo "usb0 configurada:"
  ip -br addr show usb0 2>&1
else
  echo "usb0 NAO existe: o gadget nao ancorou (veja os UDC acima)."
  lsmod | grep -E 'g_ether|u_ether|usb_f_|libcomposite' || echo "(nenhum modulo de gadget)"
fi
