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
| Status | validado no X55 e X35H | **novo: ainda não testado em hardware** |

O que é **igual** nas duas: kernel, U-Boot, DTBs (X55 + X35S/X35H), rotação
(`display_transform`), rede USB (`g_ether`, 10.55.0.1), SSH `root/root`, painel web de
rádio na **8088**, `radio-retry`, `usb-watch` e os logs de diagnóstico no cartão.

## Como escolher a variante no build

**Por push na `main`:** a variante é `kodi` (padrão), para não quebrar o fluxo usado
para testar no aparelho.

**Manual:** Actions → *Build Mainline RK3566 (Powkiddy X55) OS* → **Run workflow** →
campo **variant** → `kodi` ou `retroarch`.

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
/storage/roms/<sistema>/     ROMs (ext4, rootfs)
/storage/saves/              save RAM (.srm)
/storage/states/             savestates
/storage/screenshots/        capturas
/storage/bios/               BIOS (necessária só para alguns cores)
```

A partição FAT de boot é pequena e fica em `/boot`; serve para log e diagnóstico, não
para ROMs.

## Cores incluídos

Consoles de 8/16 bits e PlayStation 1 (que não exige BIOS):

`libretro-fceumm`, `libretro-nestopia` (NES), `libretro-snes9x` (SNES),
`libretro-gambatte`, `libretro-mgba` (GB/GBC/GBA), `libretro-genesisplusgx`
(Mega Drive/Genesis/Master System), `libretro-beetle-pce-fast` (PC Engine),
`libretro-pcsx-rearmed` (PS1).

**Não incluídos de propósito:** `libretro-mupen64plus-next` (N64) e `libretro-ppsspp`
(PSP). Os pacotes existem para arm64, mas o desempenho no RK3566 **não foi medido** —
trate como experimental. Para adicionar, basta incluir o nome no
`variants/retroarch/packages/retroarch.list` (um por linha, `#` comenta).

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
3. roda o app em Wayland;
4. se o Weston falhar, cai para o caminho sem compositor (Kodi: `--windowing=gbm`;
   RetroArch: `video_driver=drm`), esperando 3 s para o DRM ser liberado;
5. o motivo de qualquer falha vai para a **tela** (tty1) e para
   `/boot/{kodi,retroarch}-start.log`.

A lógica de rotação e o start do Weston ficam em
`common/overlay/usr/local/share/walkmam/display.sh` — **fonte única** dessa parte. O
launcher do Kodi ainda tem a cópia inline dele (foi validado em hardware assim, e não
mexemos nele sem necessidade); ao tocar nele, migre para o helper.

## Trocar de variante sem regravar

Não dá para trocar o "app da imagem" pelo cartão, porque os pacotes diferem. O que dá
para escolher no cartão é o **aparelho** (DTB) e a **rotação**. Para ter as duas
experiências, grave duas imagens em dois cartões (ou use dois cartões por aparelho).

## Se o RetroArch não abrir

1. Leia `/boot/retroarch-start.log` no PC (partição FAT): ele diz se o Weston subiu,
   qual driver foi tentado e o status de saída.
2. Na tela (tty1) aparece a mesma informação de forma resumida.
3. Console serial (`ttyS2`, 1500000n8) tem autologin do root; o `tty1` pertence ao app.
4. O `diagnostico.txt` do cartão continua sendo gerado e traz DRM, áudio, entrada e
   rotação efetiva.
