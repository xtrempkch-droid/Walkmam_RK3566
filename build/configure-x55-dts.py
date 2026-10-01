#!/usr/bin/env python3
"""Use the ROCKNIX X55 joypad binding with one driver instance."""

import re
import sys
from pathlib import Path


ROCKNIX_JOYPAD = """
\tjoypad: rocknix-joypad {
\t\tcompatible = "rocknix-joypad";
\t\tstatus = "okay";
\t\tjoypad-name = "retrogame_joypad";
\t\tjoypad-product = <0x1101>;
\t\tjoypad-revision = <0x0100>;
\t\tjoypad-vendor = <0x484B>;

\t\tio-channel-names = "key-RY", "key-RX", "key-LY", "key-LX";
\t\tio-channels = <&saradc 2>, <&saradc 3>, <&saradc 0>, <&saradc 1>;
\t\tpinctrl-names = "default";
\t\tpinctrl-0 = <&btn_pins_ctrl>;
\t\tbutton-adc-scale = <2>;
\t\tbutton-adc-deadzone = <216>;
\t\tbutton-adc-fuzz = <54>;
\t\tbutton-adc-flat = <54>;
\t\tabs_x-p-tuning = <180>;
\t\tabs_x-n-tuning = <180>;
\t\tabs_y-p-tuning = <180>;
\t\tabs_y-n-tuning = <180>;
\t\tabs_rx-p-tuning = <180>;
\t\tabs_rx-n-tuning = <180>;
\t\tabs_ry-p-tuning = <180>;
\t\tabs_ry-n-tuning = <180>;
\t\tpoll-interval = <10>;

\t\tsw1 {
\t\t\tgpios = <&gpio4 RK_PA0 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "GPIO DPAD-UP";
\t\t\tlinux,code = <BTN_DPAD_UP>;
\t\t};
\t\tsw2 {
\t\t\tgpios = <&gpio4 RK_PA1 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "GPIO DPAD-DOWN";
\t\t\tlinux,code = <BTN_DPAD_DOWN>;
\t\t};
\t\tsw3 {
\t\t\tgpios = <&gpio3 RK_PD6 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "GPIO DPAD-LEFT";
\t\t\tlinux,code = <BTN_DPAD_LEFT>;
\t\t};
\t\tsw4 {
\t\t\tgpios = <&gpio3 RK_PD7 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "GPIO DPAD-RIGHT";
\t\t\tlinux,code = <BTN_DPAD_RIGHT>;
\t\t};
\t\tsw5 {
\t\t\tgpios = <&gpio3 RK_PD3 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "GPIO BTN-A";
\t\t\tlinux,code = <BTN_EAST>;
\t\t};
\t\tsw6 {
\t\t\tgpios = <&gpio3 RK_PD2 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "GPIO BTN-B";
\t\t\tlinux,code = <BTN_SOUTH>;
\t\t};
\t\tsw7 {
\t\t\tgpios = <&gpio3 RK_PD4 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "GPIO BTN-Y";
\t\t\tlinux,code = <BTN_WEST>;
\t\t};
\t\tsw8 {
\t\t\tgpios = <&gpio3 RK_PD5 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "GPIO BTN-X";
\t\t\tlinux,code = <BTN_NORTH>;
\t\t};
\t\tsw9 {
\t\t\tgpios = <&gpio4 RK_PA4 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "BTN_SELECT";
\t\t\tlinux,code = <BTN_SELECT>;
\t\t};
\t\tsw10 {
\t\t\tgpios = <&gpio4 RK_PA2 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "BTN_START";
\t\t\tlinux,code = <BTN_START>;
\t\t};
\t\tsw11 {
\t\t\tgpios = <&gpio3 RK_PB7 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "GPIO BTN_F";
\t\t\tlinux,code = <BTN_MODE>;
\t\t};
\t\tsw12 {
\t\t\tgpios = <&gpio4 RK_PA7 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "BTN_THUMBL";
\t\t\tlinux,code = <BTN_THUMBL>;
\t\t};
\t\tsw13 {
\t\t\tgpios = <&gpio4 RK_PB0 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "BTN_THUMBR";
\t\t\tlinux,code = <BTN_THUMBR>;
\t\t};
\t\tsw14 {
\t\t\tgpios = <&gpio3 RK_PC6 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "GPIO BTN_TR";
\t\t\tlinux,code = <BTN_TR>;
\t\t};
\t\tsw15 {
\t\t\tgpios = <&gpio3 RK_PC7 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "GPIO BTN_TR2";
\t\t\tlinux,code = <BTN_TR2>;
\t\t};
\t\tsw16 {
\t\t\tgpios = <&gpio3 RK_PD0 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "GPIO BTN_TL";
\t\t\tlinux,code = <BTN_TL>;
\t\t};
\t\tsw17 {
\t\t\tgpios = <&gpio3 RK_PD1 GPIO_ACTIVE_LOW>;
\t\t\tlabel = "GPIO BTN_TL2";
\t\t\tlinux,code = <BTN_TL2>;
\t\t};
\t};
"""


def block_end(dts: str, open_brace: int) -> int:
    depth = 0
    in_string = False
    in_line_comment = False
    in_block_comment = False
    escaped = False
    i = open_brace

    while i < len(dts):
        char = dts[i]
        next_char = dts[i + 1] if i + 1 < len(dts) else ""

        if in_line_comment:
            if char == "\n":
                in_line_comment = False
        elif in_block_comment:
            if char == "*" and next_char == "/":
                in_block_comment = False
                i += 1
        elif in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == "/" and next_char == "/":
            in_line_comment = True
            i += 1
        elif char == "/" and next_char == "*":
            in_block_comment = True
            i += 1
        elif char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return i

        i += 1

    raise ValueError("Could not locate the end of a DTS node")


def remove_nodes(dts: str, node_pattern: str) -> str:
    pattern = re.compile(rf"(?m)^[ \t]*{node_pattern}[ \t]*\{{")
    blocks = []
    for match in pattern.finditer(dts):
        end = block_end(dts, match.end() - 1) + 1
        if end < len(dts) and dts[end] == ";":
            end += 1
        if end < len(dts) and dts[end] == "\n":
            end += 1
        blocks.append((match.start(), end))

    for start, end in reversed(blocks):
        dts = dts[:start] + dts[end:]
    return dts


def root_node_end(dts: str) -> int:
    root = re.search(r"(?m)^/\s*\{", dts)
    if not root:
        raise ValueError("Could not locate the DTS root node")
    return block_end(dts, dts.index("{", root.start()))


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} <rk3566-powkiddy-x55.dts>")

    dts_path = Path(sys.argv[1])
    dts = dts_path.read_text()
    dts = remove_nodes(
        dts,
        r"(?:joypad:\s*rocknix-joypad|"
        r"gpio_keys_control:\s*gpio-keys-control|"
        r"adc_joystick:\s*adc-joystick|"
        r"x55_gpio_keys:\s*gpio-keys-gamepad|"
        r"x55_joystick:\s*adc-joystick)",
    )
    dts = re.sub(r"\n(?:[ \t]*\n){2,}", "\n\n", dts)

    try:
        root_end = root_node_end(dts)
    except ValueError as error:
        raise SystemExit(f"{error} in {dts_path}") from error

    dts = (
        dts[:root_end].rstrip()
        + "\n\n"
        + ROCKNIX_JOYPAD.lstrip("\n")
        + dts[root_end:]
    )
    dts_path.write_text(dts)
    print(f"Installed the ROCKNIX X55 joypad node in {dts_path}")


if __name__ == "__main__":
    main()
