# Build

## Fluxo completo

O workflow em `.github/workflows/build.yml` continua responsável por baixar as fontes, compilar U-Boot/kernel, montar o rootfs Debian e produzir a imagem de referência X35S. Ele prioriza o DTB oficial obtido da ROCKNIX e usa o DTB compilado como fallback. Se nenhum dos dois estiver presente, o job falha explicitamente em vez de criar uma imagem com uma referência FDT ausente. Por compatibilidade, o nome histórico do artifact continua identificando X55, embora o FDT ativo da imagem seja selecionado para X35S; isso não declara validação em hardware.

## X55: diagnóstico de tela preta

O diagnóstico enviado após o teste no X55 identifica o painel MIPI-DSI e o modo 720x1280, e o Kodi informa que escolheu `DSI-1` (não HDMI). Ao mesmo tempo, o kernel registra `Failed to register component: -517` no host DSI e repetidos `POST_BUF_EMPTY irq err at vp1`. Portanto, o log não confirma que o Kodi selecionou HDMI como saída; aponta uma falha na apresentação pelo caminho DSI/VOP.

Como teste do conflito conhecido entre HDMI e o display interno, o workflow agora compila o DTB X55 com o nó HDMI desabilitado, seguindo o workaround já usado para o X35S. Isso remove a saída HDMI externa enquanto o workaround estiver ativo. A hipótese só pode ser confirmada repetindo o teste no aparelho com a nova imagem; se o painel continuar preto, o erro do caminho DSI/VOP requer investigação separada.

## X55: orientação e controle

O diagnóstico posterior enumera apenas os dispositivos de power e volume, pois o
botão não está sendo registrado no kernel. A solução de controle usada pela
comunidade ROCKNIX é o driver `rocknix-joypad`, não a combinação genérica
`gpio-keys`/`adc-joystick` testada anteriormente. O build agora mantém o binding
ROCKNIX para combinar GPIOs e ADCs numa única entrada de gamepad, e adapta o
uso legado de `input-polldev` à API de polling disponível no Linux 6.12. Também
normaliza o DTS para conter somente um nó `rocknix-joypad`.

O nó precisa ser filho direto da raiz do device tree porque o driver é um
`platform_driver`. O diagnóstico da primeira imagem ROCKNIX mostrou que um nó
aninhado sob o controlador DSI não é registrado como dispositivo de entrada;
o workflow agora verifica que o nó está na raiz antes de compilar o DTB.
Após corrigir o DTB no X55 conectado, o kernel registrou `retrogame_joypad`
com 4 eixos e 17 botões, e o Kodi registrou o joystick. A captura no aparelho
confirmou eventos de pressionar/soltar nos quatro sentidos do D-pad e nos
controles físicos mapeados; os dois analógicos percorreram seus quatro eixos
até quase o curso completo. Como o popup “New controller detected” aparecia
sem permitir navegar, foi adicionado um mapa Kodi específico para
`retrogame_joypad`. D-pad para cima e A foram confirmados na interface após
instalá-lo. A GPIO fantasma `BTN_MODE` não é mapeada para uma ação, pois fica
ativa em repouso.

O mapa em
`variants/kodi/overlay/usr/share/kodi/addons/peripheral.joystick/resources/buttonmaps/xml/linux/retrogame_joypad_17b_4a.xml`
define os 17 botões e 4 eixos na ordem observada no aparelho; o workflow o
instala no rootfs após instalar os pacotes do Kodi. A disposição física segue o
Nintendo Switch Pro Controller: A à direita, B abaixo, X acima e Y à esquerda.

As imagens X55 incluem o marcador `walkmam_x55_gamepad=rocknix-v1` na linha de
boot. O diagnóstico registra `/proc/cmdline` e os nós ativos do device tree:
isso permite distinguir uma falha de probe do driver de uma inicialização
acidental pela imagem/DTB anterior.

O painel declara orientação DRM `left-up`, que o console aplica, mas o Kodi em
GBM direto escolhe o modo DSI nativo 720x1280 sem transformar a superfície. Para
girar somente a interface Kodi, a sessão agora inicia Weston no backend DRM,
com shell kiosk, e executa Kodi como cliente Wayland. `/etc/xdg/weston/weston.ini`
aplica `transform=270` somente à saída `DSI-1`; o terminal permanece sob a
orientação existente do framebuffer. Isso adiciona uma etapa de composição,
portanto a orientação e a reprodução de vídeo acelerada precisam ser
confirmadas no X55 com a nova imagem antes de considerar a rotação concluída.

O primeiro diagnóstico da v6 mostra `kodi.service` encerrando com status 1
antes da criação de `kodi.log`; portanto, não confirma que o Kodi chegou a
iniciar. O `weston.log` revelou `unknown backend "drm"`: nesta versão o Weston
espera o nome do módulo `drm-backend.so`, e não o alias `drm`. O launcher foi
corrigido para usar esse nome. O script de diagnóstico inclui o log Weston, os
nós DRM e o estado completo do serviço; erros do compositor também são
copiados para o journal. Reinicializações repetidamente malsucedidas são
limitadas.

## Empacotamento local

`build/build.sh <device> <variant>` empacota artefatos já preparados. Por exemplo:

```sh
build/build.sh powkiddy-x55 kodi
```

O script espera por `uboot/idbloader.img`, `uboot/u-boot.itb`, `kernel/arch/arm64/boot/Image`, o DTB indicado em `devices/<device>/device.conf` e uma árvore `rootfs/` que contenha o sistema da variante. `variant.conf` declara `status` e o caminho relativo do manifesto de pacotes; variantes planejadas sem implementação não podem ser empacotadas. É possível substituir os diretórios com `WALKMAN_UBOOT_DIR`, `WALKMAN_KERNEL_DIR`, `WALKMAN_ROOTFS_DIR`, `WALKMAN_OUTPUT_DIR` e o DTB com `WALKMAN_DTB_SOURCE`. Caminhos relativos são resolvidos a partir da raiz do repositório. A criação de partições exige `sudo` e as ferramentas `dd`, `parted`, `losetup`, `mkfs.vfat`, `mkfs.ext4` e `gzip`.

As imagens não são sobrescritas: escolha um nome novo com `WALKMAN_IMAGE_NAME` ou remova manualmente um artefato anterior antes de repetir o comando.
