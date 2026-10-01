#!/bin/sh
set -eu

export HOME=/root
export XDG_RUNTIME_DIR=/run/kodi-wayland
export WAYLAND_DISPLAY=wayland-0

mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"
rm -f "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY.lock"

weston --backend=drm-backend.so --tty=1 --idle-time=0 --log=/var/log/weston.log &
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
        if [ -r /var/log/weston.log ]; then
            cat /var/log/weston.log >&2
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

/usr/bin/kodi --standalone --windowing=wayland
