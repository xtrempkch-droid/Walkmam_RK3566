#!/usr/bin/env python3
"""Converte o painel de um .dts de kernel de fabricante (Rockchip BSP) no overlay
`rocknix,generic-dsi` usado pela ROCKNIX/REG Linux.

Por que isto existe
-------------------
O R35S/R36S (RK3326) sai de fábrica com vários modelos de tela diferentes. Cada
modelo precisa da sua própria sequência de inicialização DSI e dos seus timings.
O kernel mainline só tem um driver fixo para o painel "original"
(`elida,kd35t133`); para os outros o caminho que a comunidade usa é o driver
`rocknix,generic-dsi`, que recebe **tudo por device tree**, num overlay:

    /plugin/;
    / { fragment@0 {
        target-path = "/dsi@ff450000/panel@0";
        __overlay__ {
            compatible = "rocknix,generic-dsi";
            panel_description = "G ...", "M ...", "I ...", ...;
        };
    }; };

Este script faz a tradução mecânica do bloco `panel@0` de um .dts/.dtsi de
fabricante (decompilado de um .dtb) para essa lista de strings.

O formato foi **conferido contra o overlay oficial** `mipi-panel.dtbo.r36s-panel4`
do release `panel_overlays` (https://github.com/stolen/rnix/releases/tag/panel_overlays):
para o mesmo painel (`devices/game-console-r35s/dts/mipis-panel4.dts`) a lista de
strings gerada aqui é idêntica à do .dtbo oficial — use `--check-arquivo` para
repetir essa comparação a qualquer momento.

Regras que o overlay oficial revela (e que não são óbvias no código do driver):

1. `flags` do fabricante ganha o bit `MIPI_DSI_MODE_VIDEO` (0x400):
   o vendor usa 0xa03 e o overlay oficial usa 0xe03.
2. `horizontal`/`vertical` são (display, **front-porch**, **sync-len**,
   **back-porch**) — NÃO são hsync_start/hsync_end/htotal. Conferido nos números:
   vendor 640/46/2/44 -> overlay `horizontal=640,46,2,44`.
3. `delays` = prepare, reset, init, enable, ready (o "ready" não tem campo próprio
   no DTS do fabricante; aqui usamos `unprepare-delay-ms` e, se não existir,
   `init-delay-ms` — é a única incógnita desta conversão).
4. Cada passo de `panel-init-sequence` (formato Rockchip: tipo, atraso, tamanho,
   bytes...) vira um `I seq=<bytes>` com `wait=<atraso>` quando o atraso > 0.
   O tipo original fica num comentário (`# orig_cmd=0x15`), como no overlay oficial.
5. O nome do nó de timing manda no refresh: os nós "50Hz"/"75Hz" do DTS do
   fabricante traziam porches copiados do modo de 60 Hz (os dois davam 77,4 fps).
   O overlay oficial corrige o `vfront-porch` para bater no número do nome.
   A regra reconstruída (e validada nos três modos do panel4) é: se o modo do
   fabricante está a mais de 1 Hz do nome, recalcula
   `vtotal = round(clock / (htotal * fps_do_nome))` e ajusta o `vfront-porch`.
   Os modos que já batem ficam como estão. Com um ponto de dados só, trate como
   hipótese: `--check-arquivo` mostra na hora se um painel novo divergir.
6. A lista termina com o marcador `#END` (o driver usa isso para encerrar).

Exemplos
--------
    python3 tools/panel_overlay_from_dts.py \
        devices/game-console-r35s/dts/mipis-panel4.dts \
        -o devices/game-console-r35s/dts/panel-overlay/mipi-panel.dts

    # conferir a conversão contra o .dtbo oficial (precisa do arquivo baixado)
    python3 tools/panel_overlay_from_dts.py \
        devices/game-console-r35s/dts/mipis-panel4.dts --check-arquivo /tmp/panel4.dtbo
"""

from __future__ import annotations

import argparse
import re
import struct
import sys

# MIPI_DSI_MODE_VIDEO — o driver generic-dsi espera esse bit ligado nos flags.
MIPI_DSI_MODE_VIDEO = 0x400

FORMATOS = {0: "rgb888", 1: "rgb666", 2: "rgb666_packed", 3: "rgb565"}


