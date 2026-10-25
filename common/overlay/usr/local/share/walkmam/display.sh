# Funções de display compartilhadas entre as variantes (Kodi, RetroArch, ...).
#
# Fonte canônica da rotação e do start do Weston. Nasceu porque a rotação é a
# maior fonte de bug deste projeto: existem TRÊS camadas que giram coisas
# diferentes (ver docs/hardware-e-drivers.md, seção 3.1):
#
#   1. `rotation = <270>` no nó do painel (DTS)  -> sentido físico do painel
#   2. `transform=` na saída do Weston           -> gira a sessão gráfica
#   3. o app (Kodi/RetroArch)                    -> herda a saída já girada
#
# Este arquivo cuida da camada 2. Uso:
#
#   . /usr/local/share/walkmam/display.sh
#   TRANSFORM=$(walkmam_read_transform)          # auto/normal/rotate-90/...
#   walkmam_start_weston "$TRANSFORM" "$LOG"     # 0 = pronto, 1 = falhou
#   walkmam_rotated_size "$TRANSFORM"            # tamanho da tela já girada
#   ... roda o app em $WAYLAND_DISPLAY ...
#   walkmam_stop_weston

# Diretório do socket Wayland. Separado por variante para que Kodi e RetroArch
# nunca disputem o mesmo socket se alguém rodar os dois.
: "${WALKMAM_RUNTIME_DIR:=/run/walkmam-wayland}"
: "${WALKMAM_WAYLAND_DISPLAY:=wayland-0}"
: "${WALKMAM_CONF:=/boot/walkmam.conf}"

walkmam_say_tty() {
    { printf '\033[2J\033[H'; printf '%s\n' "$*"; } > /dev/tty1 2>/dev/null || true
    printf '%s\n' "$*" >&2
}

# Rotação padrão por modelo, lida do device tree em uso. A X55 tem painel
# 720x1280 montado deitado (precisa de rotate-90); X35S/X35H tem painel
# 640x480 e ficam em "normal".
walkmam_transform_from_model() {
    _modelo=
    if [ -r /proc/device-tree/model ]; then
        _modelo=$(tr -d '\000' < /proc/device-tree/model 2>/dev/null | tr 'A-Z' 'a-z')
    fi
    case "$_modelo" in
        *x55*) printf 'rotate-90\n' ;;
        *)     printf 'normal\n' ;;
    esac
}

# Rotação efetiva: "display_transform=" de walkmam.conf (partição FAT, editável
# no PC). "auto", vazio ou valor inválido caem no padrão do modelo.
walkmam_read_transform() {
    _valor=
    if [ -r "$WALKMAM_CONF" ]; then
        _valor=$(sed -n 's/^[[:space:]]*display_transform[[:space:]]*=[[:space:]]*//p' "$WALKMAM_CONF" \
            | tail -n 1 | tr -d '\r[:space:]')
    fi
    case "$_valor" in
        normal|rotate-90|rotate-180|rotate-270|\
        flipped|flipped-rotate-90|flipped-rotate-180|flipped-rotate-270)
            printf '%s\n' "$_valor"
            ;;
        *)
            walkmam_transform_from_model
            ;;
    esac
}

# Tamanho NATIVO da saída conectada, lido do DRM: "<largura> <altura>", sem
# rotação (é o que o painel reporta, ex.: "720 1280" na X55). "0 0" = não achou.
# WALKMAM_DRM_DIR existe para testar esta função fora do aparelho.
walkmam_native_size() {
    _drm=${WALKMAM_DRM_DIR:-/sys/class/drm}
    _modo=
    for _conector in "$_drm"/card*-*; do
        [ -r "$_conector/status" ] || continue
        [ "$(cat "$_conector/status" 2>/dev/null)" = connected ] || continue
        _modo=$(sed -n '1p' "$_conector/modes" 2>/dev/null | tr -d '\r')
        [ -n "$_modo" ] && break
    done
    case "$_modo" in
        [0-9]*x[0-9]*) printf '%s %s\n' "${_modo%%x*}" "${_modo##*x}" ;;
        *)             printf '0 0\n' ;;
    esac
}

# Tamanho da saída COMO O WESTON A ENTREGA (já girada): é o que o app em
# Wayland vê como tela cheia. Sem isso o app pede a superfície no modo nativo e
# a sessão inteira é derrubada por violação de protocolo quando a saída gira.
walkmam_rotated_size() {
    _tamanho=$(walkmam_native_size)
    _larg=${_tamanho%% *}
    _alt=${_tamanho##* }
    case "$1" in
        rotate-90|rotate-270|flipped-rotate-90|flipped-rotate-270)
            printf '%s %s\n' "$_alt" "$_larg" ;;
        *)
            printf '%s %s\n' "$_larg" "$_alt" ;;
    esac
}

walkmam_weston_pid=

walkmam_stop_weston() {
    if [ -n "$walkmam_weston_pid" ]; then
        kill "$walkmam_weston_pid" 2>/dev/null || true
        wait "$walkmam_weston_pid" 2>/dev/null || true
        walkmam_weston_pid=
    fi
}

# Sobe o Weston (DRM, kiosk) e espera o socket Wayland. $1 = transform,
# $2 = arquivo de log (recebe também a saída do Weston).
walkmam_start_weston() {
    _transform=$1
    _log=$2

    export XDG_RUNTIME_DIR="$WALKMAM_RUNTIME_DIR"
    export WAYLAND_DISPLAY="$WALKMAM_WAYLAND_DISPLAY"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 0700 "$XDG_RUNTIME_DIR"
    rm -f "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY.lock"

    _ini="$XDG_RUNTIME_DIR/weston.ini"
    cat > "$_ini" << EOF_INI
[core]
shell=kiosk-shell.so
idle-time=0

[output]
name=DSI-1
transform=$_transform
EOF_INI

    # --socket explícito: o Weston 10 cria "wayland-1" quando WAYLAND_DISPLAY
    # está no ambiente; sem isso, o laço abaixo espera "wayland-0" para sempre
    # (o Weston estava funcionando e era morto pelo timeout).
    weston --backend=drm-backend.so --tty=1 --socket="$WALKMAM_WAYLAND_DISPLAY" \
        --idle-time=0 --config="$_ini" --log=/var/log/weston.log >> "$_log" 2>&1 &
    walkmam_weston_pid=$!

    _tentativa=0
    while [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; do
        if ! kill -0 "$walkmam_weston_pid" 2>/dev/null; then
            echo "Weston saiu antes de criar o socket Wayland." >> "$_log"
            [ -r /var/log/weston.log ] && cat /var/log/weston.log >> "$_log" 2>/dev/null || true
            walkmam_weston_pid=
            return 1
        fi
        if [ "$_tentativa" -ge 30 ]; then
            echo "Timeout esperando o socket do Weston." >> "$_log"
            walkmam_stop_weston
            return 1
        fi
        _tentativa=$((_tentativa + 1))
        sleep 1
    done
    return 0
}
