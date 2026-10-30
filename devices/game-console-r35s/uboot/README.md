# U-Boot do Game Console R35S (RK3326)

> Placa **RK3326**, não RK3566. Contexto completo:
> [`docs/r35s-rk3326.md`](../../../docs/r35s-rk3326.md).

## Resumo

O R35S/R36S **não** sobe com o U-Boot do projeto (que é
`powkiddy-x55-rk3566_defconfig`, para RK3566). Para esta placa é preciso outro
defconfig e outros blobs do rkbin — os do **PX30**, porque o rkbin não tem
binários com o nome `rk3326` (verificado: `rkbin/bin/rk33/` só tem `px30_*`
para essa família).

## O que o U-Boot mainline oferece (documentado, não testado)

`doc/board/rockchip/rockchip.rst` (U-Boot v2024.10) lista, para rk3326:

```text
* rk3326
     - ODROID-GO Advance (odroid-go2)
```

Ou seja, **um** defconfig: `odroid-go2_defconfig`. Ele é do Odroid Go Advance —
a mesma família de placa que o R35S imita, mas com painel 480x320 e layout de
botões diferentes. Serve para **bring-up** (tela, console serial, SD, energia);
não espere os botões certos.

Blobs (na mesma doc, seção TF-A/TPL, e conferidos no `rkbin`):

```sh
export BL31=../rkbin/bin/rk33/px30_bl31_v1.37.elf
export ROCKCHIP_TPL=../rkbin/bin/rk33/px30_ddr_333MHz_v2.12.bin
make odroid-go2_defconfig
make CROSS_COMPILE=aarch64-linux-gnu-
```

O **DDR do R35S pode não ser o mesmo** do Go Advance (tamanho/marca muda por
lote). Se o U-Boot morrer sem vídeo, o suspeito nº 1 é o blob de DDR: é preciso
gerar um `ddr.bin` para a placa (`rkbin` só publica blobs prontos) ou usar o
U-Boot/DDR do fabricante. Isso está registrado como risco, não como fato.

## O que a imagem precisa mudar (quando o RK3326 entrar no pipeline)

1. `BL31`/`ROCKCHIP_TPL` do rkbin: **px30**, não rk3568/rk3566.
2. `make odroid-go2_defconfig` em vez de `powkiddy-x55-rk3566_defconfig`.
3. `BOOT_TARGETS`: no RK3566 deste projeto o patch inclui `mmc2` (2º slot SD).
   O Go Advance só tem um slot (`mmc1`); o R35S tem **TF1 + TF2**. Isso precisa
   ser medido no aparelho (`ls /sys/block`, `dmesg | grep mmc`) antes de definir
   qualquer ordem de boot.
4. `idbloader.img` no setor 64 e `u-boot.itb` no 16384 continuam valendo (é o
   mesmo esquema Rockchip), e a partição FAT de boot continua com
   `extlinux/extlinux.conf`.

## Estado

**Nada foi compilado nem bootado.** O diretório existe para registrar a
referência e a decisão; `devices/game-console-r35s/device.conf` está com
`uboot_defconfig=` vazio de propósito (o empacotador recusa a placa em vez de
gerar uma imagem que não liga).
