#!/bin/sh
set -eu

export HOME=/root
: "${XDG_RUNTIME_DIR:=/run/kodi-wayland}"
export XDG_RUNTIME_DIR
export WAYLAND_DISPLAY=wayland-0

# Sobrescrevíveis para teste; em produção ficam nos padrões.
KODI_BIN=${KODI_BIN:-/usr/bin/kodi}
WESTON_LOG=${WESTON_LOG:-/var/log/weston.log}
WALKMAM_CONF=${WALKMAM_CONF:-/boot/walkmam.conf}

# Rotação da saída DSI-1. Valores aceitos pelo Weston (man weston.ini):
#   normal rotate-90 rotate-180 rotate-270
#   flipped flipped-rotate-90 flipped-rotate-180 flipped-rotate-270
# O valor vem de "display_transform=<valor>" em walkmam.conf, que fica na
# partição FAT (BOOT) e pode ser editado no PC sem recompilar a imagem.
read_transform() {
    value=
    if [ -r "$WALKMAM_CONF" ]; then
        value=$(sed -n 's/^[[:space:]]*display_transform[[:space:]]*=[[:space:]]*//p' "$WALKMAM_CONF" \
            | tail -n 1 | tr -d '\r[:space:]')
    fi
    case "$value" in
        normal|rotate-90|rotate-180|rotate-270|\
        flipped|flipped-rotate-90|flipped-rotate-180|flipped-rotate-270)
            printf '%s\n' "$value"
            ;;
        "")
            printf 'normal\n'
            ;;
        *)
            echo "display_transform inválido em $WALKMAM_CONF: '$value'. Usando 'normal'." >&2
            printf 'normal\n'
            ;;
    esac
}

TRANSFORM=$(read_transform)
echo "Weston: DSI-1 transform=$TRANSFORM (fonte: $WALKMAM_CONF)" >&2

mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"
rm -f "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY.lock"

WESTON_INI="$XDG_RUNTIME_DIR/weston.ini"
cat > "$WESTON_INI" << EOF_INI
[core]
shell=kiosk-shell.so
idle-time=0

[output]
name=DSI-1
transform=$TRANSFORM
EOF_INI

weston --backend=drm-backend.so --tty=1 --idle-time=0 \
    --config="$WESTON_INI" --log="$WESTON_LOG" &
weston_pid=$!

cleanup() {
    kill "$weston_pid" 2>/dev/null || true
    wait "$weston_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

attempt=0
while [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; do
    if ! kill -0 "$weston_pid" 2>/dev/null; then
        set +e
        wait "$weston_pid"
        weston_status=$?
        set -e
        echo "Weston exited before creating its Wayland socket." >&2
        echo "Weston exit status: $weston_status" >&2
        if [ -r "$WESTON_LOG" ]; then
            cat "$WESTON_LOG" >&2
        fi
        exit 1
    fi
    if [ "$attempt" -ge 30 ]; then
        echo "Timed out waiting for Weston's Wayland socket." >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 1
done

"$KODI_BIN" --standalone --windowing=wayland
