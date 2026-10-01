#!/bin/sh
sleep 15
OUT=/boot/diagnostico.txt
{
  echo "===== $(date) ====="
  echo
  echo "----- /proc/cmdline (imagem e parametros de boot) -----"
  cat /proc/cmdline
  echo
  echo "----- nós de entrada do device tree em uso -----"
  for node in rocknix-joypad gpio-keys-gamepad adc-joystick; do
    path="/proc/device-tree/$node"
    if [ -d "$path" ]; then
      printf '%s: ' "$node"
      tr '\000' ' ' < "$path/compatible"
      echo
    fi
  done
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
  echo "----- systemctl status kodi -----"
  systemctl status kodi.service --no-pager -l
  echo
  echo "----- journalctl -b -u kodi (ultimas 100 linhas) -----"
  journalctl -b -u kodi -n 100 --no-pager
  echo
  echo "----- /var/log/weston.log (compositor DRM/Wayland) -----"
  cat /var/log/weston.log 2>&1 || echo "(arquivo não existe ainda)"
  echo
  echo "----- dispositivos DRM -----"
  ls -la /dev/dri/ 2>&1
  echo
  echo "----- /root/.kodi/temp/kodi.log (log interno do Kodi) -----"
  cat /root/.kodi/temp/kodi.log 2>&1 || echo "(arquivo não existe ainda)"
} > "$OUT" 2>&1
