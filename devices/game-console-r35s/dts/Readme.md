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
sequência de inicialização. Os quatro primeiros nomes são os overlays oficiais da
ROCKNIX/REG Linux:

| Variante | Observação |
| --- | --- |
| `r36s-panel1` | painel inicial (faixa de 2024) |
| `r36s-panel2` | — |
| `r36s-panel3` | — |
| `r36s-panel4` | **o nosso `mipis-panel4.dts`** (a partir de abril/2024) |
| `r36s_clone` | clones (2025) |
| `rg351mp-v2`, `rg351v-v2` | telas trocadas de RG351 — reaproveitadas |
| `cb408` | idem |

Não existe detecção automática de painel em nenhum firmware conhecido: a
documentação da REG Linux diz literalmente "descubra qual painel você tem (ou vá
trocando as opções até funcionar)". Ver `docs/r35s-rk3326.md` para o mecanismo que
este projeto adota.

## Como (re)gerar um overlay

```sh
# 1. gerar o .dts do overlay a partir de um DTS de fabricante
python3 tools/panel_overlay_from_dts.py \
    devices/game-console-r35s/dts/mipis-panel4.dts \
    -o devices/game-console-r35s/dts/panel-overlay/mipi-panel.dts

# 2. conferir contra o .dtbo oficial (opcional, mas é o teste que vale)
python3 tools/panel_overlay_from_dts.py \
    devices/game-console-r35s/dts/mipis-panel4.dts --check-arquivo mipi-panel.dtbo.r36s-panel4

# 3. compilar: dtbo isolado (overlay em runtime) ...
dtc -@ -O dtb -o mipi-panel.dtbo panel-overlay/mipi-panel.dts

# ... ou aplicar no DTB base, que é o que o build deve fazer (ver docs)
fdtoverlay -i dtbs/rk3326-<base>.dtb -o dtbs/<base>-panel4.dtb mipi-panel.dtbo
```

`fdtoverlay` e `dtc` vêm do pacote `device-tree-compiler` (o CI já instala).

## Ainda falta (nada disso foi testado no aparelho)

- Confirmar no hardware qual variante de painel esta unidade tem.
- Descobrir o **DTB base** correto (botões/ADC/áudio) — hoje a única pista é que a
  KNULLI usa o DTB da RG351MP para o R36S; ver `docs/r35s-rk3326.md`.
- Nenhum DTS próprio do R35S foi escrito ainda: sem medir os botões, qualquer
  `gpio-keys` seria chute.
