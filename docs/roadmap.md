# Roadmap

Ordem por impacto e por risco. O que depende de teste no aparelho está marcado.

## 1. Configuração por dispositivo (a mais importante)

Hoje o workflow e o overlay do Kodi misturam coisas do X55 e da X35S/X35H.

Feito nesta rodada (ainda sem teste em hardware):

- `start-kodi-wayland.sh` lê `display_transform=<valor>` de `/boot/walkmam.conf`
  (partição FAT, editável no PC), valida contra os 8 valores do Weston, gera o
  `weston.ini` em `$XDG_RUNTIME_DIR` e avisa no journal se o valor for inválido.
- `build/create-image.sh` grava o `walkmam.conf` com o padrão do aparelho: `normal`
  para X35S/X35H, `rotate-270` para o X55 (sentido não validado).
- Removido o `dr_mode = "peripheral"` que o workflow forçava só nos DTBs da X35S (era
  a única diferença de USB para o X55, onde o gadget funciona); a imagem passou a
  oferecer também um DTB alternativo com `peripheral`
  (`extlinux.conf.x35s-peripheral`).
- `dump-diagnostico` inclui `/var/log/weston.log`, `/boot/walkmam.conf`, o `weston.ini`
  efetivo e, para o USB, o `dr_mode` em uso, os UDC e os papéis (`usb_role`).

Falta:

- Fazer o workflow usar o `create-image.sh` (hoje a imagem é montada inline — ela já
  grava o `walkmam.conf`, mas com `normal` fixo, então o X55 não recebe `rotate-270`
  automaticamente).
- Mover o padrão do `case` do `create-image.sh` para `display_transform=` no
  `device.conf` de cada aparelho.
- No X55, testar `rotate-270` e `rotate-90` editando o `walkmam.conf` e registrar qual
  deixa a interface correta.
- O mapa de botões do Kodi vira um arquivo por contagem de botões e eixos.

Aceite: imagem do X35H com interface na orientação certa e imagem do X55 na dela,
sem editar o workflow para trocar.

## 2. Fechar o gamepad na X35H (precisa de teste)

1. Gerar a imagem e ler `/proc/bus/input/devices` no `diagnostico.txt`.
2. Anotar contagem de botões e eixos do `retrogame_joypad`.
3. Se for diferente de 17/4, criar o mapa correspondente.
4. Confirmar que o DTS da X35S herda o nó `rocknix-joypad` do X55; se não herdar,
   criar o nó para a X35S a partir de fonte confirmada (sem inferir GPIOs).

## 3. USB gadget para SSH (funciona no X55, falha na X35H — precisa de teste)

O gadget funciona na X55 (`dr_mode` herdado do SoC, `otg`) e falha na X35H. Como os
DTS da X35S e da X55 não diferem em USB, a única diferença que introduzíamos era
forçar `dr_mode = "peripheral"` nos DTBs da X35S — removido nesta rodada.

1. Gravar a imagem e testar na X35H o padrão (`otg`, DTB original): ler o
   `diagnostico.txt` (agora traz o `dr_mode` em uso, o estado dos UDC e o `dmesg`
   filtrado em `dwc3`/`ep0`).
2. Se o `ep0out` continuar, repetir com a entrada alternativa
   (`extlinux.conf.x35s-peripheral`, `dr_mode = "peripheral"`) e registrar qual das
   duas funciona.
3. Se nenhuma funcionar, comparar `usb@fcc00000`/`usb2phy0_otg` do `.dtb` oficial com
   os do X55 (o CI agora imprime esses nós no log do Actions) e testar outro cabo com
   fios de dados confirmados. Considerar VBUS/ID e a porta ser host-only.

## 4. Robustez do CI

- Fixar versões: hoje o workflow clona `ROCKNIX/distribution` e o `rkbin` na ponta.
  Fixe um commit de cada, como já foi feito com o `rocknix-joypad`.
- Fazer o job falhar quando faltar o `.dtb` ou o driver, em vez de seguir (já feito
  para o FDT; vale estender ao driver do painel e ao do joypad).
- Usar o `build/create-image.sh` no workflow, em vez de manter a montagem da imagem
  duplicada dentro do YAML.
- Dar nome ao artifact pelo aparelho (`rk3566-<device>-<variant>`).
- Reduzir o que o `diagnostico.txt` despeja, ou limitar o tamanho do arquivo.

## 5. Segurança mínima

- A senha do root é `root` e o SSH está habilitado. Antes de publicar uma imagem,
  gere uma senha por build ou desative o login por senha.

## 6. Funcionalidades

- Áudio: investigar o `asoc-simple-card: parse error` (probe adiado).
- Vídeo: avaliar decodificação por hardware (`hantro_vpu` carrega, VA-API não).
- Variante `own`: hoje é só scaffold e o empacotador a recusa.

## 7. Documentação

- Atualizar o README: a X35H foi testada com o `.dtb` da X35S e funcionou. Registrar
  exatamente o que foi validado antes de mudar o estado para "suportado".
- Manter `docs/findings.md` como registro de decisões, com a marcação
  confirmado/hipótese.
