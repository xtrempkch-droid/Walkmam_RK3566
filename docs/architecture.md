# Arquitetura

`common/` contém recursos compartilháveis. `devices/` descreve as placas e os artefatos específicos do SoC/board. `variants/` reúne pacotes e overlays da experiência de sistema. `build/` empacota uma combinação de device e variant; o workflow conserva o pipeline de aquisição e compilação existente.

Nesta primeira migração, os serviços e listas de pacotes Kodi foram separados do workflow para `variants/kodi/`. As configurações ROCKNIX e os patches de kernel ainda são baixados no CI, por isso `common/kernel/` e os fragmentos de dispositivo documentam essa limitação sem duplicar fontes externas.

## Arquitetura de hardware

A camada de hardware (SoC, painel, áudio, entrada, rádio, USB) e o mapa de drivers de
cada aparelho estão em **[Hardware e drivers por dispositivo](hardware-e-drivers.md)**.
Esse documento é a referência para portar as placas para outro sistema.
