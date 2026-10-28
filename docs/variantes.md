# Variantes: `kodi` (multimídia) e `retroarch` (jogos)

O projeto gera **duas imagens** a partir do mesmo kernel, U-Boot e device tree. A
diferença é o que entra no rootfs e qual serviço toma o `tty1` no boot.

| | `kodi` | `retroarch` |
| --- | --- | --- |
| Para quê | vídeo, música, streaming | jogos (libretro) |
| App principal | Kodi 20 | RetroArch 1.14 |
| Serviço no tty1 | `kodi.service` | `retroarch.service` |
| Artefato | `rk3566-x55-mainline-sdcard-image` | `rk3566-x55-retroarch-sdcard-image` |
| Add-on de rádio no app | `script.walkmam.radio` | — (use o painel web) |
| Cores | — | NES, SNES, GB/GBC, GBA, PC Engine, PS1 (PS1 exige BIOS) |
| Status | validado no X55 e X35H | build **#116** verde (536 MB); **nada testado em hardware ainda** |

O que é **igual** nas duas: kernel, U-Boot, DTBs (X55 + X35S/X35H), rotação
(`display_transform`), rede USB (`g_ether`, 10.55.0.1), SSH `root/root`, painel web de
rádio na **8088**, `radio-retry`, `usb-watch` e os logs de diagnóstico no cartão.

## Como escolher a variante no build

**Por push na `main`:** a variante é `kodi` (padrão), para não quebrar o fluxo usado
para testar no aparelho.

**Manual:** Actions → *Build Mainline RK3566 (Powkiddy X55) OS* → **Run workflow** →
campo **variant** → `kodi` ou `retroarch`.

**Por tag (só para `retroarch`):** uma tag que comece com `retroarch-` constrói a
variante de jogos, o que também serve para marcar uma versão:

```sh
git tag retroarch-v1 && git push origin retroarch-v1
```

**Localmente** (empacotando artefatos já preparados):

```sh
build/build.sh powkiddy-x55 kodi
build/build.sh powkiddy-x55 retroarch
```

O `variant.conf` declara `status=available` e o manifesto de pacotes; variantes com
outro `status` são recusadas pelo empacotador.

## Como o build trata a variante

O passo *Build Minimal RootFS* instala a base, depois entra num bloco por variante:

* **`kodi`**: `kodi`, `kodi-bin`, `kodi-peripheral-joystick`, Weston, mesa/EGL,
  `alsa-utils`; mapa de controle do gamepad ROCKNIX; `start-kodi-wayland.sh`;
  `kodi.service`; `weston.ini`; add-on `script.walkmam.radio` (com checagem de sintaxe
  Python no build).
* **`retroarch`**: pacotes lidos de `variants/retroarch/packages/retroarch.list`;
  descoberta do diretório real dos cores (o Debian usa `/usr/lib/<triple>/libretro`) e
  do binário `retroarch`; geração do `retroarch.cfg` a partir do modelo em
  `variants/retroarch/overlay/etc/walkmam/retroarch.cfg` com o caminho real
  substituído; criação de `/storage/{roms,saves,states,screenshots,bios}`;
  `start-retroarch.sh` + `retroarch.service`.

O build **falha** se: o `retroarch` não for instalado, o diretório de cores não
existir, houver menos de 5 cores, ou o `libretro_directory` não tiver sido substituído
no `retroarch.cfg`. Melhor quebrar no CI do que descobrir no aparelho.

## Onde ficam ROMs, saves e BIOS

```text
/boot/roms/<sistema>/        ROMs (partição FAT — lê-se no PC, ~90 MB livres)
/boot/roms/sdcard1/          cartão de DADOS no slot SD1 (auto-montado, quando o
/boot/roms/sdcard2/          sistema NÃO está naquele slot) — aparece no navegador
/storage/roms/               ROMs também aqui, via Wi-Fi+scp (ext4, 4 GB)
/storage/sdcard1, sdcard2    os mesmos cartões de dados (ponto de montagem real)
/storage/saves/              save RAM (.srm)
/storage/states/             savestates
/storage/screenshots/        capturas
/storage/bios/               BIOS (PS1 exige)
```

