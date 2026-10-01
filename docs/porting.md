# Porting de dispositivos

Para adicionar uma placa, crie `devices/<device>/device.conf`, `kernel.fragment`, `dts/` e `uboot/`. Registre identificadores de DTB/defconfig apenas quando houver uma fonte confirmada. Não reutilize silenciosamente o DTS de outra placa.

1. Identifique e documente as fontes públicas do DTS/DTB, U-Boot e configuração do kernel.
2. Separe em `kernel.fragment` somente opções específicas comprovadas; mantenha opções compartilhadas em `common/kernel/`.
3. Valide o build e o boot no hardware antes de alterar o estado para suportado.
4. Documente limitações conhecidas e resultados de validação em `docs/`.

Os diretórios X35S e X35H registram referências existentes, não uma declaração de suporte validado.
