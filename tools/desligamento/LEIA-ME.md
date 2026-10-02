# Servidor FVR VMS desligando sozinho: diagnóstico e ajuste

## 1. Diagnosticar (rodar no servidor, PowerShell como Administrador)

```powershell
cd <pasta>\tools\desligamento
powershell -ExecutionPolicy Bypass -File .\Diagnosticar-Desligamento.ps1 -Dias 30
```

O script lê o Visualizador de Eventos (Sistema/Aplicativo) e gera, na Área de Trabalho
(`FVR-Diagnostico-Desligamento`), um relatório `.txt` e um `eventos-chave.csv`. Para cada
desligamento ele mostra os erros dos 15 minutos anteriores e, ao final, a causa mais provável.

| Evento | Significado | O que fazer |
|---|---|---|
| **41 Kernel-Power** (BugcheckCode = 0, sem botão) | Perdeu energia ou travou por completo | Nobreak/UPS, fonte (PSU), régua/cabo, temperatura |
| **41** com BugcheckCode ≠ 0 | Teve tela azul antes | Ver minidump |
| **6008** | Desligamento inesperado (acompanha o 41) | Igual ao 41 |
| **1074 User32** | Programa, usuário ou Windows Update mandou reiniciar | O relatório mostra o processo e o usuário. Se for TrustedInstaller/MoUsoCoreWorker, foi o Windows Update |
| **1001 BugCheck** | Tela azul | Abrir `C:\Windows\Minidump\*.dmp` no WinDbg (`!analyze -v`) ou BlueScreenView e atualizar o driver culpado |
| **WHEA-Logger 17/18/19/47** | Erro de hardware (CPU, RAM, PCIe, GPU, placa-mãe) | MemTest86, tirar overclock/XMP, atualizar BIOS, checar temperatura e slot PCIe |
| **Disk 7/51/153, StorAHCI 129** | HD/SSD/controladora | Cabos SATA e de energia, SMART (CrystalDiskInfo), firmware, driver da controladora |
| **NTFS 55** | Sistema de arquivos corrompido | `chkdsk C: /scan` (e `/f` em janela de manutenção) |
| **Kernel-Power 42/107** | Entrou em suspensão/hibernação | Parece desligado, mas está dormindo: corrigido pelo script de ajuste |

## 2. Ajustar

```powershell
.\Ajustar-Estabilidade.ps1            # simulação: só mostra o que vai mudar
.\Ajustar-Estabilidade.ps1 -Aplicar   # aplica (como Administrador)
```

O script de ajuste:
- ativa o plano Alto desempenho e desliga suspensão, hibernação, desligamento de disco,
  suspensão seletiva USB, economia de energia do PCIe e a Inicialização Rápida;
- impede a economia de energia nas placas de rede, para as câmeras IP não caírem;
- impede que o Windows Update reinicie sozinho com usuário logado e define o horário ativo das 06h às 23h;
- liga a gravação de despejo de memória, para que a próxima tela azul deixe um minidump;
- configura `FVR PostgreSQL 18`, `FVR Management Server` e `FVR Recording Server` para
  iniciarem automaticamente e reiniciarem sozinhos se caírem.

O log das alterações fica em `C:\ProgramData\FVR\`.

## 3. Itens físicos (não dá para corrigir por script)

- BIOS: **Restore on AC Power Loss = Power On**, para o servidor voltar sozinho depois de uma queda de energia.
- Nobreak com autonomia suficiente. Se só aparece **41** sem BSOD e sem WHEA, a causa quase sempre é energia: nobreak, fonte ou rede elétrica.
- Temperatura: limpar a poeira, conferir as ventoinhas e a pasta térmica. Use HWiNFO para monitorar.

## 4. Religar sozinho depois de desligar

Um PC desligado não executa nada, então quem religa tem que ser a BIOS ou outro aparelho da rede.

1. **No servidor** (como Administrador):
   ```powershell
   .\Configurar-Religamento.ps1            # mostra como está
   .\Configurar-Religamento.ps1 -Aplicar   # BIOS: After Power Loss = Power On e Wake on LAN = Automatic; placa de rede com Wake on Magic Packet
   ```
   Se a BIOS tiver senha, use `-SenhaBios "senha"`. O script mostra o MAC e o IP do servidor no final.
2. **Num segundo PC sempre ligado na mesma rede**:
   ```powershell
   .\Vigiar-E-Religar.ps1 -Mac <MAC> -Ip <IP> -Instalar
   ```
   Ele faz ping no servidor a cada 30 s. Depois de 2 minutos sem resposta, envia o pacote Wake on LAN e registra tudo em `C:\ProgramData\FVR\vigia-religar.log`. O `-Desinstalar` remove a tarefa.

Limitação: se a fonte entrar em proteção, nem a BIOS nem o Wake on LAN conseguem ligar o PC. Nesse caso só tirar e recolocar na tomada resolve; uma tomada inteligente pode fazer isso automaticamente. A solução definitiva é trocar a fonte.
