#!/usr/bin/env python3
"""Mostra, de forma legível, o nó rocknix-joypad de um DTB/DTS decompilado.

Uso:
  tools/joypad_from_dtb.py <arquivo.dtb|arquivo.dts> [--compare-x55 build/configure-x55-dts.py]

Um .dtb decompilado perde os rótulos (&gpio4, RK_PA0, BTN_EAST). Este script
resolve os phandles de GPIO para banco/pino e os códigos de tecla para nomes, e
opcionalmente compara com o mapa do X55 embutido no configure-x55-dts.py.
Não infere nada: só traduz o que está no arquivo.
"""

import re
import subprocess
import sys
from pathlib import Path

# Endereços dos controladores GPIO do RK3566 (rk356x.dtsi).
GPIO_BANKS = {
    "fdd60000": 0,
    "fe740000": 1,
    "fe750000": 2,
    "fe760000": 3,
    "fe770000": 4,
}

# Códigos de linux/input-event-codes.h usados por gamepads.
KEY_NAMES = {
    0x130: "BTN_SOUTH", 0x131: "BTN_EAST", 0x132: "BTN_C", 0x133: "BTN_NORTH",
    0x134: "BTN_WEST", 0x135: "BTN_Z", 0x136: "BTN_TL", 0x137: "BTN_TR",
    0x138: "BTN_TL2", 0x139: "BTN_TR2", 0x13A: "BTN_SELECT", 0x13B: "BTN_START",
    0x13C: "BTN_MODE", 0x13D: "BTN_THUMBL", 0x13E: "BTN_THUMBR",
    0x220: "BTN_DPAD_UP", 0x221: "BTN_DPAD_DOWN",
    0x222: "BTN_DPAD_LEFT", 0x223: "BTN_DPAD_RIGHT",
}


def load_dts(path: Path) -> str:
    if path.suffix == ".dtb":
        out = subprocess.run(
            ["dtc", "-I", "dtb", "-O", "dts", str(path)],
            capture_output=True, text=True, check=False,
        )
        if not out.stdout:
            raise SystemExit(f"dtc não gerou saída para {path}: {out.stderr.strip()}")
        return out.stdout
    return path.read_text()


def find_block(text: str, header_re: str):
    """Devolve (inicio, fim) do primeiro bloco cujo cabeçalho casa com header_re."""
    m = re.search(header_re, text)
    if not m:
        return None
    open_idx = text.index("{", m.start())
    depth = 0
    for i in range(open_idx, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return m.start(), i + 1
    return None


def phandle_to_bank(text: str) -> dict:
    """Mapeia phandle -> número do banco GPIO, pelos nós gpio@<endereço>."""
    result = {}
    for m in re.finditer(r"gpio@([0-9a-f]+)\s*\{", text):
        addr = m.group(1)
        if addr not in GPIO_BANKS:
            continue
        blk = find_block(text[m.start():], r"gpio@" + addr + r"\s*\{")
        if not blk:
            continue
        body = text[m.start():][blk[0]:blk[1]]
        ph = re.search(r"phandle\s*=\s*<(0x[0-9a-fA-F]+)>", body)
        if ph:
            result[int(ph.group(1), 16)] = GPIO_BANKS[addr]
    return result


def pin_name(n: int) -> str:
    return f"RK_P{'ABCD'[n // 8]}{n % 8}"


def parse_joypad(text: str):
    blk = find_block(text, r"rocknix-joypad\s*\{")
    if not blk:
        raise SystemExit("Nenhum nó 'rocknix-joypad' encontrado neste arquivo.")
    body = text[blk[0]:blk[1]]
    banks = phandle_to_bank(text)

    header = {}
    for key in ("joypad-name", "joypad-vendor", "joypad-product",
                "io-channel-names", "io-channels", "poll-interval",
                "button-adc-scale", "button-adc-deadzone"):
        m = re.search(rf"{re.escape(key)}\s*=\s*([^;]+);", body)
        if m:
            header[key] = m.group(1).strip()

    buttons = []
    for m in re.finditer(r"(sw\d+)\s*\{", body):
        sub = find_block(body[m.start():], r"sw\d+\s*\{")
        if not sub:
            continue
        sbody = body[m.start():][sub[0]:sub[1]]
        gp = re.search(r"gpios\s*=\s*<(0x[0-9a-fA-F]+)\s+(0x[0-9a-fA-F]+)\s+(0x[0-9a-fA-F]+)>", sbody)
        lb = re.search(r'label\s*=\s*"([^"]*)"', sbody)
        cd = re.search(r"linux,code\s*=\s*<(0x[0-9a-fA-F]+)>", sbody)
        if not (gp and cd):
            continue
        ph, pin, flags = (int(g, 16) for g in gp.groups())
        code = int(cd.group(1), 16)
        buttons.append({
            "node": m.group(1),
            "label": lb.group(1) if lb else "",
            "bank": banks.get(ph),
            "phandle": ph,
            "pin": pin,
            "active_low": bool(flags & 1),
            "code": KEY_NAMES.get(code, hex(code)),
        })
    return header, buttons


def parse_x55_map(script_path: Path) -> dict:
    """Lê o mapa do X55 do configure-x55-dts.py: código -> (banco, pino)."""
    text = script_path.read_text()
    mapping = {}
    for m in re.finditer(
        r"gpios\s*=\s*<&gpio(\d)\s+RK_P([A-D])(\d)\s+\w+>;.*?linux,code\s*=\s*<(\w+)>",
        text, re.S,
    ):
        bank, letter, idx, code = m.groups()
        mapping[code] = (int(bank), "ABCD".index(letter) * 8 + int(idx))
    return mapping


def main() -> None:
    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)
    path = Path(args[0])
    x55 = None
    if "--compare-x55" in args:
        x55 = parse_x55_map(Path(args[args.index("--compare-x55") + 1]))

    header, buttons = parse_joypad(load_dts(path))
    print(f"Arquivo: {path}")
    for k, v in header.items():
        print(f"  {k} = {v}")
    print(f"\n{len(buttons)} botões GPIO:")
    print(f"  {'nó':6} {'código':14} {'GPIO':14} {'ativo':8} rótulo")
    for b in buttons:
        gpio = (f"gpio{b['bank']} {pin_name(b['pin'])}" if b["bank"] is not None
                else f"phandle {hex(b['phandle'])}?")
        print(f"  {b['node']:6} {b['code']:14} {gpio:14} "
              f"{'baixo' if b['active_low'] else 'alto':8} {b['label']}")

    if x55:
        print("\nComparação com o mapa do X55:")
        diffs = 0
        seen = set()
        for b in buttons:
            seen.add(b["code"])
            ref = x55.get(b["code"])
            here = (b["bank"], b["pin"])
            if ref is None:
                print(f"  {b['code']}: existe aqui, não existe no X55")
                diffs += 1
            elif ref != here:
                print(f"  {b['code']}: X55=gpio{ref[0]} {pin_name(ref[1])}  "
                      f"aqui=gpio{here[0]} {pin_name(here[1])}")
                diffs += 1
        for code in x55:
            if code not in seen:
                print(f"  {code}: existe no X55, não existe aqui")
                diffs += 1
        print("  Mapas idênticos." if diffs == 0 else f"  {diffs} diferença(s).")


if __name__ == "__main__":
    main()
