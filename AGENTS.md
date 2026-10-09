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
| X55: boot ativo com o DTB da X55 + `display_transform=rotate-270` | **implementado** (runs #87/#88) |
| X35S/X35H: usam o **mesmo** DTB (`rk3566-powkiddy-x35s.dts` faz `#include` do X55) | confirmado no código |
| `rocknix-joypad` (17 botões / 4 eixos) + mapa do Kodi | confirmado no X55 (teste anterior) |
| **X55: Kodi não inicia — a tela fica em loop** | **BLOQUEIO ABERTO** |
| **X55/X35H: ancoragem USB (gadget `g_ether`) não funciona** | **BLOQUEIO ABERTO** |
| Sentido da rotação no X55 (`rotate-270` ou `rotate-90`) | **não validado** |
| Áudio (`asoc-simple-card: parse error`) e vídeo VA-API | **aberto** |

Detalhes e histórico completo: [`docs/status.md`](docs/status.md) e
[`docs/findings.md`](docs/findings.md). Não trate **hipótese** como fato.

## 4. Bloqueios ativos (o que precisa de atenção)

### 4.1 Kodi não inicia no X55 (tela em loop)

Sintoma relatado: o **display funciona**, mas a interface fica em **loop**. Como
`kodi.service` usa `Restart=always`/`RestartSec=5`, uma falha do Kodi (ou do Weston)
produz exatamente esse ciclo.

Já confirmado no código (não é o problema):

- Debian bookworm traz **Kodi 20.1** e o build habilita **Wayland**
  (`BUILD_WAYLAND := yes` no `debian/rules`), então `--windowing=wayland` é válido.
- O backend do Weston foi corrigido para `drm-backend.so` (não `drm`).

**O que falta:** o motivo real da falha. O `diagnostico.txt` precisa trazer:
`/boot/kodi-start.log` (novo), `journalctl -u kodi`, `/var/log/weston.log` e
`/root/.kodi/temp/kodi.log`. Sem esse dado, qualquer correção é chute.

### 4.2 Ancoragem USB não funciona

O DTB ativo da X55 habilita `usb@fcc00000` (`usb_host0_xhci`) com
`dr_mode = "otg"` e um `extcon`. Com `otg`, o controlador só vira *device* (UDC) se a
detecção de papel/VBUS funcionar; em handheld isso costuma não acontecer, e então
o `g_ether` não tem UDC para se ligar → **sem `usb0`**.

Existe uma variante histórica de teste com `dr_mode = "peripheral"` forçado
(`extlinux.conf.x35s-peripheral`). Ver seção 6.

## 5. Como construir

**Nuvem (fluxo completo):** Actions → *Build Mainline RK3566 (Powkiddy X55) OS* →
Run workflow (ou um push no `main`). Gera o artifact
`rk3566-x55-mainline-sdcard-image`.

**Local (U-Boot + kernel + DTB, sem root):** possível, com toolchain extra. O CI é o
caminho oficial; o rootfs Debian e a montagem da imagem exigem `sudo`.

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
  `display_transform` por `device.conf` (X55 `rotate-270`, X35S/X35H `normal`); o
  `build.sh`/`create-image.sh` gravam `walkmam.conf`. Submeteu ao `main` e o build
  **#87** passou.
- Fez também: melhorou o diagnóstico de USB/Kodi (role/UDC, `kodi-start.log`,
  `dump-diagnostico` em 2 capturas) e criou uma variante de boot
  `extlinux.conf.x55-peripheral` (USB forçado a *device*) para teste. Criou este
  `AGENTS.md`. Build **#88** passou e é o **run atual a usar** (keeps X55 ativo +
  `rotate-270` + diagnóstico).
- **Próximo (depende do aparelho):** gravar o artifact do run verde mais recente no X55
  e devolver o `diagnostico.txt`. Com ele, fechar: (a) por que o Kodi não inicia;
  (b) se a entradas `*peripheral` faz a ancoragem USB funcionar; (c) o sentido correto
  da rotação (`rotate-270` ou `rotate-90`).
