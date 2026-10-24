# Estado do projeto e retomada

Ponto de partida para continuar o trabalho depois de testar no aparelho. Diz o que já
está pronto, o que ainda é **hipótese** e exatamente o que testar e devolver.

## Como retomar (leia isto primeiro)

> **Estado em 2026-10-24:** o **#92 está verde** e é a imagem a usar (352 MB). Ela
> junta: boot ativo da X55 + `rotate-90` (validado), **SSH root/root**, Kodi com
> `--socket=wayland-0` (validado no X55: 2 h sem reiniciar) e **áudio I2S habilitado**
> (ainda não testado no aparelho). Os #90/#91 falharam por drift das fontes externas
> (ROCKNIX master mudou) — o CI agora fixa U-Boot/ROCKNIX/rkbin por commit.

1. Pegue o artifact `rk3566-x55-mainline-sdcard-image` do **run verde (success) mais
   recente** em Actions. Ele traz: boot ativo da X55 (`display_transform=rotate-90`),
   **SSH com senha liberado**, Kodi com `--socket=wayland-0`, áudio (I2S) habilitado e
   os logs de diagnóstico. **Não** use runs com `failure`.
2. Grave no cartão, ligue o cabo USB e faça os testes da seção **"Testes a fazer"**.
3. Confirme que o **SSH** entra: `ssh root@10.55.0.1` (senha `root`). Se entrar, dá
   para depurar ao vivo (dmesg, journalctl, `kodi.log`).
4. Me mande o **`diagnostico.txt`** e, se o Kodi não abrir, o **`kodi-start.log`**
   (e o `weston.log` quando o teste for de rotação/áudio/vídeo).
5. Com os dados eu fecho cada hipótese: a tabela **"Confirmado x hipótese"** diz o
   que ainda é suposição.

## Estado do CI

| Run | Commit | Resultado | Observação |
| --- | --- | --- | --- |
| #92 | `407fd46` (fix de fontes) | **success** | fixa U-Boot/ROCKNIX/rkbin; **use este artefato** (áudio incluído) |
| #91 | `0a7ffb2` (áudio) | failure | ROCKNIX drift: patch X35S usa `&gpio_keys_control` (não existe no mainline 6.12) |
| #90 | `da0073f` (Kodi) | failure | mesmo drift (não era o Kodi: kernel não compilava) |
| #89 | `63f4bd7` (SSH) | **success** | imagem gravada e testada no X55; Kodi resolvido ao vivo |
| #88 | `84b38ea` (diagnóstico) | **success** | Kodi/USB diagnosticáveis + variante `x55-peripheral` |
| #87 | `e30e6`/`e430e61` (fix X55) | **success** | boot ativo da X55 + `rotate-90` |
| #84 | `836f3b5` (fix) | **success** | imagem antiga (bootava com DTB da X35S) |
| #83 | `664b057` (docs) | failure | bug de aspas do #82; ignorar |
| #82 | `68c5c77` (merge USB) | failure | bug de aspas no `build.yml` |
| #81 | `42e66b7` (merge rotação) | success | — |

> **Por que o #90/#91 falharam (drift de fontes externas):** o CI clonava a
> `ROCKNIX/distribution` no **master**. Em 23/10 esse master estava no kernel **7.2**,
> tinha **removido** o patch 0012 (joypad da X55) e reescrito o 0016 (X35S) usando o
> label `&gpio_keys_control`, que **não existe** no DTS da X55 do mainline 6.12 → o
> `make dtbs` falhava. Correção: U-Boot, ROCKNIX e rkbin **fixados por commit** (os
> commits que geraram a imagem validada) + guarda que falha na hora se um patch de DTS
> for rejeitado (deixava `.rej` e um DTS inconsistente).

O #82/#83 falharam sempre no step **"Build Minimal RootFS (Debian ARM64)"**, com
`ep0: command not found` e `here-document ... delimited by end-of-file`. Causa: o step
escreve arquivos com `sudo bash -c 'cat << "EOF" ...'`, e havia **aspas simples dentro**
desse bloco (fechavam o `'...'` do `bash -c`). Corrigido no #84 (aspas duplas e o
`dump-diagnostico.sh` deixou de ser copiado inline — agora vem de `variants/` via
`install`). A armadilha está na seção final deste documento.