# ---------------------------------------------------------------------------
# leitura de pedaços do .dts (texto)
# ---------------------------------------------------------------------------
def bloco(texto: str, cabecalho: str, inicio: int = 0) -> str | None:
    """Devolve o conteúdo entre as chaves do bloco cujo cabeçalho casa com
    `cabecalho` (regex). Devolve None se não achar."""
    m = re.search(cabecalho, texto[inicio:])
    if not m:
        return None
    abre = texto.find("{", inicio + m.end() - 1)
    if abre < 0:
        return None
    profundidade = 0
    for pos in range(abre, len(texto)):
        c = texto[pos]
        if c == "{":
            profundidade += 1
        elif c == "}":
            profundidade -= 1
            if profundidade == 0:
                return texto[abre + 1:pos]
    return None


def numero(onde: str, nome: str, padrao: int | None = None) -> int | None:
    m = re.search(rf"(?:^|\s){re.escape(nome)}\s*=\s*<\s*(0x[0-9a-fA-F]+|\d+)\s*>", onde)
    if not m:
        return padrao
    return int(m.group(1), 0)


def bytes_de_hex(lista: str) -> list[int]:
    return [int(b, 16) for b in re.findall(r"[0-9a-fA-F]{2}", lista)]


# ---------------------------------------------------------------------------
# conversão
# ---------------------------------------------------------------------------
def passos_de_init(sequencia: list[int]) -> list[str]:
    """Divide `panel-init-sequence` (tipo, atraso, tamanho, dados...) em passos."""
    saida: list[str] = []
    i = 0
    while i + 2 < len(sequencia):
        tipo, atraso, tamanho = sequencia[i], sequencia[i + 1], sequencia[i + 2]
        dados = sequencia[i + 3:i + 3 + tamanho]
        if len(dados) != tamanho:
            raise SystemExit(
                f"panel-init-sequence truncada no passo {i}: pede {tamanho} byte(s) "
                f"e só há {len(dados)}"
            )
        if not dados:
            raise SystemExit(f"panel-init-sequence com passo vazio no offset {i}")
        passo = "I seq=" + "".join(f"{b:02x}" for b in dados)
        if atraso:
            passo += f" wait={atraso}"
        passo += f" # orig_cmd=0x{tipo:x}"
        saida.append(passo)
        i += 3 + tamanho
    if i != len(sequencia):
        raise SystemExit(
            f"panel-init-sequence com {len(sequencia) - i} byte(s) sobrando no fim"
        )
    return saida


def modos_de_video(painel: str, avisos: list[str]) -> list[str]:
    """Traduz `display-timings` em linhas `M ...` (uma por modo)."""
    timings = bloco(painel, r"display-timings\s*\{")
    if not timings:
        raise SystemExit("painel sem display-timings: não há como montar os modos `M`")

    saida: list[str] = []
    for m in re.finditer(r"([A-Za-z0-9_-]+)\s*\{", timings):
        nome = m.group(1)
        if nome in ("display-timings", "timings"):
            continue
        conteudo = bloco(timings, re.escape(nome) + r"\s*\{", m.start())
        if conteudo is None:
            continue
        clock_hz = numero(conteudo, "clock-frequency")
        hactive = numero(conteudo, "hactive")
        vactive = numero(conteudo, "vactive")
        if not clock_hz or not hactive or not vactive:
            continue
        hfp = numero(conteudo, "hfront-porch", 0)
        hsync = numero(conteudo, "hsync-len", 0)
        hbp = numero(conteudo, "hback-porch", 0)
        vfp = numero(conteudo, "vfront-porch", 0)
        vsync = numero(conteudo, "vsync-len", 0)
        vbp = numero(conteudo, "vback-porch", 0)
        clock_khz = clock_hz // 1000

        htotal = hactive + hfp + hsync + hbp
        vtotal = vactive + vfp + vsync + vbp
        fps = clock_hz / (htotal * vtotal) if htotal and vtotal else 0

        # O nome do nó ("60Hz") é a referência de refresh do fabricante.
        nominal = re.match(r"(\d+(?:[.,]\d+)?)\s*[Hh]z", nome)
        alvo = float(nominal.group(1).replace(",", ".")) if nominal else None
        if alvo and htotal and abs(fps - alvo) > 1.0:
            vtotal_alvo = round(clock_hz / (htotal * alvo))
            vfp_novo = vtotal_alvo - vactive - vsync - vbp
            if vfp_novo > 0:
                avisos.append(
                    f"modo '{nome}': porches do fabricante davam {fps:.1f} fps; "
                    f"vfront-porch {vfp} -> {vfp_novo} para bater em {alvo:g} fps"
                )
                vfp = vfp_novo
                vtotal = vtotal_alvo
                fps = clock_hz / (htotal * vtotal)

        linha = (
            f"M clock={clock_khz} "
            f"horizontal={hactive},{hfp},{hsync},{hbp} "
            f"vertical={vactive},{vfp},{vsync},{vbp}"
        )
        if not saida:
            # o primeiro modo é o preferido do fabricante (native-mode).
            linha += " default=1"
        if alvo:
            linha += f" # {alvo:g}"
        else:
            linha += f" # {fps:.1f}fps"
        saida.append(linha)
    if not saida:
        raise SystemExit("display-timings sem nenhum modo utilizável")
    return saida


