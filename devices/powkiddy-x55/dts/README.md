# Device tree

O Linux mainline v6.12 usado pelo workflow contém `rk3566-powkiddy-x55.dts`. O build baixa essa fonte junto com o kernel; a migração não duplica uma cópia externa no repositório.

O suporte de controle segue a implementação da comunidade ROCKNIX: um único
nó `rocknix-joypad` liga os botões GPIO e os quatro eixos ADC ao driver
`rocknix-joypad` e deve ser filho direto da raiz do device tree. O driver é um
`platform_driver`; aninhar o nó em outro dispositivo (por exemplo, no DSI)
impede que ele seja registrado. `build/configure-x55-dts.py` normaliza o DTS
para garantir esse vínculo. Como o driver da comunidade usa a API
`input-polldev`, removida no Linux 6.12, o build fornece
`rocknix-input-polldev-compat.h`, um adaptador pequeno para a API de polling
atual do subsistema input.
