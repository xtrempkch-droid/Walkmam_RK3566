# Estado do projeto e retomada

Ponto de partida para continuar o trabalho depois de testar no aparelho. Diz o que já
está pronto, o que ainda é **hipótese** e exatamente o que testar e devolver.

Última mudança grande já mesclada no `main`: rotação configurável (PR #5) e remoção do
`dr_mode = "peripheral"` forçado nos DTBs da X35S (PR #6).

## Gerar e gravar a imagem

1. No GitHub: **Actions → "Build Mainline RK3566 (Powkiddy X55) OS" → Run workflow**.
   (Um push no `main` também dispara o build automaticamente.)
2. Baixe o artifact **`rk3566-x55-mainline-sdcard-image`** (contém
   `rk3566-x55-mainline-sdcard.img.gz`).
3. Descompacte o `.gz`, grave o `.img` no cartão SD e insira no aparelho.

O nome do artifact continua "x55" só por compatibilidade: a mesma imagem atende os três
aparelhos, trocando o `FDT` no `extlinux.conf`.

## O que a imagem já tem (confirmado no código)

- **Boot:** `idbloader.img` no setor 64 e `u-boot.itb` no setor 16384; boot por
  `extlinux/extlinux.conf` na partição FAT `BOOT`; rootfs ext4 com rótulo `ROOTFS`.
- **FDT padrão (X35S/X35H):** `dtbs/rk3566-powkiddy-x35s-rocknix.dtb` (DTB oficial da
  ROCKNIX, com o nó HDMI desabilitado). Se o oficial não for obtido, usa
  `dtbs/rk3566-powkiddy-x35s-nosso.dtb`.
- **`walkmam.conf`** na raiz da partição FAT, com `display_transform=normal`.
- **Entradas de boot alternativas** (presentes, mas não ativas) na pasta `extlinux/` da
  partição FAT:
  - `extlinux.conf` — a que está valendo (X35S/X35H).
  - `extlinux.conf.x55` — para bootar a X55.
  - `extlinux.conf.x35s-nosso` — nosso DTB compilado.
  - `extlinux.conf.x35s-peripheral` — DTB de teste com `dr_mode = "peripheral"` no USB.
  - Para usar qualquer uma: no PC, copie o conteúdo escolhido **por cima** de
    `extlinux.conf`.
- **Diagnóstico:** `diagnostico.txt` na raiz da partição FAT, gravado pelo serviço
  `dump-diagnostico` cerca de 15 s depois do boot. Tire o cartão e leia no PC. O script
  vem de `variants/kodi/overlay/usr/local/bin/dump-diagnostico.sh` (o CI o instala com
  `install`; não há mais cópia inline no `build.yml`).
- **Acesso:** a senha do `root` é `root` e o SSH está habilitado (ver "Segurança" no
  `docs/roadmap.md`).

## Confirmado x hipótese

| Item | Estado |
| --- | --- |
| Boot, painel, U-Boot, Debian/Kodi | **confirmado** (testes anteriores) |
| HDMI desabilitado resolve a tela preta | **confirmado** |
| `rocknix-joypad` no X55 (17 botões / 4 eixos) + mapa Kodi | **confirmado** |
| Weston com `drm-backend.so` + `kiosk-shell` | **confirmado** |
| USB gadget funciona no X55 (`dr_mode` do SoC = `otg`) | **confirmado** |
| Remover `dr_mode = "peripheral"` conserta o USB na X35H | **hipótese** (não testada) |
| Sentido da rotação no X55: `rotate-90` ou `rotate-270` | **não validado** |
| Contagem de botões/eixos na X35H | **não medido** |
| Áudio (`asoc-simple-card: parse error`) e vídeo (`va_openDriver() returns -1`) | **aberto** |

## Testes a fazer (na ordem)

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

Hipótese em teste: a única diferença de USB entre a imagem que funciona (X55) e a que
falhava era o `peripheral` que forçávamos. Se as duas opções falharem, a causa passa a
ser hardware (VBUS/ID da porta, cabo sem fios de dados, ou a porta ser host-only).

### 2. Rotação da tela no X55

1. Boote a X55 usando `extlinux.conf.x55` (copie por cima de `extlinux.conf`).
2. Na partição FAT, edite `walkmam.conf` e troque para `display_transform=rotate-270`.
   (A imagem do CI grava `normal`; para a X55 é preciso editar à mão.)
3. Se a imagem ficar de cabeça para baixo, teste `display_transform=rotate-90`.
4. Me diga **qual valor deixa a interface correta** e, se possível, mande o trecho do
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