def descricao_do_painel(painel: str, avisos: list[str]) -> list[str]:
    largura = numero(painel, "width-mm", 0)
    altura = numero(painel, "height-mm", 0)
    prepare = numero(painel, "prepare-delay-ms", 0)
    reset = numero(painel, "reset-delay-ms", 0)
    init = numero(painel, "init-delay-ms", 0)
    enable = numero(painel, "enable-delay-ms", 0)
    ready = numero(painel, "unprepare-delay-ms")
    if ready is None:
        ready = init
        avisos.append(
            "`unprepare-delay-ms` ausente: usar `init-delay-ms` como `ready` dos delays"
        )
    formato_cru = numero(painel, "dsi,format", 0) or 0
    if formato_cru not in FORMATOS:
        avisos.append(f"dsi,format={formato_cru} desconhecido: usando rgb888")
        formato_cru = 0
    formato = FORMATOS[formato_cru]
    lanes = numero(painel, "dsi,lanes", 4) or 4
    flags = numero(painel, "dsi,flags", 0) or 0
    flags_original = flags
    flags |= MIPI_DSI_MODE_VIDEO
    if flags != flags_original:
        avisos.append(
            f"flags 0x{flags_original:03x} -> 0x{flags:03x}: bit 0x400 "
            "(MIPI_DSI_MODE_VIDEO) que o generic-dsi espera"
        )

    linha_g = (
        f"G size={largura},{altura} "
        f"delays={prepare},{reset},{init},{enable},{ready} "
        f"format={formato} lanes={lanes} flags=0x{flags:03x}"
    )
    descricao = [
        linha_g,
        *modos_de_video(painel, avisos),
        *passos_de_init(_init_sequence(painel)),
        "#END",
    ]
    return descricao


def _init_sequence(painel: str) -> list[int]:
    m = re.search(r"panel-init-sequence\s*=\s*\[([^\]]*)\]", painel, re.S)
    if not m:
        raise SystemExit("painel sem `panel-init-sequence`")
    return bytes_de_hex(m.group(1))


# ---------------------------------------------------------------------------
# emissão do overlay
# ---------------------------------------------------------------------------
def overlay_dts(descricao: list[str], alvo: str, origem: str, avisos: list[str]) -> str:
    cabeçalho = [
        "/dts-v1/;",
        "/plugin/;",
        "",
        "/*",
        f" * Overlay de painel gerado por tools/panel_overlay_from_dts.py",
        f" * a partir de: {origem}",
        " *",
        " * Instalar como overlays/mipi-panel.dtbo na partição de boot (ver",
        " * docs/r35s-rk3326.md). Trocar o arquivo troca o modelo de tela:",
        " * o R35S/R36S sai de fábrica com painéis diferentes.",
        " *",
        " * Não editar à mão: rode o script de novo.",
        " */",
    ]
    if avisos:
        cabeçalho += ["/*"] + [f" * ATENÇÃO: {a}" for a in avisos] + [" */"]
    cabeçalho += [
        "",
        "/ {",
        "\tfragment@0 {",
        f'\t\ttarget-path = "{alvo}";',
        "",
        "\t\t__overlay__ {",
        '\t\t\tcompatible = "rocknix,generic-dsi";',
    ]
    linhas = []
    for i, item in enumerate(descricao):
        sufixo = ";" if i == len(descricao) - 1 else ","
        linhas.append(f'\t\t\t\t"{item}"{sufixo}')
    corpo = "\n".join(linhas)
    return (
        "\n".join(cabeçalho)
        + "\n\t\t\tpanel_description = "
        + corpo.lstrip("\t")
        + "\n\t\t};\n\t};\n};\n"
    )


