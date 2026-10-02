<#
.SYNOPSIS
    Ajusta o Windows do servidor FVR VMS para ficar sempre ligado e deixar rastro
    quando cair.

.DESCRIPTION
    Sem -Aplicar o script so mostra o que faria (simulacao). Com -Aplicar ele:

      - Ativa o plano "Alto desempenho" e zera suspensao, hibernacao, desligamento de
        disco, suspensao seletiva USB e economia de energia do PCIe (link state).
      - Desativa hibernacao e Inicializacao Rapida (Fast Startup).
      - Impede que o Windows Update reinicie sozinho com usuario logado e define o
        horario ativo para 06h-23h (reinicio de update so de madrugada).
      - Desativa economia de energia das placas de rede (cameras IP caem se a NIC dormir).
      - Liga a gravacao de despejo de memoria (Automatico) para telas azuis deixarem
        minidump, mantendo o reinicio automatico apos falha.
      - Configura os servicos FVR para iniciarem automaticamente (atraso) e
        reiniciarem sozinhos se cairem.

    Nada disso resolve defeito fisico (fonte, nobreak, RAM, disco, temperatura); para
    isso siga o diagnostico de Diagnosticar-Desligamento.ps1.

.EXAMPLE
    .\Ajustar-Estabilidade.ps1            # simulacao
    .\Ajustar-Estabilidade.ps1 -Aplicar   # aplica (como Administrador)
#>
[CmdletBinding()]
param([switch]$Aplicar)

$ErrorActionPreference = 'Continue'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Aplicar -and -not $isAdmin) { throw 'Execute o PowerShell como Administrador para usar -Aplicar.' }

$log = Join-Path $env:ProgramData ("FVR\ajuste-estabilidade-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null

function Passo([string]$descricao, [scriptblock]$acao) {
    if ($Aplicar) {
        try {
            & $acao | Out-Null
            Write-Host "[OK]   $descricao" -ForegroundColor Green
            Add-Content $log "[OK]   $descricao"
        } catch {
            Write-Host "[FALHA] $descricao : $($_.Exception.Message)" -ForegroundColor Red
            Add-Content $log "[FALHA] $descricao : $($_.Exception.Message)"
        }
    } else {
        Write-Host "[SIMULACAO] $descricao" -ForegroundColor Yellow
    }
}

function Definir-Registro([string]$caminho, [string]$nome, $valor, [string]$tipo = 'DWord') {
    if (-not (Test-Path $caminho)) { New-Item -Path $caminho -Force | Out-Null }
    New-ItemProperty -Path $caminho -Name $nome -Value $valor -PropertyType $tipo -Force | Out-Null
}

if (-not $Aplicar) { Write-Host 'Modo SIMULACAO - nada sera alterado. Use -Aplicar para efetivar.' -ForegroundColor Cyan }

# --- Energia -----------------------------------------------------------------
$altoDesempenho = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
Passo 'Plano de energia: Alto desempenho' {
    $planos = powercfg /list
    if (-not ($planos -match $altoDesempenho)) { powercfg -duplicatescheme $altoDesempenho $altoDesempenho }
    powercfg /setactive $altoDesempenho
}
Passo 'Nunca suspender / hibernar / desligar disco (tomada e bateria)' {
    foreach ($m in 'standby-timeout', 'hibernate-timeout', 'disk-timeout') {
        powercfg /change "$m-ac" 0
        powercfg /change "$m-dc" 0
    }
}
Passo 'Desativar suspensao seletiva USB' {
    powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
}
Passo 'Desativar economia de energia do PCI Express (Link State Power Management)' {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0
}
Passo 'Botao de energia: apenas desligar (evita suspensao acidental)' {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 3
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 0
}
Passo 'Reaplicar plano atual' { powercfg /setactive SCHEME_CURRENT }
Passo 'Desativar hibernacao' { powercfg /hibernate off }
Passo 'Desativar Inicializacao Rapida (Fast Startup)' {
    Definir-Registro 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
}

# --- Placas de rede ----------------------------------------------------------
Passo 'Placas de rede: nao permitir que o Windows desligue para economizar energia' {
    foreach ($nic in (Get-NetAdapter -Physical -ErrorAction Stop)) {
        Disable-NetAdapterPowerManagement -Name $nic.Name -NoRestart -ErrorAction SilentlyContinue
    }
}

# --- Windows Update ----------------------------------------------------------
$au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
Passo 'Windows Update: nao reiniciar automaticamente com usuario logado' {
    Definir-Registro $au 'NoAutoRebootWithLoggedOnUsers' 1
    Definir-Registro $au 'AUOptions' 3   # baixa e avisa para instalar
}
Passo 'Windows Update: horario ativo 06h-23h' {
    Definir-Registro 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'ActiveHoursStart' 6
    Definir-Registro 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'ActiveHoursEnd' 23
    Definir-Registro 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'SetActiveHours' 1
    Definir-Registro 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ActiveHoursStart' 6
    Definir-Registro 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ActiveHoursEnd' 23
}

# --- Despejo de memoria (BSOD) -----------------------------------------------
Passo 'Gravar despejo de memoria automatico + minidump e reiniciar apos falha' {
    $cc = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
    Definir-Registro $cc 'CrashDumpEnabled' 7
    Definir-Registro $cc 'AutoReboot' 1
    Definir-Registro $cc 'MinidumpDir' '%SystemRoot%\Minidump' 'ExpandString'
    Definir-Registro $cc 'DumpFile' '%SystemRoot%\MEMORY.DMP' 'ExpandString'
}

# --- Servicos FVR ------------------------------------------------------------
foreach ($svc in 'FVR PostgreSQL 18', 'FVR Management Server', 'FVR Recording Server') {
    if (-not (Get-Service -Name $svc -ErrorAction SilentlyContinue)) {
        Write-Host "[--]   Servico '$svc' nao encontrado, ignorado." -ForegroundColor DarkGray
        continue
    }
    Passo "Servico '$svc': inicio automatico (atrasado) e reinicio automatico em caso de falha" {
        sc.exe config "$svc" start= delayed-auto
        sc.exe failure "$svc" reset= 86400 actions= restart/10000/restart/30000/restart/60000
        sc.exe failureflag "$svc" 1
    }
}

Write-Host ''
if ($Aplicar) {
    Write-Host "Ajustes aplicados. Log: $log" -ForegroundColor Green
    Write-Host 'Reinicie o servidor em horario de manutencao para efetivar tudo.' -ForegroundColor Green
} else {
    Write-Host 'Para aplicar: .\Ajustar-Estabilidade.ps1 -Aplicar (PowerShell como Administrador)' -ForegroundColor Cyan
}
Write-Host ''
Write-Host 'Verificacoes manuais que o script NAO faz:' -ForegroundColor Cyan
Write-Host '  - BIOS: "Restore on AC Power Loss" = Power On (volta sozinho apos queda de energia).'
Write-Host '  - BIOS: desativar overclock/XMP se houver erros WHEA; atualizar BIOS.'
Write-Host '  - Nobreak (UPS) com autonomia e software de desligamento configurado.'
Write-Host '  - Temperatura (HWiNFO), limpeza de poeira, ventoinhas, fonte (PSU) com folga.'
Write-Host '  - Memoria: MemTest86 / mdsched.exe.  Disco: CrystalDiskInfo, chkdsk C: /scan.'
