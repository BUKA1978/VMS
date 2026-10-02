<#
.SYNOPSIS
    Roda em OUTRO PC sempre ligado: vigia o servidor e o religa por Wake on LAN.

.DESCRIPTION
    A cada -Intervalo segundos faz ping no servidor. Se ele nao responder em
    -FalhasParaReligar verificacoes seguidas, envia o "pacote magico" (Wake on LAN)
    para o MAC informado e anota em C:\ProgramData\FVR\vigia-religar.log.

    O servidor precisa ter rodado Configurar-Religamento.ps1 -Aplicar e os dois PCs
    precisam estar na mesma rede local.

    -Instalar cria uma tarefa agendada que inicia este vigia junto com o Windows.
    -Desinstalar remove a tarefa.

.EXAMPLE
    .\Vigiar-E-Religar.ps1 -Mac 00-11-22-33-44-55 -Ip 192.168.0.50             # roda na janela
    .\Vigiar-E-Religar.ps1 -Mac 00-11-22-33-44-55 -Ip 192.168.0.50 -Instalar   # roda sempre
#>
[CmdletBinding()]
param(
    [string]$Mac,
    [string]$Ip,
    [int]$Intervalo = 30,
    [int]$FalhasParaReligar = 4,
    [switch]$Instalar,
    [switch]$Desinstalar
)

$tarefa = 'FVR - Vigiar e religar servidor'

if ($Desinstalar) {
    Unregister-ScheduledTask -TaskName $tarefa -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Tarefa '$tarefa' removida." -ForegroundColor Green
    return
}
if (-not $Mac -or -not $Ip) { throw 'Informe -Mac e -Ip do servidor (mostrados pelo Configurar-Religamento.ps1).' }

$bytesMac = $Mac -split '[:-]' | ForEach-Object { [Convert]::ToByte($_, 16) }
if ($bytesMac.Count -ne 6) { throw "MAC invalido: $Mac" }

if ($Instalar) {
    $destino = Join-Path $env:ProgramData 'FVR\Vigiar-E-Religar.ps1'
    New-Item -ItemType Directory -Force -Path (Split-Path $destino) | Out-Null
    if ($PSCommandPath -ne $destino) { Copy-Item -Path $PSCommandPath -Destination $destino -Force }
    $acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$destino`" -Mac $Mac -Ip $Ip -Intervalo $Intervalo -FalhasParaReligar $FalhasParaReligar"
    $gatilho = New-ScheduledTaskTrigger -AtStartup
    $config = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $tarefa -Action $acao -Trigger $gatilho -Settings $config -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
    Start-ScheduledTask -TaskName $tarefa
    Write-Host "Tarefa '$tarefa' instalada e iniciada. Log: $env:ProgramData\FVR\vigia-religar.log" -ForegroundColor Green
    return
}

$log = Join-Path $env:ProgramData 'FVR\vigia-religar.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
function Log([string]$m) {
    $linha = '{0:dd/MM/yyyy HH:mm:ss}  {1}' -f (Get-Date), $m
    Write-Host $linha
    Add-Content -Path $log -Value $linha
}

function Enviar-PacoteMagico {
    $pacote = [byte[]](@(0xFF) * 6 + ($bytesMac * 16))
    $udp = New-Object System.Net.Sockets.UdpClient
    try {
        $udp.EnableBroadcast = $true
        foreach ($porta in 7, 9) {
            [void]$udp.Send($pacote, $pacote.Length, [Net.IPEndPoint]::new([Net.IPAddress]::Broadcast, $porta))
            # Broadcast da sub-rede (ex.: 192.168.0.255), caso o roteador bloqueie 255.255.255.255
            $partes = $Ip -split '\.'
            if ($partes.Count -eq 4) {
                $bc = [Net.IPAddress]::Parse(($partes[0..2] -join '.') + '.255')
                [void]$udp.Send($pacote, $pacote.Length, [Net.IPEndPoint]::new($bc, $porta))
            }
        }
    } finally { $udp.Close() }
}

Log "Vigia iniciado: servidor $Ip ($Mac), ping a cada $Intervalo s, religa apos $FalhasParaReligar falhas."
$falhas = 0
$tentativas = 0
while ($true) {
    if (Test-Connection -ComputerName $Ip -Count 2 -Quiet -ErrorAction SilentlyContinue) {
        if ($falhas -ge $FalhasParaReligar) { Log 'Servidor voltou a responder.' }
        $falhas = 0
        $tentativas = 0
    } else {
        $falhas++
        if ($falhas -ge $FalhasParaReligar) {
            $tentativas++
            Log "Servidor sem resposta ha $($falhas * $Intervalo) s - enviando Wake on LAN (tentativa $tentativas)."
            Enviar-PacoteMagico
            if ($tentativas -eq 10) { Log 'ATENCAO: 10 tentativas sem resposta. A fonte pode estar em protecao - desligue e religue o PC na tomada.' }
        }
    }
    Start-Sleep -Seconds $Intervalo
}