**Cartões de dados (1 eMMC + 2 slots SD).** O aparelho tem três mídias e o sistema pode
estar em qualquer uma delas (ver o mapa em
[hardware-e-drivers.md](hardware-e-drivers.md#52-os-três-armazenamentos-emmc--2-slots-sd--medido-em-2026-10-28)).
`walkmam-extra-storage.service` monta automaticamente as que **não** têm o sistema:

| Situação | Resultado |
| --- | --- |
| sistema no SD1 | SD2 vira `/boot/roms/sdcard2` |
| sistema no eMMC | SD1 → `/boot/roms/sdcard1` e SD2 → `/boot/roms/sdcard2` |
| sistema no SD2 | SD1 vira `/boot/roms/sdcard1` |

Regras de segurança do serviço: nunca monta partição com label `BOOT`/`ROOTFS` (é o
sistema), nunca religa o slot que tem o root, e desmonta sozinho quando o cartão sai.
Cartão **inserido depois do boot** é detectado (o slot é religado); não é preciso
reiniciar. Log em `/boot/extra-storage.log`.

**Por que ROMs em `/boot/roms` (FAT):** é o único lugar que se abre de um PC **sem
rede**. O menu do RetroArch já abre nessa pasta — e os cartões de dados aparecem dentro
dela (`sdcard1`/`sdcard2`), então não é preciso navegar pelo sistema de arquivos.

A imagem cria `/boot/roms/LEIA-ME.txt` com a organização por sistema e os limites.

**Limite:** a partição FAT tem 128 MB no total (kernel + dtbs ocupam parte). Dá para
alguns jogos de 8/16 bits, não para uma coleção de PS1. Para biblioteca grande use um
**cartão de dados** (o slot extra aceita vfat/exfat/ext4, sem limite prático) ou o Wi-Fi
com `scp` para `/storage/roms`. Saves e savestates ficam no ext4 (`/storage/...`), não na
FAT — assim não se perdem ao copiar ROMs.

Para desligar a detecção de cartão inserido depois do boot (economizar energia),
`extra_storage_hotplug=off` em `/boot/walkmam.conf`.

## Cores incluídos

O que o **arm64 do bookworm** realmente tem (conferido no índice da arquitetura, não
no site de pacotes — ver o aviso no fim desta seção):

| Sistema | Pacote | Arquivo do core |
| --- | --- | --- |
| NES | `libretro-nestopia` | `nestopia.libretro` |
| SNES | `libretro-bsnes-mercury-balanced` | `bsnes_mercury_balanced.libretro` |
| GB/GBC | `libretro-gambatte` | `gambatte.libretro` |
| GBA | `libretro-mgba` | `mgba.libretro` |
| PC Engine | `libretro-beetle-pce-fast` | `mednafen_pce_fast.libretro` |
| PlayStation 1 | `libretro-beetle-psx` | `mednafen_psx.libretro` |

**PlayStation 1 exige BIOS.** É o único core de PS1 disponível para arm64 e ele precisa
de `scph5500.bin`/`scph5501.bin`/`scph5502.bin` em `/storage/bios`. A BIOS não vem com o
projeto.

**Não existem para arm64** (o apt falha com "não é possível encontrar o pacote", embora
existam para amd64/armhf): `libretro-fceumm`, `libretro-snes9x`, `libretro-genesisplusgx`
e `libretro-pcsx-rearmed`. Ou seja: **não há core de Mega Drive/Genesis** no arm64 do
bookworm. Se precisar, compile o core (genesis_plus_gx) na mão e coloque em
`/storage/cores`.

Também disponíveis, mas não incluídos: `libretro-beetle-vb` (Virtual Boy),
`libretro-beetle-wswan` (WonderSwan) e `libretro-desmume` (NDS, pesado).

### Dois detalhes do Debian que quebram build/config

1. **Os cores não são `.so`.** Vêm como **`.libretro`**
   (`/usr/lib/aarch64-linux-gnu/libretro/mgba.libretro`). O RetroArch aceita as duas
   extensões, mas qualquer contagem/verificação que só olhe `*.so` acha zero.
2. **Não use `packages.debian.org/bookworm/arm64/<pacote>` para validar um nome:** ele
   responde **HTTP 200 mesmo quando o pacote não existe** para a arquitetura (é uma
   página de erro). A fonte da verdade é o índice:

   ```sh
   curl -s http://deb.debian.org/debian/dists/bookworm/main/binary-arm64/Packages.gz \
     | zcat | grep -c '^Package: <nome>$'
   ```

   Foi assim que apareceram os quatro cores inexistentes acima — depois de um build
   falhar por eles.
3. **`rootfs/root` é modo `0700`** (padrão do debootstrap). Escrever o
   `/root/.config/retroarch/retroarch.cfg` exige `sudo` — e **ler também**: um `grep`
   sem `sudo` no arquivo responde `Permission denied` porque não consegue nem
   atravessar o diretório. Se você for verificar o conteúdo depois de escrever, use
   `sudo grep`.

## A armadilha dos nomes de driver (RetroArch 1.14)

O RetroArch do Debian 12 é o **1.14**, e nessa versão os nomes são diferentes dos
tutoriais atuais. Conferido no código-fonte:

| O que se quer | No 1.14 | Em versões novas |
| --- | --- | --- |
| Driver de vídeo | `video_driver = "gl"` (ou `glcore`, `vulkan`, `drm`) | idem |
| Wayland | **`video_context_driver = "wayland"`** — não é video_driver | virou driver |
| KMS/DRM direto | `video_driver = "drm"` + `video_context_driver = "kms"` | virou `kmsdrm` |
| Trocar driver pela linha de comando | **não existe `--video-driver`**; use `--appendconfig` | existe `--video-driver` |

Por isso o `start-retroarch.sh` faz o fallback com um arquivo extra e
`--appendconfig`, e não com `--video-driver`. Se você copiar uma configuração da
internet e a tela ficar preta, este quadro é o primeiro lugar a olhar.

## Como o app é iniciado

Mesmo desenho das duas variantes, para o comportamento ser previsível:

1. lê `display_transform` de `/boot/walkmam.conf` (`auto` escolhe pelo modelo);
2. sobe o **Weston** (backend DRM, `kiosk-shell`) com `transform` na saída `DSI-1` —
   é essa camada que gira a imagem;
3. roda o app em Wayland — no RetroArch já com o **tamanho da saída girada** em
   `video_fullscreen_x/y` (ver "Se o RetroArch não abrir");
4. se o Weston falhar, cai para o caminho sem compositor (Kodi: `--windowing=gbm`;
   RetroArch: `video_driver=drm`), esperando 3 s para o DRM ser liberado;
5. o motivo de qualquer falha vai para a **tela** (tty1) e para
   `/boot/{kodi,retroarch}-start.log`.

A lógica de rotação e o start do Weston ficam em
`common/overlay/usr/local/share/walkmam/display.sh` — **fonte única** dessa parte. O
launcher do Kodi ainda tem a cópia inline dele (foi validado em hardware assim, e não
mexemos nele sem necessidade); ao tocar nele, migre para o helper.

## Fechar o app: no RetroArch, sair **desliga**

O menu do RetroArch 1.14 só oferece "Restart RetroArch" e "Quit RetroArch" — **não
existe item "Desligar"** (nem jeito de criar um sem mexer no fonte do RetroArch). E
"Quit" só encerra o processo: o aparelho continuaria ligado, com a tela sem interface,
porque o `tty1` pertence ao app e o `getty@tty1` é mascarado. Sem SSH/serial, não havia
como desligar.

Por isso o `start-retroarch.sh` trata a **saída normal como desligamento**:

| Situação | O que acontece |
| --- | --- |
| "Quit RetroArch" no menu (com `quit_press_twice`, dois toques) ou hotkey de sair | aparece "Desligando..." no `tty1`, faz `sync` e `systemctl poweroff --no-block` |
| crash, ou sessão com status 0 e menos de 10 s | **não** desliga: é falha, tenta o driver `drm`, e o serviço para após 3 tentativas com o motivo na tela |

O `sync` antes de desligar existe porque a partição FAT (ROMs) e o ext4 (saves) podem
ter escrita pendente — e o RetroArch grava o `retroarch.cfg` no exit
(`config_save_on_exit = "true"`).

Ligado/desligado por `retroarch_exit` em `/boot/walkmam.conf` (partição FAT, editável no
PC, sem regravar o cartão):

```ini
retroarch_exit=poweroff   # padrão: fechar o RetroArch desliga o aparelho
retroarch_exit=stay       # só sai do app (depurar por SSH/serial)
```

O Kodi **não** precisa disso: ele tem menu de energia próprio ("Desligar").

## Trocar de variante sem regravar

Não dá para trocar o "app da imagem" pelo cartão, porque os pacotes diferem. O que dá
para escolher no cartão é o **aparelho** (DTB) e a **rotação**. Para ter as duas
experiências, grave duas imagens em dois cartões (ou use dois cartões por aparelho).

## Se o RetroArch não abrir

1. Leia `/boot/retroarch-start.log` no PC (partição FAT): ele diz se o Weston subiu,
   qual driver foi tentado, em que tamanho e o status de saída.
2. Na tela (tty1) aparece a mesma informação de forma resumida.
3. Console serial (`ttyS2`, 1500000n8) tem autologin do root; o `tty1` pertence ao app.
4. O `diagnostico.txt` do cartão continua sendo gerado e traz DRM, áudio, entrada e
   rotação efetiva.

### Sintomas já vistos (os dois primeiros custaram uma sessão inteira)

| Sintoma no log | Causa | Correção |
| --- | --- | --- |
| `xdg_surface geometry (720 x 1280) is larger than the configured fullscreen state (1280 x 720)`, e o RetroArch "termina com status 0" | a saída foi girada pelo Weston, mas o app pediu a superfície no modo **nativo** do painel | o launcher passa `video_fullscreen_x/y` com o tamanho **já girado** (`walkmam_rotated_size`); nunca deixe em `"0"` |
| `[Autoconf]: retrogame_joypad (…) not configured` | o pacote Debian do RetroArch **não traz** perfil de joypad | perfil em `/root/.config/retroarch/autoconfig/udev/Rocknix_Gamepad.cfg` (instalado pelo build) |
| `RetroArch (wayland) terminou com status 0 apos 3s` seguido de "tentando video_driver=drm" | morte precoce, não saída do usuário | é o comportamento novo e desejado: abaixo de 10 s não conta como sucesso |
| "Quit RetroArch" fecha o app e **o aparelho continua ligado** (tela sem interface, só serial responde) | o menu do RetroArch não tem "Desligar"; o `tty1` é do app e o `getty` está mascarado | o launcher desliga na saída normal; log grava `Saida normal do usuario (...) : desligando o aparelho` |

Para inspecionar o RetroArch **sem tomar a tela** (útil por SSH, com o serviço
rodando), use os drivers nulos — é assim que o autoconfig foi diagnosticado. Nesse tipo
de depuração, use `retroarch_exit=stay` em `/boot/walkmam.conf` (ou
`WALKMAM_CONF=<arquivo com stay>`) para o aparelho **não** desligar quando o teste
terminar:

```sh
cat > /tmp/probe.cfg <<'CFG'
video_driver = "null"
audio_driver = "null"
input_driver = "udev"
log_verbose = "true"
CFG
timeout 12 retroarch --config /root/.config/retroarch/retroarch.cfg \
    --appendconfig /tmp/probe.cfg --verbose 2>&1 | grep -iE "autoconf|joypad"
```
