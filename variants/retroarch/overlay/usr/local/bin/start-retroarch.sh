#!/bin/sh
# Sessão gráfica do RetroArch no tty1 (variante "retroarch" = versão de jogos).
#
# Mesmo desenho do launcher do Kodi: Weston (backend DRM, kiosk) aplica a rotação
# e o RetroArch roda em Wayland por cima. Se o Weston não subir, tenta o driver
# KMS/DRM do próprio RetroArch (sem compositor). O motivo de qualquer falha
# aparece NA TELA (tty1) e em /boot/retroarch-start.log, sem precisar de SSH.
set -eu

export HOME=/root

RETROARCH_BIN=${RETROARCH_BIN:-/usr/bin/retroarch}
RETROARCH_CFG=${RETROARCH_CFG:-/root/.config/retroarch/retroarch.cfg}
RETROARCH_LOG=${RETROARCH_LOG:-/boot/retroarch-start.log}

# Rotação e start do Weston vêm do helper compartilhado (fonte canônica).
. /usr/local/share/walkmam/display.sh

TRANSFORM=$(walkmam_read_transform)

_log_dir=$(dirname "$RETROARCH_LOG")
if [ ! -d "$_log_dir" ] || [ ! -w "$_log_dir" ]; then
    RETROARCH_LOG=/var/log/retroarch-start.log
fi

echo "===== $(date -Is) start-retroarch (transform=$TRANSFORM) =====" >> "$RETROARCH_LOG"

if [ ! -x "$RETROARCH_BIN" ]; then
    walkmam_say_tty "RETROARCH: binário não encontrado em $RETROARCH_BIN"
    echo "binário ausente: $RETROARCH_BIN" >> "$RETROARCH_LOG"
    exit 1
fi

# --config explícito: o serviço roda como root com HOME=/root, e o padrão do
# RetroArch é ~/.config/retroarch/retroarch.cfg. Ser explícito evita "abriu com
# a configuração errada" quando o HOME muda.
set -- --config "$RETROARCH_CFG"
if [ -n "${WALKMAM_ROM:-}" ]; then
    set -- "$@" "$WALKMAM_ROM"
fi

ok=0

# Tentativa 1: Weston (Wayland) — é o caminho que aplica a rotação.
if walkmam_start_weston "$TRANSFORM" "$RETROARCH_LOG"; then
    echo "Weston pronto; iniciando RetroArch (video_driver=wayland)" >> "$RETROARCH_LOG"
    set +e
    "$RETROARCH_BIN" "$@" >> "$RETROARCH_LOG" 2>&1
    status=$?
    set -e
    echo "RetroArch (wayland) terminou com status $status" >> "$RETROARCH_LOG"
    [ "$status" -eq 0 ] && ok=1
else
    walkmam_say_tty "RETROARCH: Weston falhou. Veja /boot/retroarch-start.log. Tentando KMS/DRM direto..."
fi
walkmam_stop_weston

# Tentativa 2: KMS/DRM direto, sem compositor. Dá um tempo para o DRM ser
# liberado pelo Weston antes de o RetroArch tentar pegá-lo; sem isso ele
# reclama que o dispositivo está ocupado.
if [ "$ok" -eq 0 ]; then
    sleep 3
    walkmam_say_tty "RETROARCH: tentando video_driver=drm (sem Weston)..."
    # Como trocar o driver aqui: o RetroArch 1.14 NÃO tem a opção
    # --video-driver (ela apareceu em versões posteriores). O jeito que existe é
    # um arquivo com --appendconfig, que é aplicado depois do --config e vence.
    # Identificadores no 1.14: driver "drm" (no 1.17+ virou "kmsdrm") e contexto
    # "kms". Ver docs/variantes.md.
    _cfg_extra="$XDG_RUNTIME_DIR/retroarch-drm.cfg"
    mkdir -p "$XDG_RUNTIME_DIR"
    cat > "$_cfg_extra" << EOF_EXTRA
video_driver = "drm"
video_context_driver = "kms"
EOF_EXTRA
    set +e
    "$RETROARCH_BIN" "$@" --appendconfig "$_cfg_extra" >> "$RETROARCH_LOG" 2>&1
    status=$?
    set -e
    echo "RetroArch (drm) terminou com status $status" >> "$RETROARCH_LOG"
    [ "$status" -eq 0 ] && ok=1
fi

# Sair do RetroArch pelo menu é uma saída normal (status 0). Se nada rodou,
# explica na tela em vez de deixar o usuário numa tela preta sem motivo.
if [ "$ok" -eq 0 ]; then
    walkmam_say_tty "RETROARCH NAO ABRIU (veja /boot/retroarch-start.log)"
    exit 1
fi

exit 0
