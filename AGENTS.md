# AGENTS.md — direcionamentos e avisos para agentes de IA

Este arquivo existe para que agentes de IA (e pessoas) que trabalham neste projeto
**se comuniquem**: deixem direcionamentos, avisos e o resultado do que fizeram. Leia-o
antes de mexer no repositório e **acrescente uma entrada** (na seção
[Registro de agentes](#registro-de-agentes)) ao terminar um trabalho.

Idioma do repositório: **português**. Mantenha comentários, commits e docs em pt-BR.

---

## 0. ONDE PARAMOS (2026-10-24) — leia antes de tudo

Detalhe completo em [`docs/status.md`](status.md#-ponto-de-retomada-2026-10-24-fim-da-sessão).
Resumo:

| O que | Estado |
| --- | --- |
| Variante **`kodi`** (multimídia) | **pronta e validada** no X55 e X35H — build #100/#105, artefato 356 MB |
| Variante **`retroarch`** (jogos) | **build #116 OK e validada no X55**: tela 1280x720 girada, áudio aberto no ALSA, **todos os botões e os 2 analógicos** |
| X35H: áudio, vídeo 640x480@58,5 Hz, botões | **confirmados em hardware** |
| X35H: USB | **não ancora**; já se sabe que **não é o papel OTG**. Falta o teste do pendrive |
| X55 | tudo o que a imagem entrega foi validado, incluindo áudio no jack e no alto-falante |

**Para gerar a imagem de jogos:** `git tag retroarch-vN && git push origin retroarch-vN`
(push na `main` gera `kodi`; a tag `retroarch-*` gera `retroarch`). Se falhar, o passo
**Preflight** diz em segundos qual pacote/arquivo está errado, sem compilar kernel.

**Nunca repita (custou build):**
1. Validar pacote por `packages.debian.org/<suite>/arm64/<pkg>` — responde **HTTP 200**
   com página de erro quando o pacote não existe para arm64. Use
   `http://deb.debian.org/debian/dists/bookworm/main/binary-arm64/Packages.gz`.
2. Ler ou escrever em `rootfs/root/...` sem `sudo`: o diretório é **0700** e o erro é
   `Permission denied` (foi o que derrubou o build #112 com tudo mais correto).
3. `[skip ci]`: cancela o build do **intervalo inteiro** do push, não só do commit de
   topo. Um commit com a marca no meio de dois pushes silencia também o push seguinte
   (custou uma tag que não gerou build). Se precisar silenciar um commit, faça o push
   dele **sozinho** e o próximo push separado.
4. `:` dentro de `name:` de um step no YAML — quebra o parse do workflow.
5. Em Wayland girado, deixar `video_fullscreen_x/y = "0"` no RetroArch: ele pede a
   superfície no modo **nativo** (720x1280) e o Weston mata o cliente
   (`xdg_surface geometry ... larger than the configured fullscreen state`), com
   **status 0** — parece "saiu normal" e a tela fica preta.
6. Contar com perfil de joystick do pacote Debian do RetroArch: `dpkg -L retroarch |
   grep autoconfig` é **vazio**. Sem `Rocknix_Gamepad.cfg` o log diz
   `[Autoconf]: retrogame_joypad (...) not configured` e **nada** responde.
7. Escrever autoconfig do RetroArch com código evdev: os números são a **posição** na
   enumeração do driver udev (tabela em `docs/hardware-e-drivers.md` §3.2.1).

---

## 1. Qual é o objetivo do projeto

Colocar o **Kodi** para funcionar em handhelds **RK3566**, começando pelo
**Powkiddy X55**, e também X35S e X35H. O sistema é: U-Boot + Linux mainline v6.12 +
Debian Bookworm + Weston/Wayland + Kodi, em imagem de cartão SD.

Leia primeiro a visão de estado do projeto: [`docs/status.md`](docs/status.md)
(é o ponto de retomada, com o que testar e o que devolver).

## 2. Mapa do repositório

```text
common/        fragmentos de kernel e pacotes compartilhados
devices/<placa>/
  device.conf        metadados da placa (image_dtb, display_transform, ...)
  dts/ uboot/        fontes e referências
variants/<variante>/
  packages/          manifesto de pacotes
  overlay/           serviços e scripts instalados no rootfs
build/
  build.sh           empacota <device> <variant> localmente
  create-image.sh    cria a imagem SD (precisa de root)
  configure-x55-dts.py   normaliza o nó rocknix-joypad no DTS da X55
.github/workflows/build.yml   pipeline completo (é ele que gera a imagem)
docs/              status.md, build.md, findings.md, roadmap.md, porting.md, architecture.md
tools/             utilitários auxiliares
```

## 3. Estado atual (resumo)

| Item | Estado |
| --- | --- |
| Boot, U-Boot, painel (display liga), Debian | **confirmado em hardware** |
| X55: boot ativo com o DTB da X55 + `display_transform=rotate-90` | **implementado** (runs #87/#88) |
| X35S/X35H: usam o **mesmo** DTB (`rk3566-powkiddy-x35s.dts` faz `#include` do X55) | confirmado no código |
| `rocknix-joypad` (17 botões / 4 eixos) + mapa do Kodi | confirmado no X55 (teste anterior) |
| **X55: Kodi não inicia — a tela fica em loop** | **RESOLVIDO** (Weston 10 criava `wayland-1`; `--socket=wayland-0`) |
| X55: ancoragem USB + SSH (`root`/`root` em 10.55.0.1) | **confirmado** (PC precisa de IP estático 10.55.0.2/24) |
| X35H: ancoragem USB | **aberto** (`failed to enable ep0out`) |
| Sentido da rotação no X55 | **confirmado no aparelho: `rotate-90`** |
| Wi-Fi/BT RTL8821CS | **firmware validado ao vivo** (`wlan0`, `hci0`); painel web na :8088 |
| Áudio (`asoc-simple-card: parse error`) e vídeo VA-API | **aberto** |

Detalhes e histórico completo: [`docs/status.md`](docs/status.md) e
[`docs/findings.md`](docs/findings.md). Não trate **hipótese** como fato.

## 4. Bloqueios e armadilhas já resolvidos (não repita o erro)

### 4.1 X55: Kodi não iniciava (tela em loop) — RESOLVIDO

Sintoma: display ligava, terminal aparecia, mas o Kodi não abria (loop). Causas:

1. **`Restart=always` + `RestartSec=5`** transformava qualquer falha em loop e apagava
   a mensagem. Agora `Restart=on-failure` + `RestartSec=15` + `StartLimitBurst=3`.
2. **Weston 10.0.1 cria o socket como `wayland-1`** quando `WAYLAND_DISPLAY` está no
   ambiente. O launcher esperava `wayland-0`, dava timeout (30 s) e matava um Weston
   que estava funcionando. **Correção: `weston --socket=wayland-0` explícito.**
   Validado com reboot: `GUI format 720x1280`, `xdg_output` lógico 1280x720.
3. O fallback GBM falhava logo após matar o Weston (DRM ainda preso); agora espera 3 s.

Se voltar a falhar: o motivo fica em **`/boot/kodi-start.log`** e na **tela (tty1)**.

### 4.2 Ancoragem USB — X55 funciona; X35H **não ancora** (provável hardware)

- No **X55** a rede USB sobe (`g_ether`), o aparelho fica em **10.55.0.1** e o SSH
  (`root`/`root`) funciona. O PC **não** recebe IP por DHCP: configure **estático**
  `10.55.0.2/24` na interface USB.
- No **X35S/X35H**, testado em 2026-10-24: **não funciona**, e **não é o papel OTG**.
  Forçar `dr_mode = "peripheral"` no DTB não mudou nada (o PC não acusa nem
  "dispositivo desconhecido"). O diagnóstico daquele boot mostra o UDC
  `fcc00000.usb` presente porém `state = not attached` (sem VBUS/sessão no fio) e
  `usb0` em `NO-CARRIER`. O DTB foi conferido: `dr_mode`, `phys`, `extcon` e o
  `otg-port` estão corretos — é a mesma estrutura do DTB da X55.
  - **Não repita** a tentativa de "resolver com peripheral": já foi testada e falhou.
  - **Hipótese atual:** a porta USB-C do X35H não está no OTG (`usb@fcc00000`) e sim no
    `usb@fd000000` (`dr_mode = "host"`). Se for isso, a porta é host-only: pendrive,
    teclado e **adaptador USB-Ethernet funcionam**; gadget/SSH pelo cabo direto **não é
    possível por software**.
  - **Teste que decide:** com o console serial aberto, `dmesg -w` e plugar um pendrive;
    depois `ls /sys/bus/usb/devices/`. Antes de concluir "sem dados", repetir com o
    **mesmo cabo que funciona na X55**.
  - A imagem traz `walkmam-usb-watch.service` → `/boot/usb-watch.log` com o retrato do
    estado USB a cada mudança (UDC, `usb_role`, dispositivos, `online`, `dmesg`).
  - Continuam disponíveis `extlinux.conf.x35s` (otg, padrão) e
    `extlinux.conf.x35s-peripheral` (teste).
- O gadget não faz DHCP — se o PC ficar em 169.254.x.x, é isso.

### 4.2.0 tty1 é do Kodi — não habilite getty ali

`kodi.service` usa `TTYPath=/dev/tty1`, `StandardInput=tty` e
`Conflicts=getty@tty1.service`. Se o `getty@tty1` também estiver habilitado (com ou sem
autologin), os dois disputam a unidade no boot e **um dos dois recebe SIGTERM**: no
`/boot/kodi-start.log` aparece `Kodi (wayland) terminou com status 143`, depois a
tentativa GBM falha (`ERROR: Unable to create GUI`, 255) e o serviço entra em ciclo.

A imagem agora **mascara** `getty@tty1.service` (`systemctl mask`). O shell de
emergência fica no **console serial** (`ttyS2`, autologin do `root`). Não recrie o
drop-in de autologin em tty1.

### 4.2.1 Áudio: mux tem que ficar em `HP` (não "conserte" isso)

No X55 o amplificador do alto-falante (`spk_amp`) é alimentado por **`HPOL`/`HPOR`**, não
pelo `SPKO` do codec. Por isso o `Playback Mux` **deve** ficar em `HP`; em `SPK` o
aparelho fica **mudo**. Áudio validado pelo usuário nos **dois** caminhos (jack 3,5 mm e
alto-falante interno), com `Headphones Jack` alternando por detecção de GPIO
(`gpio4 RK_PC6`).

### 4.3 Bluetooth do X55 não inicializava — RESOLVIDO (2026-10-24)

Sintoma: `hci0` existe, mas com `BD Address 00:00:00:00:00:00`; `bluetoothctl show`
responde "No default controller available"; `dmesg` mostra
`RTL: no UART config entry found`.

Causa: o BT é UART no `uart1` com `compatible = "realtek,rtl8821cs-bt",
"realtek,rtl8723bs-bt"`. Não existe driver para `rtl8821cs-bt`; casa o **`hci_h5`**
(three-wire) pelo fallback `rtl8723bs-bt`. O `h5_btrtl_setup()` chama
`btrtl_get_uart_settings()`, que **exige** no `rtl8821cs_config.bin` uma entrada de
offset **0x0c** (baudrate + flow control). O `linux-firmware` **não publica** esse
arquivo; o `rtl8821c_config.bin` (10 bytes) renomeado não tem a entrada → `-ENOENT` →
o setup aborta antes de baixar o firmware.

Fix (no CI): **gerar** o `rtl_bt/rtl8821cs_config.bin` com 25 bytes — assinatura
`0x8723ab55`, `total_len=0x13`, uma entrada `0x0c` de 16 bytes com baudrate
`0x04928002` (1500000) e `data[12]=0x5f` (bit 2 = flow control, casa com o
`uart-has-rtscts` do `uart1`). Validado: `RTL: fw version 0x75b8f098`, MAC real,
`UP RUNNING`, scan listando dispositivos e **sobe sozinho depois de reboot**.

Não troque esse arquivo por um renomeado do 8821C: volta a quebrar.

### 4.4 Variantes: `kodi` (multimídia) e `retroarch` (jogos)

O mesmo kernel/DTB gera **duas imagens**. O que muda é o rootfs e o serviço do `tty1`.
A variante é escolhida no `workflow_dispatch` (input `variant`); **push na `main` constrói
`kodi`**, que é o que se usa para testar no aparelho.

* `variants/kodi/` — Kodi + Weston + add-on de rádio.
* `variants/retroarch/` — RetroArch + cores + Weston, sem add-on (rádio pelo painel web).

Detalhes em [docs/variantes.md](docs/variantes.md). Pontos que custam tempo se esquecidos:

1. **Nomes de driver do RetroArch 1.14** (o do bookworm): `video_driver = "gl"` +
   **`video_context_driver = "wayland"`** (Wayland é contexto, não driver); KMS/DRM é
   `video_driver = "drm"` + `video_context_driver = "kms"` (no 1.17+ virou `kmsdrm`).
   E **não existe `--video-driver`** nessa versão: para trocar driver use
   `--appendconfig <arquivo>`.
2. O build **descobre** o diretório dos cores (`/usr/lib/<triple>/libretro`) em vez de
   chutar, e falha se houver menos de 5 cores ou se o `libretro_directory` não tiver
   sido substituído no `retroarch.cfg`.
3. A rotação/Weston saiu para `common/overlay/usr/local/share/walkmam/display.sh`
   (fonte única). **O launcher do Kodi ainda tem a cópia inline** — foi validado em
   hardware assim; ao mexer nele, migre para o helper.
4. `dump-diagnostico.sh`, `radio-retry.sh`, `usb-watch.sh` e o painel web ainda moram em
   `variants/kodi/overlay/` embora sejam compartilhados. Funciona, mas o lugar certo é
   `common/overlay/`; mover exige atualizar todos os `install` do workflow.
5. N64 (`mupen64plus-next`) e PSP (`ppsspp`) existem para arm64 mas **não** entram por
   padrão: desempenho não medido no RK3566.

## 5. Como construir

**Nuvem (fluxo completo):** Actions → *Build Mainline RK3566 (Powkiddy X55) OS* →
Run workflow (ou um push no `main`). Gera o artifact
`rk3566-x55-mainline-sdcard-image`.

**Local (U-Boot + kernel + DTB, sem root):** possível, com toolchain extra. O CI é o
caminho oficial; o rootfs Debian e a montagem da imagem exigem `sudo`.

**Cuidado com `[skip ci]` (custou dois ciclos):** o GitHub olha a mensagem do
**commit que o ref aponta**.

1. Push na branch: vale o commit de topo. Se você commitar uma correção e o último
   commit do push for `docs: ... [skip ci]`, o workflow **não roda** e a correção fica
   sem imagem.
2. **Push de tag:** vale a mensagem do commit **apontado pela tag**. Uma tag criada em
   cima de um commit com `[skip ci]` também não roda — inclusive a tag
   `retroarch-*`, que é justamente o gatilho da variante de jogos.

Saídas: dois pushes separados; `git commit --allow-empty` sem `[skip ci]` para gerar a
imagem; ou marcar a tag num commit limpo. Um `git push --delete` da tag e recriar em
outro commit resolve sem force-push na branch.

## 5.1 Acesso ao aparelho (para depurar)

- Console **serial** (`ttyS2`, 1500000n8) e **tty1** com autologin do `root`.
- **SSH pela rede USB** (`g_ether`): o aparelho fica em **10.55.0.1** (o PC usa
  `10.55.0.2/24`), usuário `root`, senha `root`.
  - Se o login por senha for **recusado**, quase sempre é o `ssh_config` do Debian:
    o padrão é `PermitRootLogin prohibit-password`. A imagem instala
    `/etc/ssh/sshd_config.d/10-walkmam.conf` com `PermitRootLogin yes` e
    `PasswordAuthentication yes`.
- **Logs no cartão** (partição FAT, leitura no PC): `diagnostico.txt`,
  `kodi-start.log`, `usb-gadget.log`, `weston.log`.

## 6. Regras e armadilhas (leia antes de editar)

1. **Não inferir GPIO/pinagem.** Nunca invente valores de hardware; use fonte
   confirmada ou marque como hipótese.
2. **Um DTB por placa, mas X35S e X35H compartilham o mesmo.** O `rk3566-powkiddy-x35s.dts`
   faz `#include` do DTS da X55 e sobrescreve o painel (640x480,
   `rocknix,generic-dsi`). Bootar a X55 com o DTB da X35S deixa a tela preta — foi a
   regressão corrigida nos runs #87/#88.
3. **FDT ausente = aparelho sem imagem** (LED aceso). O step de imagem falha de
   propósito se faltar o DTB ativo.
4. **Rotação vem de `display_transform`** em `devices/<placa>/device.conf`, gravada em
   `walkmam.conf` na partição FAT e lida por
   `variants/kodi/overlay/usr/local/bin/start-kodi-wayland.sh`. Não fixe o transform no
   `weston.ini`.
5. **Aspas dentro de `bash -c '...'` no `build.yml` já quebraram o build (#82/#83).**
   Prefira instalar arquivos do overlay com `install` em vez de heredoc inline.
6. **Não commitar segredos** (tokens, senhas). A senha do `root` da imagem é `root` e
   o SSH está ligado — ver "Segurança" no roadmap.
7. Fixe versões de fontes externas por commit quando possível (hoje o CI clona
   `ROCKNIX/distribution` e o `rkbin` na ponta; os blobs citados dos `rkbin`
   `rk3568_bl31_v1.43` / `rk3566_ddr_1056MHz_v1.18` já não existem e o fallback entra).

## 7. Protocolo de comunicação entre agentes

- Toda mudança relevante deve atualizar [`docs/status.md`](docs/status.md) (bloqueios,
  "confirmado x hipótese", runs do CI) e, se for decisão de engenharia, `docs/findings.md`.
- Ao terminar, **acrescente uma entrada** em [Registro de agentes](#registro-de-agentes)
  (mais recente por último), dizendo: data, autor (o modelo/agente), o que fez, o que
  ficou pendente e o que o **próximo** precisa testar.
- Deixe o repositório sempre num estado que **compila** (o `main` dispara build).

---

## Registro de agentes

<!-- Mais recente por último. Modelo:

### AAAA-MM-DD — <autor/agente>
- Fez: ...
- Pendente / próximo: ...
-->

### 2026-10-09 — Copilot (sessão de correção do X55)

- Fez: corrigiu a regressão de "sem imagem" (o boot ativo usava o DTB da X35S; agora
  usa o DTB da X55, com o DTB da X35S/X35H em `extlinux/extlinux.conf.x35s`); criou
  `display_transform` por `device.conf` (X55 `rotate-90`, X35S/X35H `normal`); o
  `build.sh`/`create-image.sh` gravam `walkmam.conf`. Submeteu ao `main` e o build
  **#87** passou.
- Fez também: melhorou o diagnóstico de USB/Kodi (role/UDC, `kodi-start.log`,
  `dump-diagnostico` em 2 capturas) e criou uma variante de boot
  `extlinux.conf.x55-peripheral` (USB forçado a *device*) para teste. Criou este
  `AGENTS.md`. Build **#88** passou.
- Fez ainda: **corrigiu o SSH** — o Debian 12 bloqueia login do root por senha
  (`PermitRootLogin prohibit-password`), então `root:root` era recusado; a imagem agora
  instala `/etc/ssh/sshd_config.d/10-walkmam.conf` com `PermitRootLogin yes` +
  `PasswordAuthentication yes`. Launcher do Kodi com fallback **Weston → GBM** e o
  motivo do erro **na tela**; `kodi.service` com `Restart=on-failure`/`RestartSec=15`
  para a falha não virar loop que apaga a mensagem. Push `63f4bd7` → **build #89**.
- **Handoff (2026-10-09):** o usuário **vai criar/baixar a imagem (#89) quando voltar
  e avisar**; eu sigo com o teste. Confirmar que o #89 ficou `success`.
- **RESOLVIDO em 2026-10-23 (com SSH ao vivo no X55):** o Kodi não abria porque o
  **Weston 10.0.1 criava o socket `wayland-1`** (com `WAYLAND_DISPLAY` no ambiente) e o
  launcher esperava `wayland-0`, matando o Weston após 30 s. Correção:
  `weston --socket=wayland-0` explícito + 3 s antes do fallback GBM. Confirmedo com
  **reboot**: `kodi.service` ativo, Kodi em Wayland, `GUI format 720x1280`, `xdg_output`
  lógico 1280x720 (`rotate-90` validado no aparelho). Também validado o **SSH root/root** e a rede USB
  (PC precisa de IP estático `10.55.0.2/24`; o gadget não faz DHCP).
- **Áudio (2026-10-23/24):** o `sound` ficava em deferred probe porque o **I2S do
  Rockchip** não estava no kernel (`# CONFIG_SND_SOC_ROCKCHIP`); o config da ROCKNIX
  pedia o filho, mas o `olddefconfig` descartava. Habilitados
  `SND_SOC_ROCKCHIP{,_I2S,_I2S_TDM}` + `&hdmi_sound` desligado junto com o HDMI.
  **Build #92 verde** (352 MB) — instalar e testar o áudio no aparelho.
- **Wi-Fi/Bluetooth (2026-10-24):** faltavam firmware (`rtw88/rtw8821c_fw.bin`,
  `rtl_bt/rtl8821cs_fw.bin`+config), `wpa_supplicant` (sem ele o NM deixa `wlan0`
  `unavailable`) e BlueZ. Validado ao vivo após copiar os firmwares: `wlan0` (fw
  24.11.0) e `hci0` sobem. A imagem agora baixa os firmwares (tag 20260309, sha256) e
  instala `wpasupplicant iw wireless-tools rfkill bluez busybox`, além do **painel web
  na porta 8088** (`walkmam-webui.service`) para gerenciar Wi-Fi/BT.
- **Drift de fontes externas (2026-10-24):** os runs #90/#91 falharam porque o master da
  ROCKNIX mudou (kernel 7.2, patch 0012 removido, 0016 usando `&gpio_keys_control`).
  Agora U-Boot/ROCKNIX/rkbin estão **fixados por commit** e há guarda para `.rej`.
- **Próximos itens abertos:** validar o **áudio** no #92, VA-API
  (`rockchip_drv_video.so` ausente) e o **sentido visual** da rotação
  (`rotate-90` validado).

### 2026-10-24 — Copilot (Bluetooth do X55)

- Fez: fechou a causa raiz do Bluetooth (config UART `0x0c` ausente no
  `rtl8821cs_config.bin`). O CI passou a **gerar** o arquivo (25 bytes) em vez de
  renomear o do 8821C; conferido por sha256 no build. Validado ao vivo no aparelho com
  build #97 (trocando o arquivo e recarregando o `hci_uart`): firmware baixa
  (`fw version 0x75b8f098`), `hci0` com MAC real, `UP RUNNING`, scan acha dispositivos,
  e depois de **reboot** sobe sozinho. Wi-Fi também confirmado no boot sem retry.
- Pendente / próximo: gravar a imagem nova (#98) e validar áudio no aparelho; o
  esticamento horizontal de ~1,6% é do painel (67x121 mm vs modo 720x1280).

### 2026-10-24 — Copilot (add-on de rádio dentro do Kodi + créditos)

- Fez: criou o add-on **`script.walkmam.radio`** ("Walkmam Radio") porque o Kodi 20 no
  Linux não tem UI de rádio (o gerenciador de Wi-Fi só existe nos builds
  Windows/Android). É um script add-on (`xbmc.python` 3.0.0) em
  `variants/kodi/overlay/usr/share/kodi/addons/script.walkmam.radio/` que chama
  `nmcli` (listar/conectar/desconectar Wi-Fi) e `bluetoothctl` (ligar, procurar,
  parear, conectar, ficar visível). O CI instala e roda `py_compile` no `default.py`.
  Também adicionou ao `README.md` a seção **"Créditos e transparência sobre o uso de
  IA"** (DeepSeek como modelo criador dos códigos + Copilot como assistente, o que foi
  verificado em hardware e o que não foi).
- Validado no #97: o Kodi registra `CAddonMgr::FindAddons: script.walkmam.radio v1.0.0
  installed`; e a lógica rodou no aparelho com os binários reais — `wifi_redes()`
  devolveu SSIDs com sinal/segurança, `bt_info()` devolveu o controlador
  `A8:4F:A4:C9:98:4C`, `bt_escanear(8)` achou 2 dispositivos em 8,3 s.
- Armadilha: `bluetoothctl` imprime `[NEW] Device <MAC> <nome>` no scan e
  `Device <MAC> <nome>` em `devices` — o regex **não** pode ser ancorado no começo da
  linha; e linhas `[CHG] ... RSSI:` não trazem nome (usar só as `[NEW]`).
- Pendente / próximo: gravar a imagem (#99 em diante) e abrir o add-on pela TV para
  confirmar os diálogos (a lógica já foi testada, a GUI não).

### 2026-10-24 — Copilot (áudio confirmado + doc de portabilidade)

- Fez: registrou a confirmação do **áudio nos dois caminhos** (jack 3,5 mm e alto-falante
  interno) e criou **`docs/hardware-e-drivers.md`**, a referência de portabilidade: para
  cada um dos três aparelhos, a arquitetura de hardware e de driver (painel, backlight,
  entrada, áudio, Wi-Fi/BT, USB, energia), os números exatos (GPIO, SARADC, timings,
  trilhos, firmware), a lista de configs de kernel obrigatórias e **11 receitas prontas
  (F1–F11)** para portar a outro sistema, além da tabela sintoma → causa → correção.
- Também deixou explícito o que **não** é mainline e precisa ser carregado junto:
  `rocknix-joypad`, o shim `input-polldev`, `panel-generic-dsi.c` (painel da X35S/X35H),
  o DTS da X35S e o `rtl8821cs_config.bin` gerado.
- Corrigido de passo: `CONFIG_BT_HCIUART` é `=m` (não `=y`); na X35S o Wi-Fi/BT está
  **não medido** (só a X35H tem "sem WiFi/BT" registrado); o `dr_mode` da X55 vem do
  `rk356x.dtsi` como `otg` (não precisa de variante "peripheral").
- Pendente / próximo: validar a imagem #100 no aparelho (Bluetooth + add-on com o
  teclado corrigido) e confirmar as builds.

### 2026-10-24 — Copilot (imagem #100 validada no CI)

- Fez: **build #100 success** (356 MB), a imagem para usar: junta o Bluetooth corrigido
  (config UART do 8821CS gerada no build) e o add-on `script.walkmam.radio` com o
  teclado da senha corrigido. Conferido localmente que o bloco do CI gera o
  `rtl8821cs_config.bin` **byte-idêntico** ao validado no aparelho (sha256
  `6ddeb15f...`) e que a instalação do add-on produz os dois arquivos certos
  (`addon.xml` + `default.py`, registrado como `xbmc.python.script`).
- Pendente / próximo: usuário gravar o #100 e testar Bluetooth pelo add-on e o teclado
  da senha na TV; depois confirmar o resto (áudio já confirmado nos dois caminhos).

### 2026-10-24 — Copilot (X35H validada em hardware + correções de USB e rotação)

- Fez: registrou o **primeiro teste de X35H em hardware**: vídeo 640x480 a **58,5 Hz**
  em tela cheia, **áudio** e **botões/direcionais** funcionando. Só o **USB** ficou em
  aberto.
- **USB:** `failed to enable ep0out` é o DWC3 recusando o DEPCMD de ep0out porque o
  controlador está em modo *host* (`dr_mode = "otg"` do `rk356x.dtsi`, e nessas placas a
  detecção não resolve para *device*). O build agora gera `dtbs/<dtb>-peripheral.dtb`
  com `dr_mode = "peripheral"` num **helper reutilizável** que **verifica o DTB final**
  (não gera variante quebrada em silêncio) e a entrada `extlinux.conf.x35s` **já aponta
  para ela**; `extlinux.conf.x35s-otg` volta ao original.
- **Rotação (bug real):** o `walkmam.conf` saía sempre com `display_transform=rotate-90`,
  obrigando a editar à mão para X35S/X35H. Agora o padrão é `auto` e o launcher escolhe
  pelo `/proc/device-tree/model` (`*x55*` → `rotate-90`, resto → `normal`); valor
  explícito continua vencendo. Testado com matriz de casos (auto/vazio/explícito).
- **75 Hz (esclarecido):** não é limitação de hardware. O `panel-generic-dsi` só marca
  como preferido o modo `M` com `default=1` (o de 58,5 fps), e o Kodi usa o preferido do
  conector. Os 75,47 fps existem na lista mas marcados `(CAN FAIL)`. Para testar de
  verdade é preciso gerar um DTB com esse modo como `default=1`.
- Diagnóstico: `diagnostico.txt` agora traz o modelo do device tree, os modos DRM (o
  primeiro é o preferido) e a rotação efetiva — responde "o 75 Hz aplicou?" e "qual DTB
  está ativo".
- Pendente / próximo: gerar a imagem e o usuário testar o SSH por USB na X35H; se o
  `peripheral` não resolver, olhar o `diagnostico.txt` (campos `dr_mode` e `usb_role`).

### 2026-10-24 (2) — Copilot (diagnóstico da X35H: USB descartado como software)

- Recebi o `diagnostico.txt` da X35H (boot com
  `rk3566-powkiddy-x35s-rocknix-peripheral.dtb`). Conclusões com evidência:
  - `dr_mode` no device tree em uso = **`peripheral`** (confirmado no log);
  - `/sys/class/udc/fcc00000.usb` **existe**, mas `state = not attached`;
  - `usb0` sobe com `10.55.0.1/24` e fica `NO-CARRIER`;
  - `failed to enable ep0out` continua.
- Desmontei o `.dtb` que o aparelho realmente usou: `usb@fcc00000` com
  `dr_mode="peripheral"`, `phys`/`phy-names`, `extcon`, `maximum-speed` e o
  `usb2phy@fe8a0000`/`otg-port` todos `okay` — **estruturalmente igual ao da X55**, que
  funciona. Portanto o DTB não é o culpado.
- Conclusão honesta: **não é o papel OTG** (forçá-lo a device não mudou nada). A
  hipótese que sobrou é hardware: a porta USB-C da X35H provavelmente está no
  `usb@fd000000` (`dr_mode = "host"`), o que a torna **host-only** — nesse caso pendrive,
  teclado e **dongle USB-Ethernet funcionam**, mas gadget/SSH direto é impossível.
- Revertido o padrão `peripheral` (seria trocar o padrão por uma hipótese já testada e
  falha) e mantida a variante como teste. Também reverte o `dr_mode` só na X35S/X35H.
- Criado `walkmam-usb-watch.service` + `usb-watch.sh` (5 min no boot, log por boot em
  `/boot/usb-watch.log`, retrato a cada mudança + `dmesg` do instante) para o teste do
  pendrive produzir evidência.
- Pendente / próximo: o usuário plugar um pendrive e devolver `usb-watch.log`. Isso
  define se o SSH na X35H será por dongle USB-Ethernet ou se a porta não tem dados.

### 2026-10-24 (3) — Copilot (variante `retroarch`)

- Fez: criou a variante **`retroarch`** (versão de jogos) ao lado da `kodi` (multimídia).
  O workflow ganhou o input `variant` (push na main continua `kodi`), os pacotes saem de
  `variants/retroarch/packages/retroarch.list`, o build descobre o diretório real dos
  cores e gera o `retroarch.cfg` a partir de um modelo (com asserção), cria
  `/storage/{roms,saves,states,screenshots,bios}` e habilita `retroarch.service` no tty1.
  Artefato próprio: `rk3566-x55-retroarch-sdcard-image` (o nome do kodi não mudou).
- Extraiu a rotação/start do Weston para `common/overlay/.../display.sh` (fonte única) e
  o novo launcher a consome; o launcher do Kodi ficou intocado de propósito.
- Conferido no fonte do RetroArch 1.14 (não por suposição): wayland é
  `video_context_driver`, o driver KMS/DRM se chama `drm` (não `kmsdrm`) e **não existe**
  `--video-driver` nessa versão. Tudo isso está documentado e comentado no código, porque
  é o tipo de erro que só aparece na tela preta.
- `dump-diagnostico.sh` passou a registrar `retroarch-start.log`, a config efetiva, os
  cores instalados e o `usb-watch.log`.
- Pendente / próximo: **nada disso foi testado em hardware**; o primeiro teste precisa
  confirmar boot, rotação e áudio no RetroArch, e se o joypad ROCKNIX é reconhecido.

### 2026-10-24 (4) — Copilot (variante retroarch: 4 builds, 4 bugs reais)

- Fez: criou a variante **`retroarch`** (jogos) ao lado de `kodi` (multimídia), com
  input `variant` no workflow e gatilho por tag (`retroarch-*`). Extraiu a rotação/start
  do Weston para `common/overlay/.../display.sh` (fonte única) e deixou `/roms` na
  partição FAT para copiar jogo pelo PC — essencial na X35H, onde o USB não ancora.
- **4 builds da variante falharam, cada um por um motivo diferente, todos corrigidos:**
  1. `libretro-fceumm`, `libretro-snes9x`, `libretro-genesisplusgx` e
     `libretro-pcsx-rearmed` **não existem para arm64** (existem para amd64/armhf).
     Descoberto simulando `apt-get -s install` com `APT::Architecture=arm64` e o índice
     `binary-arm64/Packages.gz`. A lista passou a usar o que existe: `nestopia`,
     `bsnes-mercury-balanced`, `gambatte`, `mgba`, `beetle-pce-fast`, `beetle-psx`.
  2. Os cores vêm como **`.libretro`** (e também `_libretro.so`), não só `.so`: a
     contagem por `*.so` dava números estranhos.
  3. A asserção do `retroarch.cfg` comparava `.../libretro/` (gerado) com
     `.../libretro` (esperado) → abortava por causa da própria checagem.
  4. **`rootfs/root` é 0700**: o `grep` de verificação rodava sem `sudo` e recebia
     `Permission denied`. O log do #112 provou que os 24 pacotes e **12 cores** já
     estavam instalados — só a verificação falhava.
- Também: `concurrency` (um build por ref, cancela o anterior — cheguei a 4 runs em
  paralelo), passo de **Preflight** que valida nome de variante, manifesto, cada pacote
  contra o índice arm64 e os arquivos de overlay **em segundos**, e correção de um erro
  de YAML meu (`:` no `name:`).
- Testado sem hardware: launcher do RetroArch com binários falsos — rotação por modelo
  (X55 → `rotate-90`, X35S → `normal`), valor explícito vencendo o modelo, fallback
  wayland → drm via `--appendconfig`, falha total saindo 1 e binário ausente com
  mensagem no log.
- **Pendente / próximo:** o build **#116** (`retroarch-v0.6`) não terminou; ver se deu
  `success` e, em caso positivo, testar no aparelho (boot, rotação, áudio, joypad e
  cores no menu). Se falhar, o Preflight diz o motivo sem compilar. No X35H falta o
  teste do pendrive para decidir se a porta é host-only.