# ---------------------------------------------------------------------------
# conferência contra um .dtbo oficial
# ---------------------------------------------------------------------------
def descricao_de_dtbo(caminho: str) -> list[str]:
    """Lê as strings de `panel_description` de um .dtbo (FDT binário)."""
    dados = open(caminho, "rb").read()
    _, _, off_struct, off_strings, _, _, _, _, tam_strings, _ = struct.unpack(
        ">10I", dados[:40]
    )
    strings = dados[off_strings:off_strings + tam_strings]
    pos = off_struct

    def nome(off: int) -> str:
        fim = strings.find(b"\0", off)
        return strings[off:fim].decode("utf-8", "replace")

    while True:
        (tok,) = struct.unpack(">I", dados[pos:pos + 4])
        pos += 4
        if tok == 1:  # BEGIN_NODE
            fim = dados.find(b"\0", pos)
            pos = (fim + 4) & ~3
        elif tok == 2:  # END_NODE
            continue
        elif tok == 3:  # PROP
            tamanho, nome_off = struct.unpack(">II", dados[pos:pos + 8])
            pos += 8
            valor = dados[pos:pos + tamanho]
            pos = (pos + tamanho + 3) & ~3
            if nome(nome_off) == "panel_description":
                return [
                    s.decode("utf-8", "replace")
                    for s in valor.split(b"\0")
                    if s.strip()
                ]
        elif tok == 4:  # NOP
            continue
        elif tok == 9:  # END
            break
        else:
            raise SystemExit(f"token inesperado {tok} no .dtbo")
    raise SystemExit("propriedade panel_description não encontrada no .dtbo")


def normalizar(itens: list[str]) -> list[str]:
    return [re.sub(r"\s+", " ", i).strip() for i in itens]


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Gera um overlay rocknix,generic-dsi a partir de um .dts de fabricante"
    )
    ap.add_argument("dts", help=".dts do fabricante (ex.: mipis-panel4.dts)")
    ap.add_argument("-o", "--saida", help="arquivo .dts de overlay a escrever")
    ap.add_argument(
        "--alvo",
        default="/dsi@ff450000/panel@0",
        help="target-path do overlay (padrão: /dsi@ff450000/panel@0, RK3326)",
    )
    ap.add_argument(
        "--check-arquivo",
        metavar="DTBO",
        help="compara com um .dtbo oficial e sai 1 se divergir",
    )
    args = ap.parse_args()

    texto = open(args.dts, encoding="utf-8", errors="replace").read()
    painel = bloco(texto, r"panel@0\s*\{")
    if painel is None:
        raise SystemExit(f"{args.dts}: nó `panel@0` não encontrado")

    avisos: list[str] = []
    descricao = descricao_do_painel(painel, avisos)

    if args.check_arquivo:
        oficial = normalizar(descricao_de_dtbo(args.check_arquivo))
        gerado = normalizar(descricao)
        if oficial == gerado:
            print(f"OK: {len(gerado)} strings idênticas às do {args.check_arquivo}")
            return 0
        print("DIVERGÊNCIA:", file=sys.stderr)
        for i in range(max(len(oficial), len(gerado))):
            a = oficial[i] if i < len(oficial) else "<faltando>"
            b = gerado[i] if i < len(gerado) else "<faltando>"
            if a != b:
                print(f"  [{i}] oficial: {a}", file=sys.stderr)
                print(f"      gerado : {b}", file=sys.stderr)
        return 1

    texto_overlay = overlay_dts(descricao, args.alvo, args.dts, avisos)
    if args.saida:
        with open(args.saida, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(texto_overlay)
        print(f"--> {args.saida}")
        for a in avisos:
            print(f"!!! {a}")
    else:
        sys.stdout.write(texto_overlay)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
