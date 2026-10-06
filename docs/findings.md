# Descobertas de hardware e build (X35S/X35H e X55)

Este documento junta o que foi aprendido testando imagens nos aparelhos. Cada item
diz se foi **confirmado** (log ou teste no aparelho) ou é **hipótese**. Não trate
hipótese como fato ao portar outra placa.

## Aparelhos usados nos testes

| Aparelho | Observação |
| --- | --- |
| Powkiddy X35H | Sem WiFi, sem Bluetooth, sem touch. Compartilha o DTB da X35S. |
| Powkiddy X55 | Usado para corrigir a rotação do Kodi e o gamepad. |

## Bootloader e imagem (confirmado)

- U-Boot mainline com `powkiddy-x55-rk3566_defconfig`. A ROCKNIX usa o mesmo defconfig
  para a família, então a X35S/X35H também boota com ele.
- Blobs do rkbin usados pela ROCKNIX: `rk3568_bl31_v1.43.elf` e
  `rk3566_ddr_1056MHz_v1.18.bin`.
- Gravação no cartão: `idbloader.img` no setor 64 e `u-boot.itb` no setor 16384.
- O boot lê `extlinux/extlinux.conf` na partição FAT (`BOOT`). Se o `FDT` aponta
  para um arquivo que não existe, o aparelho acende o LED e fica sem imagem.

## Device tree

- **X55** tem DTS no kernel mainline (`rk3566-powkiddy-x55.dts`, desde o Linux 6.8).
- **X35S** não existe no mainline v6.12 (confirmado: `make dtbs` não gera o `.dtb`).
  O DTS vem de um patch da ROCKNIX (`add device tree for powkiddy x35s`) que só
  adiciona o arquivo. É preciso registrá-lo no `Makefile` de
  `arch/arm64/boot/dts/rockchip/`, senão o `.dtb` não é compilado.
- **X35H** não tem DTB próprio. A documentação da ROCKNIX manda usar o da X35S.
- O DTS da X35S tem 37 linhas e só sobrescreve o painel (`&panel`). Isso sugere que
  ele inclui o DTS do X55 (**hipótese**, não verificada).

## Painel (confirmado)

- O painel usa `compatible = "rocknix,generic-dsi"`. Esse driver não está no mainline.
  É o `panel-generic-dsi.c` do repositório `ROCKNIX/distribution`, injetado no
  kernel pelo `package.mk` deles.
- Com o driver habilitado (`CONFIG_DRM_PANEL_GENERIC_DSI`), o log mostra
  `panel-generic-dsi ... lanes 4` e o framebuffer é criado.
- O nó `hdmi@fe0a0000` precisa estar desabilitado. No `.dtb` oficial da ROCKNIX com
  HDMI e DSI ligados juntos, o log mostra `Failed to register component: -517` e
  `POST_BUF_EMPTY irq err at vp1` em loop, com tela preta. Desabilitando o HDMI (por
  decompilar, editar e recompilar o `.dtb`), a tela ligou.
- No X55 aparece o mesmo erro `-517`/`POST_BUF_EMPTY`; o workflow também desabilita
  o HDMI nele para testar. O Kodi informou ter escolhido `DSI-1`, então o log não
  prova que ele tenha escolhido HDMI.

## Botões e analógico

- Sem o driver certo, o kernel só enumera `rk805 pwrkey` e `gpio-keys-vol`.
  (confirmado em `diagnostico.txt`).
- O driver é o `rocknix-joypad`, de um repositório separado
  (`github.com/ROCKNIX/rocknix-joypad`). Ele usa `input-polldev.h`, que não existe
  mais no Linux 6.12. Um header de compatibilidade baseado em `input_setup_polling`
  resolve a compilação.
- No X55, depois de corrigir o DTS, o kernel registrou `retrogame_joypad` com 17
  botões e 4 eixos, e o Kodi reconheceu o joystick (confirmado).
