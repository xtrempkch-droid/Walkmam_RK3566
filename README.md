# Walkmam RK3566

Sistema operacional Linux para media players RK3566, com foco inicial nos handhelds Powkiddy X55, X35S e X35H.

> **Status:** em desenvolvimento. O build funcional atual está em `.github/workflows/build.yml` e usa Linux mainline v6.12, U-Boot, rkbin, ROCKNIX, Debian ARM64 e Kodi/GBM. A matriz e os arquivos de dispositivo abaixo organizam a evolução sem substituir o fluxo funcional antes dos testes em hardware.

## Dispositivos

| Identificador | Modelo | Device tree | Estado |
|---|---|---|---|
| `powkiddy-x55` | Powkiddy X55 | `rk3566-powkiddy-x55.dtb` | Base mainline funcional |
| `powkiddy-x35s` | Powkiddy X35S | Referência ROCKNIX / DTS próprio | Em investigação |
| `powkiddy-x35h` | Powkiddy X35H | Referência X35S até existir DTS específico validado | Em investigação |

Não são definidos GPIOs, resolução ou pinagem sem confirmação no hardware. Esses dados devem ser registrados em `devices/<device>/device.conf` após validação.

## Build atual

O workflow legado preserva a base já parcialmente funcional:

1. baixa U-Boot mainline, Linux v6.12 e `rkbin`;
2. consulta configurações, patches e DTBs da ROCKNIX;
3. compila kernel, módulos e device trees;
4. cria Debian ARM64 com Kodi GBM, SSH USB gadget e diagnóstico;
5. gera imagem SD compactada como artefato do Actions.

Acesse **Actions → Build Mainline RK3566 (Powkiddy X55) OS → Run workflow** para disparar manualmente.

## Estrutura

```text
common/                recursos compartilhados
  kernel/              política e fragmentos comuns
  packages/            pacotes comuns
  overlay/             arquivos do rootfs
devices/               um diretório por placa
variants/              Kodi e sistema próprio
build/                 ferramentas e documentação
docs/                  diagnóstico e porting
.github/workflows/     CI/CD