Últimas mudanças grandes já mescladas no `main`: rotação configurável (PR #5) e remoção
do `dr_mode = "peripheral"` forçado nos DTBs da X35S (PR #6).

## Gerar e gravar a imagem

1. No GitHub: **Actions → "Build Mainline RK3566 (Powkiddy X55) OS"** → escolha o run
   **verde mais recente** → baixe o artifact. Para gerar de novo, use *Run workflow*.
   (Um push no `main` também dispara o build automaticamente.)
2. Baixe o artifact **`rk3566-x55-mainline-sdcard-image`** (contém
   `rk3566-x55-mainline-sdcard.img.gz`).
3. Descompacte o `.gz`, grave o `.img` no cartão SD e insira no aparelho.

O nome do artifact continua "x55" só por compatibilidade: a mesma imagem atende os três
aparelhos, trocando o `FDT` no `extlinux.conf`.

## O que a imagem já tem (confirmado no código)

- **Boot:** `idbloader.img` no setor 64 e `u-boot.itb` no setor 16384; boot por
  `extlinux/extlinux.conf` na partição FAT `BOOT`; rootfs ext4 com rótulo `ROOTFS`.
- **FDT ativo:** `dtbs/rk3566-powkiddy-x55.dtb` (DTB da X55) — a imagem sai pronta para
  a X55, aparelho em teste. O DTB da X35S/X35H vai em `extlinux.conf.x35s`
  (`dtbs/rk3566-powkiddy-x35s-rocknix.dtb`, oficial da ROCKNIX com HDMI desabilitado, ou
  `dtbs/rk3566-powkiddy-x35s-nosso.dtb`, o nosso compilado). Se o DTB da X55 não for
  gerado, o step falha em vez de criar uma imagem com o FDT ausente.
- **`walkmam.conf`** na raiz da partição FAT, com `display_transform=rotate-90` (X55).
  Para X35S/X35H, troque para `normal`.
- **Entradas de boot alternativas** (presentes, mas não ativas) na pasta `extlinux/` da
  partição FAT:
  - `extlinux.conf` — a que está valendo (X55).
  - `extlinux.conf.x35s` — X35S/X35H (mesmo DTB).
  - `extlinux.conf.x35s-nosso` — nosso DTB compilado da X35S.
  - `extlinux.conf.x35s-peripheral` — DTB de teste com `dr_mode = "peripheral"` no USB.
  - `extlinux.conf.x55-peripheral` — o mesmo, mas para o DTB ativo da **X55** (use este
    para testar a ancoragem USB na X55).
  - Para usar qualquer uma: no PC, copie o conteúdo escolhido **por cima** de
    `extlinux.conf`.
- **Logs de diagnóstico no cartão** (partição FAT, leitura no PC):
  - `diagnostico.txt` — duas capturas (15s e 60s) com dmesg, entrada, USB, Kodi/Weston.
  - `kodi-start.log` — **saída do Kodi** (o motivo de a tela ficar em loop).
  - `usb-gadget.log` — o que o serviço de ancoragem USB tentou e o que achou de UDC.
  - `weston.log`/`weston-falhou.log` — compositor.
- **Diagnóstico:** `diagnostico.txt` na raiz da partição FAT, gravado pelo serviço
  `dump-diagnostico` cerca de 15 s depois do boot. Tire o cartão e leia no PC. O script
  vem de `variants/kodi/overlay/usr/local/bin/dump-diagnostico.sh` (o CI o instala com
  `install`; não há mais cópia inline no `build.yml`).
- **Acesso:** a senha do `root` é `root` e o SSH está habilitado. A imagem instala
  `/etc/ssh/sshd_config.d/10-walkmam.conf` com `PermitRootLogin yes` +
  `PasswordAuthentication yes` (o Debian 12 bloqueia login do root por senha por
  padrão — sem esse drop-in, `root:root` é recusado). Pelo cabo USB o aparelho fica
  em **10.55.0.1**. Ver "Segurança" no `docs/roadmap.md`.
- **Painel web de Wi-Fi/Bluetooth:** `walkmam-webui.service` (busybox httpd) na porta
  **8080**, servindo `variants/kodi/overlay/usr/local/share/walkmam-webui/`. Acesse
  `http://10.55.0.1:8080` pelo cabo (ou pelo IP do Wi-Fi) para procurar/conectar redes
  e parear dispositivos Bluetooth — o Kodi em si não gerencia rádio.
  Wi-Fi usa `nmcli`/`wpa_supplicant`; BT usa `bluetoothctl`/`bluez`.
- **Firmware de rádio:** o CI baixa do `linux-firmware` (tag **20260309**, sha256
  conferido) `rtw88/rtw8821c_fw.bin`, `rtl_bt/rtl8821cs_fw.bin` e a config do 8821C
  renomeada para `rtl8821cs_config.bin`.

## Confirmado x hipótese

| Item | Estado |
| --- | --- |
| Boot, painel, U-Boot, Debian/Kodi | **confirmado** (testes anteriores) |
| HDMI desabilitado resolve a tela preta | **confirmado** |
| `rocknix-joypad` no X55 (17 botões / 4 eixos) + mapa Kodi | **confirmado** |
| Weston com `drm-backend.so` + `kiosk-shell` | **confirmado** |
| Kodi do Debian bookworm é 20.1 **com Wayland** (`BUILD_WAYLAND=yes`) | **confirmado (código)** |
| X55: Kodi inicia e mostra a interface | **RESOLVIDO** (Weston criava `wayland-1`; corrigido com `--socket=wayland-0`) |
| X55: rotação da interface | **confirmado no aparelho: `rotate-90`** (landscape 1280x720) |
| USB gadget (ancoragem) no X55: rede `usb0` no PC | **confirmado** (10.55.0.1 responde e a porta 22 abre, verificado do PC em 2026-10-09) |
| Login do root por senha no SSH | **era bloqueado** (`prohibit-password`); corrigido no #89 e **validado** |
| `dr_mode = "peripheral"` faz a ancoragem USB funcionar | **hipótese** (testar `*peripheral`) |
| Sentido da rotação no X55 | **confirmado no aparelho: `rotate-90`** |
| Contagem de botões/eixos na X35H | **não medido** |
| Áudio (I2S habilitado no #92) | **a validar** no aparelho |
| Wi-Fi RTL8821CS: driver + firmware + `wpa_supplicant` | **validado ao vivo** (`wlan0`, fw 24.11.0); conexão a testar |
| Bluetooth RTL8821CS: `hci0` + firmware carregado | **validado ao vivo**; pareamento a testar |
| Painel web de Wi-Fi/BT na porta 8080 | **implementado** (validar na próxima imagem) |
| Vídeo por hardware (`va_openDriver() returns -1`) | **aberto** |

## Testes a fazer (na ordem)

### 0. Kodi não inicia no X55 (tela em loop) — ✅ RESOLVIDO em 2026-10-23

Causa raiz confirmada no aparelho: o **Weston 10.0.1 criava o socket como
`wayland-1`** (porque `WAYLAND_DISPLAY` estava no ambiente); o launcher esperava
`wayland-0`, dava timeout e matava um Weston que estava funcionando. Correção:
`--socket=wayland-0` explícito (+ 3 s antes do fallback GBM). Validado com **reboot**:
`kodi.service` ativo, Weston + Kodi em Wayland, `GUI format 720x1280`,
`xdg_output` lógico **1280x720** (landscape).

**Falta só a confirmação visual:** se a imagem estiver de cabeça para baixo, troque
`display_transform` em `walkmam.conf` para `rotate-270` (já está `rotate-90`, validado).

### 1. USB gadget na X35H (prioridade)

Objetivo: ver se, sem forçar `peripheral`, o PC enxerga a `usb0`.

1. Boot normal (sem mexer em nada) no X35H, com o cabo USB-C ligado ao PC.
2. Tire o cartão, abra o `diagnostico.txt` no PC e procure, na seção de USB:
   - `dr_mode` do nó `usb@fcc00000` — o esperado agora é **`otg`**;
   - as linhas de `dmesg` filtrado — se aparecer `failed to enable ep0out`, ainda falha.
3. **Se funcionar** (o PC lista a rede `usb0`): me diga e o item está fechado.
4. **Se falhar:** no PC, na partição FAT, copie
   `extlinux/extlinux.conf.x35s-peripheral` por cima de `extlinux/extlinux.conf`
   (isso usa o DTB com `dr_mode = "peripheral"`), boote de novo e repita o passo 2.

O mesmo teste na **X55** usa `extlinux/extlinux.conf.x55-peripheral` (o DTB ativo da
X55 com USB forçado a `peripheral`). O `usb-gadget.log` no cartão mostra o que o
serviço fez e se apareceu algum UDC.

Hipótese em teste: a única diferença de USB entre a imagem que funciona (X55) e a que
falhava era o `peripheral` que forçávamos. Se as duas opções falharem, a causa passa a
ser hardware (VBUS/ID da porta, cabo sem fios de dados, ou a porta ser host-only).

**Limitação conhecida deste diagnóstico:** o `dr_mode` que o CI imprime no log do
Actions usa `grep -A5` e acaba **não** mostrando o atributo (ele fica depois das 5
linhas). Ou seja, o log do CI **não** serve para conferir esse valor — use a seção USB
do `diagnostico.txt`, que traz o `dr_mode` do device tree em uso.

### 2. Rotação da tela no X55

1. Não precisa copiar `extlinux.conf`: a imagem já sai com o DTB da X55 **e** a rotação
   da X55 (`display_transform=rotate-90`) ativos.
2. Se a interface ficar de cabeça para baixo, edite `walkmam.conf` na partição FAT e
   troque para `display_transform=rotate-90`.
3. Me diga **qual valor deixa a interface correta** e, se possível, mande o trecho do
   `weston.log` (ele está no `diagnostico.txt`) — nele aparece se houve
   `Invalid transform`.

Valores válidos (Weston): `normal`, `rotate-90`, `rotate-180`, `rotate-270`, `flipped`,
`flipped-rotate-90`, `flipped-rotate-180`, `flipped-rotate-270`. Um valor inválido cai
em `normal`, com aviso no journal.

### 3. Gamepad na X35H

No `diagnostico.txt`, procure `/proc/bus/input/devices` e veja se aparece o
`retrogame_joypad` e com quantos botões/eixos. O mapa atual do Kodi vale para
**17 botões e 4 eixos**; se a X35H tiver outra contagem, precisamos de um mapa novo.

### 4. Áudio e vídeo

- Áudio: mande o trecho do `dmesg` com `asoc-simple-card` / `parse error`.
- Vídeo: mande a linha com `va_openDriver`.

## O que me enviar

- O **`diagnostico.txt` inteiro** (é o mais útil: tem `dmesg`, entrada, UDC/role, USB,
  Kodi e Weston).
- Se o teste for de rotação, o trecho do **`weston.log`**.
- Se for de áudio ou vídeo, o trecho do `dmesg` correspondente.

O log do CI e o `diagnostico.txt` são coisas **diferentes**: o log do CI mostra a
compilação; o `diagnostico.txt` mostra o que aconteceu no aparelho.

## Pendências de código (para eu resolver, não dependem do aparelho)

1. O dump do nó USB no log do CI usa `grep -A5` e não imprime o `dr_mode` (fica fora das
   5 linhas). Trocar por algo que mostre o atributo (ex.: `grep -A20` ou filtrar só o
   `dr_mode`). **Não refiz o build só por isso**, para não trocar o artefato que você vai
   baixar; se mexer nisso, gere um run novo e use o artefato do run mais recente.
2. O `build.yml` ainda monta a imagem **inline** (não usa o `build/create-image.sh`).
   Duplicação pendente; a rotação já não depende disso (o CI grava `rotate-90` para a
   X55, e o `create-image.sh` lê `display_transform` de `device.conf`).
3. ~~Mover o padrão de rotação do `case` do `create-image.sh` para `display_transform=`
   em `devices/<placa>/device.conf`.~~ **Feito:** `devices/*/device.conf` tem
   `display_transform`, o `build.sh` repassa como 9º argumento e o `create-image.sh` usa
   esse valor (o `case` fica só como fallback).

## Onde ficam as coisas no repositório

- `docs/findings.md` — o que foi aprendido, com marcação confirmado/hipótese.
- `docs/roadmap.md` — prioridades, incluindo o que depende de teste no aparelho.
- `docs/build.md` — fluxo de build e detalhes de painel, gamepad, rotação e USB.
- `docs/porting.md` — como adicionar outra placa.
- `.github/workflows/build.yml` — o pipeline completo (é ele que monta a imagem).
- `build/create-image.sh` — empacotador local (o CI **não** usa este ainda).
- `variants/kodi/overlay/` — serviços e scripts que vão para o rootfs (Weston, Kodi,
  `dump-diagnostico`, USB gadget).
- `tools/joypad_from_dtb.py` — extrai o nó `rocknix-joypad` de um `.dtb` e compara com
  o mapa do X55.

## Armadilhas já vividas (para não repetir)

- Terminador de heredoc dentro de um `run: |` precisa ficar na indentação base do bloco.
- `: ` (dois-pontos e espaço) no `name:` de um step quebra o YAML.
- `find` retorna 0 mesmo quando não acha nada — não dá para checar por código de saída.
- Em `sudo bash -c '...'` no `build.yml`, **não usar aspas simples** no conteúdo: elas
  fecham o `'...'` do `bash -c` e quebram o heredoc. Foi o que derrubou o CI no run #82,
  com `ep0: command not found` e
  `here-document ... delimited by end-of-file (wanted 'EOF')`. Usar aspas duplas.
- **`bash -n` não pega esse erro** de aspas: o número de aspas pode ficar par e o
  arquivo "parseia", mas o heredoc sai errado. Validar a estrutura à parte.
- Não duplicar scripts entre o `build.yml` e `variants/`: o `dump-diagnostico.sh` era
  mantido nos dois lugares e as cópias divergiram. Agora o CI instala o arquivo do
  overlay com `install` (fonte única em `variants/kodi/overlay/usr/local/bin/`).
- Alterar um `.dts` **depois** de `make dtbs` não afeta o `.dtb` já compilado.
- O log do CI e o `diagnostico.txt` são arquivos diferentes (ver acima).
- Não inventar GPIOs, nomes de `CONFIG_` nem valores de pinagem: usar só fonte confirmada.
