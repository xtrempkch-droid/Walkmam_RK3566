# Build

## Fluxo completo

O workflow em `.github/workflows/build.yml` continua responsável por baixar as fontes, compilar U-Boot/kernel, montar o rootfs Debian e produzir a imagem de referência X35S. Ele prioriza o DTB oficial obtido da ROCKNIX e usa o DTB compilado como fallback. Se nenhum dos dois estiver presente, o job falha explicitamente em vez de criar uma imagem com uma referência FDT ausente. Por compatibilidade, o nome histórico do artifact continua identificando X55, embora o FDT ativo da imagem seja selecionado para X35S; isso não declara validação em hardware.

## Empacotamento local

`build/build.sh <device> <variant>` empacota artefatos já preparados. Por exemplo:

```sh
build/build.sh powkiddy-x55 kodi
```

O script espera por `uboot/idbloader.img`, `uboot/u-boot.itb`, `kernel/arch/arm64/boot/Image`, o DTB indicado em `devices/<device>/device.conf` e uma árvore `rootfs/` que contenha o sistema da variante. `variant.conf` declara `status` e o caminho relativo do manifesto de pacotes; variantes planejadas sem implementação não podem ser empacotadas. É possível substituir os diretórios com `WALKMAN_UBOOT_DIR`, `WALKMAN_KERNEL_DIR`, `WALKMAN_ROOTFS_DIR`, `WALKMAN_OUTPUT_DIR` e o DTB com `WALKMAN_DTB_SOURCE`. Caminhos relativos são resolvidos a partir da raiz do repositório. A criação de partições exige `sudo` e as ferramentas `dd`, `parted`, `losetup`, `mkfs.vfat`, `mkfs.ext4` e `gzip`.

As imagens não são sobrescritas: escolha um nome novo com `WALKMAN_IMAGE_NAME` ou remova manualmente um artefato anterior antes de repetir o comando.
