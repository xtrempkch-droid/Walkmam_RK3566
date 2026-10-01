#!/bin/sh
sleep 15
OUT=/boot/diagnostico.txt
{
  echo "===== $(date) ====="
  echo
  echo "----- dmesg (log do kernel) -----"
  dmesg
  echo
  echo "----- /proc/bus/input/devices (botoes/analogico) -----"
  cat /proc/bus/input/devices
  echo
  echo "----- lsmod (modulos carregados) -----"
  lsmod
  echo
  echo "----- /sys/class/udc (controlador USB em modo gadget) -----"
  ls -la /sys/class/udc/ 2>&1
  echo
  echo "----- ip addr (interfaces de rede) -----"
  ip addr
  echo
  echo "----- journalctl -u kodi (ultimas 100 linhas) -----"
  journalctl -u kodi -n 100 --no-pager
  echo
  echo "----- /root/.kodi/temp/kodi.log (log interno do Kodi, GBM/DRM) -----"
  cat /root/.kodi/temp/kodi.log 2>&1 || echo "(arquivo não existe ainda)"
} > "$OUT" 2>&1