- O nó `rocknix-joypad` precisa ser filho direto da raiz do device tree, porque o
  driver é um `platform_driver`. Aninhado sob o DSI, ele não é registrado.
- O mapa do Kodi (`retrogame_joypad_17b_4a.xml`) só vale para 17 botões e 4 eixos.
  **Hipótese a verificar:** a X35H pode ter outra contagem.
- O arquivo `rocknix-singleadc-joypad.c` do mesmo repositório também usa
  `input-polldev.h`. Não foi confirmado que a X35S precise dele.

## USB gadget (SSH pelo cabo) — NÃO resolvido

- O controlador aparece em `/sys/class/udc/fcc00000.usb` e o `g_ether` carrega.
- Mesmo assim o kernel registra `dwc3 fcc00000.usb: failed to enable ep0out`, em
  todos os testes, com o `.dtb` oficial e com o nosso. O PC não lista nada no
  `lsusb`, nas duas portas testadas.
- Forçar `dr_mode = "peripheral"` foi implementado no workflow, mas o resultado no
  aparelho ainda não foi relatado.
- Hipóteses ainda abertas: detecção de VBUS/ID, fornecimento do PHY, hub interno ou
  cabo sem fios de dados.

## Kodi e sessão gráfica

- O pacote Kodi do Debian bookworm suporta `--windowing=gbm`.
- Com GBM direto, o Kodi usa o modo nativo do painel sem rotacionar. No X55 (painel
  720x1280) isso deixava a interface girada. A solução atual é Weston (backend
  DRM, shell kiosk) com rotação na saída `DSI-1` (o valor usado até agora, `270`, é
  inválido; ver abaixo).
- Em versões do Weston desta distro o backend se chama `drm-backend.so`, não `drm`.
- **`transform=270` é inválido no Weston.** As man pages do Weston (`weston.ini(5)` e
  `weston-drm(7)`) listam só `normal`, `rotate-90`, `rotate-180`, `rotate-270` e as
  variantes `flipped-*`. O `weston.ini` do repo usava `transform=270`. O efeito exato
  de um valor inválido (ignorar a linha ou rejeitar a saída) **não foi verificado**;
  o `weston.log` mostra se ele registrou `Invalid transform`.
- **Hipótese consistente com os testes:** se o Weston ignorou o valor, a saída ficou
  `normal`. Isso explicaria a X35H "funcionar certinho" (ela quer `normal`) e o X55
  continuar sem a rotação desejada.
- **X35S e X35H:** a wiki da ROCKNIX dá a mesma tela (3,5", 640x480) e o mesmo DTB
  para as duas ("a X35H é a versão horizontal da X35S"). O DTS tem `rotation = <0>`.
  Não há evidência de rotação diferente entre elas; o esperado é `normal` nas duas.
  (Uma afirmação anterior deste projeto, de que a X35S precisaria de rotação própria
  por ser "vertical", não tem base e foi retirada.)
- **X55:** painel 720x1280 (retrato) com orientação DRM `left-up`. O sentido correto
  em nomenclatura do Weston (`rotate-90` ou `rotate-270`) **não foi validado**; por isso
  o valor é editável em `/boot/walkmam.conf` (ver `build.md`).

## Itens que apareceram nos logs e ainda não foram tratados

- `va_openDriver() returns -1`: sem decodificação de vídeo por hardware via VA-API.
  O módulo `hantro_vpu` carrega, então vale investigar outro caminho.
- `asoc-simple-card: parse error` (probe adiado): o áudio ainda não funciona.

## Como diagnosticar sem serial, rede ou solda

O serviço `dump-diagnostico` grava `diagnostico.txt` na partição FAT (`/boot`)
depois do boot. Tire o cartão, abra no PC e leia. O arquivo inclui `dmesg`,
`/proc/bus/input/devices`, módulos, UDC, rede e logs do Kodi/Weston.
