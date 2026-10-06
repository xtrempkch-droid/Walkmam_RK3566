# Walkmam RK3566

Sistema Linux para media players RK3566, com foco inicial nos handhelds Powkiddy X55, X35S e X35H.

> **Status:** em desenvolvimento. O workflow em `.github/workflows/build.yml` mantém o build existente com U-Boot, Linux v6.12, ROCKNIX, Debian ARM64 e Kodi/GBM. X55 tem device tree mainline; X35S continua em investigação e X35H não possui configuração de build independente validada.

## Estrutura

```text
common/
  kernel/                 fragmentos e política compartilhada do kernel
  packages/               pacotes comuns do rootfs
  overlay/                arquivos compartilhados instalados no rootfs
devices/<device>/
  dts/                    fontes e referências de device tree
  uboot/                  configuração e referências de U-Boot
  kernel.fragment         fragmento específico, quando validado
  device.conf             metadados de build da placa
variants/<variant>/
  packages/               pacotes da variante
  overlay/                serviços e arquivos específicos da variante
  variant.conf            metadados da variante
build/
  build.sh                entrada para empacotar <device> <variant>
  create-image.sh         criação da imagem SD
tools/                    utilitários auxiliares
docs/                     build, arquitetura e porting
.github/                  workflow, templates e CODEOWNERS
```

## Dispositivos e variantes

| Identificador | Modelo | Estado |
|---|---|---|
| `powkiddy-x55` | Powkiddy X55 | Device tree mainline conhecido |
| `powkiddy-x35s` | Powkiddy X35S | DTS/DTB de referência ROCKNIX; em investigação |
| `powkiddy-x35h` | Powkiddy X35H | Sem DTS/DTB independente validado |

A variante atualmente configurada é `kodi` (Debian Bookworm + Weston/Wayland). O teste no Powkiddy X55 revelou tela preta com erros no caminho DSI/VOP; o workflow desabilita HDMI como workaround experimental, conforme `docs/build.md`. Valores de pinagem, GPIO e display não são inferidos; consulte `docs/porting.md` antes de adicionar hardware.

`variants/own/` permanece como scaffold planejado: não contém pacotes nem overlay instalável e o empacotador recusa essa variante até que seja implementada.

## Empacotar uma imagem

Depois de preparar os artefatos de U-Boot, kernel e rootfs, execute:

```sh
build/build.sh powkiddy-x55 kodi
```

Por padrão, o script procura `uboot/`, `kernel/` e `rootfs/` na raiz do repositório e grava a imagem compactada em `output/`. Os caminhos podem ser definidos por `WALKMAN_UBOOT_DIR`, `WALKMAN_KERNEL_DIR`, `WALKMAN_ROOTFS_DIR` e `WALKMAN_OUTPUT_DIR`; caminhos relativos também são resolvidos a partir da raiz do repositório. `WALKMAN_DTB_SOURCE` pode apontar para um DTB de referência já obtido; sem isso, usa o DTB compilado no diretório do kernel. O script não baixa fontes nem monta o rootfs: no momento, o workflow do GitHub Actions é o fluxo completo de build.

Para executar o build completo, use **Actions → Build Mainline RK3566 (Powkiddy X55) OS → Run workflow**. O workflow produz a imagem de referência com DTB X35S (oficial da ROCKNIX, ou o compilado como fallback), mantendo o nome histórico do artifact `rk3566-x55-mainline-sdcard-image` por compatibilidade. A imagem não representa validação em hardware nem suporte específico à X35H.

## Documentação

- [Estado do projeto e retomada](docs/status.md) — comece por aqui
- [Fluxo de build](docs/build.md)
- [Descobertas de hardware (confirmado/hipótese)](docs/findings.md)
- [Roadmap](docs/roadmap.md)
- [Porting de dispositivos](docs/porting.md)
- [Arquitetura e estado da migração](docs/architecture.md)
