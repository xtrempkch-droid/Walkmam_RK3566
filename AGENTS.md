# AGENTS.md — direcionamentos e avisos para agentes de IA

Este arquivo existe para que agentes de IA (e pessoas) que trabalham neste projeto
**se comuniquem**: deixem direcionamentos, avisos e o resultado do que fizeram. Leia-o
antes de mexer no repositório e **acrescente uma entrada** (na seção
[Registro de agentes](#registro-de-agentes)) ao terminar um trabalho.

Idioma do repositório: **português**. Mantenha comentários, commits e docs em pt-BR.

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

### 4.2 Ancoragem USB — X55 funciona; X35H em aberto

- No **X55** a rede USB sobe (`RNDIS`), o aparelho fica em **10.55.0.1** e o SSH
  (`root`/`root`) funciona. O PC **não** recebe IP por DHCP: configure **estático**
  `10.55.0.2/24` na interface USB.
- No **X35H** ainda aparece `dwc3 fcc00000.usb: failed to enable ep0out`. Existe a
  variante de teste `extlinux.conf.x35s-peripheral` (USB forçado a *device*).
- O gadget não faz DHCP — se o PC ficar em 169.254.x.x, é isso.

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

## 5. Como construir

**Nuvem (fluxo completo):** Actions → *Build Mainline RK3566 (Powkiddy X55) OS* →
Run workflow (ou um push no `main`). Gera o artifact
`rk3566-x55-mainline-sdcard-image`.

**Local (U-Boot + kernel + DTB, sem root):** possível, com toolchain extra. O CI é o
caminho oficial; o rootfs Debian e a montagem da imagem exigem `sudo`.

**Cuidado com `[skip ci]`:** o GitHub olha a mensagem do **commit de topo** do push.
Se você commitar uma correção e, no mesmo push, o último commit for `docs: ... [skip
ci]`, o workflow **não roda** — a correção fica sem imagem. Ou faça dois pushes, ou
dispare um commit vazio (`git commit --allow-empty`) para gerar a imagem.

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

