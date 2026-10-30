# DTS de referência do Game Console R35S (RK3326)

> Placa **RK3326**, não RK3566. Leia antes: [`docs/r35s-rk3326.md`](../../../docs/r35s-rk3326.md).

## O que tem nesta pasta

| Arquivo | O que é | `model` no DTS |
| --- | --- | --- |
| `mipis-panel4.dts` | DTS **decompilado** de um `.dtb` de kernel de fabricante (BSP), painel "4" | `Game Console R35S/R36S fix by lxc` |
| `mipis-panel4-V22.dts` | Idem, variante de painel "V22" (outra placa, R36S) | `Game Console R36S V22` |
| `panel-overlay/mipi-panel.dts` | Overlay `rocknix,generic-dsi` **gerado** de `mipis-panel4.dts` | — |
| `panel-overlay/mipi-panel-v22.dts` | Overlay gerado de `mipis-panel4-V22.dts` | — |

Os dois primeiros são **fonte de dados, não código para compilar**: são DTBs de
kernel 4.4 de fabricante, decompilados (`compatible = "rockchip,rk3326-odroidgo3-linux"`,
nós `px30-*`, `panel-init-sequence` no formato do driver de painel do BSP). O
mainline 6.12 não conhece esses bindings — eles só servem para extrair os números
do painel.

## O painel: os números confirmados

Ambos os DTS declaram o mesmo tipo de painel (DSI, 4 lanes, 640x480):

| Campo | `mipis-panel4.dts` | `mipis-panel4-V22.dts` |
| --- | --- | --- |
| `compatible` do painel | `elida,kd35t133` + `simple-panel-dsi` | idem |
| `dsi,format` / `dsi,lanes` | `0` (rgb888) / `4` | idem |
| `dsi,flags` | `0xa03` | `0xa03` |
| `width-mm` x `height-mm` | 52 x 70 | 52 x 70 |
| delays (prepare, reset, init, enable) | 20, 150, 20, 120 ms | 20, 150, 20, 120 ms |
| `clock-frequency` | **29 MHz** | **58 MHz** |
| modo 60 Hz (`vfront-porch`) | 640x480, h 46/2/44, v **165**/2/14 | 640x480, h **300/200/300**, v 17/2/13 |
| modos 50 Hz / 75 Hz | existem, mas com porches copiados do 60 (dão 77,4 fps) | idem |
| `panel-init-sequence` | ~157 comandos DSI | ~157 comandos DSI |

Conferência cruzada: os números do `mipis-panel4.dts` batem **exatamente** com o
overlay oficial `mipi-panel.dtbo.r36s-panel4` do release
[`panel_overlays`](https://github.com/stolen/rnix/releases/tag/panel_overlays)
(usado pela ROCKNIX/REG Linux). O `tools/panel_overlay_from_dts.py --check-arquivo`
compara as **160 strings** e hoje dá `OK`.

## Modelos de tela existentes (o R35S/R36S não tem um painel só)

O mesmo aparelho sai de fábrica com telas diferentes, e cada uma precisa da sua
sequência de inicialização. As assinaturas abaixo foram **medidas nos arquivos do
aparelho** (2026-10-30, partição de boot da ROCKNIX):

| Overlay | tamanho | clock | modos | passos de init | observação |
| --- | --- | --- | --- | --- | --- |
| `mipi-panel0` | 153x85 mm | 30 MHz | 12 | 24 | **outro painel** (lista de testes) |
| `mipi-panel1` | 52x70 mm | 29 MHz | 3 iguais | 25 | init curta |
| `mipi-panel2` | 52x70 mm | 29 MHz | 3 iguais | 187 | init longa |
| `mipi-panel3` | 52x70 mm | 29 MHz | 3 iguais | 188 | init longa |
| **`mipi-panel4`** | 52x70 mm | 29 MHz | 3 (60/50/75) | **155** | **a da nossa unidade** |

O `panel4` é o mesmo painel do `mipis-panel4.dts` desta pasta: o DTB de fabricante
`rk3326-r35s-linux.dtb` traz essa sequência embutida (773 bytes / 155 passos) com
`elida,kd35t133`. O `extlinux.conf` ativo no cartão confirma:
`FDT /rk3326-gameconsole-r36s.dtb` + `FDTOVERLAYS /overlays/mipi-panel4.dtbo`.

Os nomes usados no release `panel_overlays` da ROCKNIX/REG Linux são
`r36s-panel1..4` (mais `r36s_clone`, `rg351mp-v2`, `rg351v-v2`).

Não existe detecção automática de painel: o U-Boot da ROCKNIX lê um **ADC** para
descobrir o *modelo da placa* (`uboot.hwid_adc`), não o painel. Se o ADC falhar, o
`README.txt` da própria ROCKNIX manda editar o `extlinux.conf` na mão — foi assim que
o `panel4` ficou fixado. Ver `docs/r35s-rk3326.md` §9.

## Como (re)gerar um overlay

```sh
# 1. gerar o .dts do overlay a partir de um DTS de fabricante
python3 tools/panel_overlay_from_dts.py \
    devices/game-console-r35s/dts/mipis-panel4.dts \
    -o devices/game-console-r35s/dts/panel-overlay/mipi-panel.dts

# 2. conferir contra o .dtbo oficial (opcional, mas é o teste que vale)
python3 tools/panel_overlay_from_dts.py \
    devices/game-console-r35s/dts/mipis-panel4.dts --check-arquivo mipi-panel.dtbo.r36s-panel4

# 3. compilar o overlay: o U-Boot que o projeto fixa aceita FDTOVERLAYS
#    (include/pxe_utils.h tem o campo), então o caminho é o mesmo da ROCKNIX:
#    publicar o .dtbo e apontar em extlinux.conf
dtc -@ -O dtb -o overlays/mipi-panel.dtbo panel-overlay/mipi-panel.dts

# ... ou aplicar no DTB base, gerando um DTB por variante (alternativa)
fdtoverlay -i dtbs/rk3326-<base>.dtb -o dtbs/<base>-panel4.dtb mipi-panel.dtbo
```

`fdtoverlay` e `dtc` vêm do pacote `device-tree-compiler` (o CI já instala).

## Estado (2026-10-30)

- **Painel desta unidade: `panel4`** — confirmado pelo `extlinux.conf` ativo
  (`FDTOVERLAYS /overlays/mipi-panel4.dtbo`) e pelo `.dtbo` do cartão, que bate
  100% com o que `tools/panel_overlay_from_dts.py` gera.
- **DTB base: `rk3326-gameconsole-r36s.dtb`** (painel `st7703` + joypad
  `rocknix-singleadc-joypad`) — é o que a ROCKNIX usa neste aparelho.
- Falta o **loader U-Boot/DDR** para o nosso kernel: ver `docs/r35s-rk3326.md` §9.7.
