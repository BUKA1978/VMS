<#
.SYNOPSIS
    Investiga por que o servidor FVR VMS esta desligando/reiniciando.

.DESCRIPTION
    Le o log "Sistema" (e parte do "Aplicativo") do Visualizador de Eventos e procura os
    eventos que explicam um desligamento:

      41   Kernel-Power   perdeu energia, travou ou reiniciou sem desligamento normal
      6008 EventLog       desligamento inesperado
      1074 User32         programa/usuario/Windows Update mandou reiniciar ou desligar
      1001 BugCheck       tela azul (BSOD)
      17/18/19/47 WHEA-Logger  erro de hardware (CPU, RAM, PCIe, GPU, placa-mae)
      7/51/153 Disk, 129 StorAHCI  problema de HD/SSD/controladora
      55   Ntfs           erro de sistema de arquivos

    Tambem verifica: eventos de energia/termicos, Windows Update, despejos de memoria
    (minidump), plano de energia, saude dos discos e quedas dos servicos FVR.

    Gera um relatorio em texto + CSV na pasta indicada e imprime um diagnostico com a
    causa mais provavel e o que fazer.

.PARAMETER Dias
    Quantos dias para tras analisar (padrao 30).

.PARAMETER Saida
    Pasta onde gravar o relatorio (padrao: Desktop\FVR-Diagnostico-Desligamento).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Diagnosticar-Desligamento.ps1 -Dias 15
#>
[CmdletBinding()]
param(
    [int]$Dias = 30,
    [string]$Saida = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'FVR-Diagnostico-Desligamento')
)

$ErrorActionPreference = 'Continue'
$inicio = (Get-Date).AddDays(-$Dias)
New-Item -ItemType Directory -Force -Path $Saida | Out-Null
$relatorio = Join-Path $Saida ("relatorio-{0:yyyyMMdd-HHmmss}.txt" -f (Get-Date))
$achados = New-Object System.Collections.Generic.List[string]

function Escrever([string]$texto = '', [string]$cor = 'Gray') {
    Write-Host $texto -ForegroundColor $cor
    Add-Content -Path $relatorio -Value $texto -Encoding UTF8
}

function Titulo([string]$texto) {
    Escrever ''
    Escrever ('=' * 78) 'Cyan'
    Escrever $texto 'Cyan'
    Escrever ('=' * 78) 'Cyan'
}

function Buscar-Eventos([string]$log, [string[]]$provedores, [int[]]$ids) {
    # Consulta um provedor por vez: um provedor inexistente na maquina faria a consulta inteira falhar.
    $lista = if ($provedores) { $provedores } else { @($null) }
    $res = foreach ($p in $lista) {
        $filtro = @{ LogName = $log; StartTime = $inicio }
        if ($p) { $filtro.ProviderName = $p }
        if ($ids) { $filtro.Id = $ids }
        try { Get-WinEvent -FilterHashtable $filtro -ErrorAction Stop } catch { }
    }
    @($res | Sort-Object TimeCreated -Descending)
}

function Resumo-Mensagem($evento, [int]$max = 300) {
    $m = ($evento.Message -replace '\s+', ' ').Trim()
    if (-not $m) { $m = '(sem mensagem) ' + (($evento.Properties | ForEach-Object { $_.Value }) -join ' | ') }
    if ($m.Length -gt $max) { $m = $m.Substring(0, $max) + '...' }
    $m
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Titulo "Diagnostico de desligamento - $env:COMPUTERNAME - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
if (-not $isAdmin) { Escrever 'AVISO: execute como Administrador para ler todos os logs e discos.' 'Yellow' }
$os = Get-CimInstance Win32_OperatingSystem
Escrever ("Windows: {0} build {1}" -f $os.Caption, $os.BuildNumber)
Escrever ("Ultima inicializacao: {0}" -f $os.LastBootUpTime)
Escrever ("Periodo analisado: {0:dd/MM/yyyy HH:mm} ate agora ({1} dias)" -f $inicio, $Dias)

# ---------------------------------------------------------------------------
# 1. Eventos-chave
# ---------------------------------------------------------------------------
$grupos = [ordered]@{
    'Kernel-Power 41 (perda de energia / travamento)' = @{ P = @('Microsoft-Windows-Kernel-Power'); I = @(41) }
    'EventLog 6008 (desligamento inesperado)'          = @{ P = @('EventLog'); I = @(6008) }
    'User32 1074 (desligamento solicitado)'            = @{ P = @('User32'); I = @(1074) }
    'BugCheck 1001 (tela azul)'                        = @{ P = @('Microsoft-Windows-WER-SystemErrorReporting', 'BugCheck'); I = @(1001) }
    'WHEA-Logger 17/18/19/47 (hardware)'               = @{ P = @('Microsoft-Windows-WHEA-Logger'); I = @(17, 18, 19, 47) }
    'Disco 7/51/153'                                   = @{ P = @('disk', 'Disk'); I = @(7, 51, 153) }
    'StorAHCI/stornvme 129 (reset da controladora)'    = @{ P = @('storahci', 'stornvme', 'iaStorA', 'iaStorAC', 'iaStorAVC'); I = @(129) }
    'NTFS 55 (sistema de arquivos)'                    = @{ P = @('Ntfs', 'Microsoft-Windows-Ntfs'); I = @(55) }
    'Termico / energia (Kernel-Power 125/137, ACPI)'   = @{ P = @('Microsoft-Windows-Kernel-Power', 'ACPI'); I = @(86, 125, 137) }
    'Inicializacao/parada do log (6005/6006)'          = @{ P = @('EventLog'); I = @(6005, 6006) }
}

$todos = New-Object System.Collections.Generic.List[object]
$contagem = @{}
Titulo '1. Eventos-chave no log Sistema'
foreach ($nome in $grupos.Keys) {
    $g = $grupos[$nome]
    $ev = Buscar-Eventos 'System' $g.P $g.I
    $contagem[$nome] = $ev.Count
    $cor = if ($ev.Count -gt 0 -and $nome -notlike '*6005*') { 'Yellow' } else { 'Green' }
    Escrever ("{0,-52} {1,5} ocorrencia(s)" -f $nome, $ev.Count) $cor
    foreach ($e in $ev) {
        $todos.Add([pscustomobject]@{
            Data = $e.TimeCreated; Grupo = $nome; Id = $e.Id; Origem = $e.ProviderName
            Nivel = $e.LevelDisplayName; Mensagem = (Resumo-Mensagem $e 1000)
        })
    }
}
$todos | Sort-Object Data | Export-Csv -Path (Join-Path $Saida 'eventos-chave.csv') -NoTypeInformation -Encoding UTF8

# ---------------------------------------------------------------------------
# 2. Linha do tempo de cada desligamento
# ---------------------------------------------------------------------------
Titulo '2. Linha do tempo (cada desligamento e os 15 min anteriores)'
$quedas = $todos | Where-Object { $_.Id -in 41, 6008, 1074 } | Sort-Object Data -Descending
if (-not $quedas) {
    Escrever 'Nenhum desligamento registrado no periodo (41/6008/1074).' 'Green'
}
foreach ($q in ($quedas | Select-Object -First 15)) {
    Escrever ''
    Escrever ("--- {0:dd/MM/yyyy HH:mm:ss}  [{1}] {2}" -f $q.Data, $q.Id, $q.Origem) 'Yellow'
    Escrever ("    {0}" -f ($q.Mensagem.Substring(0, [Math]::Min(400, $q.Mensagem.Length))))
    if ($q.Id -eq 41) {
        $k = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $q.Data.AddSeconds(-1); EndTime = $q.Data.AddSeconds(1) } -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($k) {
            $xml = [xml]$k.ToXml()
            $d = @{}; foreach ($n in $xml.Event.EventData.Data) { $d[$n.Name] = $n.'#text' }
            $bc = [Convert]::ToInt64(('0' + $d['BugcheckCode']), 10)
            Escrever ("    BugcheckCode={0} (0x{0:X})  PowerButtonTimestamp={1}" -f $bc, $d['PowerButtonTimestamp'])
            if ($bc -ne 0) {
                Escrever '    => Houve TELA AZUL antes do reinicio (veja secao 4 / minidump).' 'Red'
            } elseif ($d['PowerButtonTimestamp'] -and $d['PowerButtonTimestamp'] -ne '0') {
                Escrever '    => Botao de energia foi pressionado (desligamento manual forcado).' 'Red'
            } else {
                Escrever '    => Sem tela azul e sem botao: tipico de QUEDA DE ENERGIA, fonte (PSU), superaquecimento ou travamento total.' 'Red'
            }
        }
    }
    $antes = Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $q.Data.AddMinutes(-15); EndTime = $q.Data; Level = 1, 2, 3 } -ErrorAction SilentlyContinue |
        Select-Object -First 12
    foreach ($a in $antes) {
        Escrever ("      {0:HH:mm:ss} {1,-8} {2,-35} {3,5}  {4}" -f $a.TimeCreated, $a.LevelDisplayName, $a.ProviderName, $a.Id, (Resumo-Mensagem $a 140))
    }
}

# ---------------------------------------------------------------------------
# 3. Quem mandou desligar (1074)
# ---------------------------------------------------------------------------
Titulo '3. Desligamentos solicitados (User32 1074)'
$u = Buscar-Eventos 'System' @('User32') @(1074)
if (-not $u) { Escrever 'Nenhum.' 'Green' }
foreach ($e in ($u | Select-Object -First 20)) {
    $p = $e.Properties | ForEach-Object { $_.Value }
    # 0=processo 1=computador 2=motivo 3=codigo 4=tipo 5=comentario 6=usuario
    Escrever ("{0:dd/MM/yyyy HH:mm:ss}  tipo={1}  usuario={2}" -f $e.TimeCreated, $p[4], $p[6]) 'Yellow'
    Escrever ("    processo: {0}" -f $p[0])
    Escrever ("    motivo  : {0} {1}" -f $p[2], $p[5])
    if ($p[0] -match 'TrustedInstaller|wuauclt|MoUsoCoreWorker|usoclient|svchost') { $achados.Add('WINDOWS UPDATE reiniciou a maquina (evento 1074 por ' + (Split-Path $p[0] -Leaf) + ').') }
    elseif ($p[0] -match 'winlogon|explorer|shutdown\.exe') { $achados.Add("Desligamento/reinicio manual ou por script (1074, usuario $($p[6])).") }
    else { $achados.Add("Programa solicitou desligamento: $($p[0]).") }
}

# ---------------------------------------------------------------------------
# 4. Tela azul / minidumps
# ---------------------------------------------------------------------------
Titulo '4. Tela azul (BugCheck 1001) e arquivos de despejo'
foreach ($e in (Buscar-Eventos 'System' @('Microsoft-Windows-WER-SystemErrorReporting', 'BugCheck') @(1001) | Select-Object -First 10)) {
    Escrever ("{0:dd/MM/yyyy HH:mm:ss}  {1}" -f $e.TimeCreated, (Resumo-Mensagem $e 300)) 'Red'
}
$dumps = @()
$dumps += Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -ErrorAction SilentlyContinue
$dumps += Get-Item "$env:SystemRoot\MEMORY.DMP" -ErrorAction SilentlyContinue
if ($dumps) {
    $dumps | Sort-Object LastWriteTime -Descending | ForEach-Object { Escrever ("  {0:dd/MM/yyyy HH:mm}  {1,10:N0} KB  {2}" -f $_.LastWriteTime, ($_.Length / 1KB), $_.FullName) }
    Escrever '  Analise com WinDbg (!analyze -v) ou BlueScreenView para ver o driver culpado.' 'Yellow'
} else { Escrever 'Nenhum arquivo .dmp encontrado.' }
$cc = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -ErrorAction SilentlyContinue
if ($cc) {
    $tipos = @{ 0 = 'Nenhum'; 1 = 'Completo'; 2 = 'Kernel'; 3 = 'Minidump'; 7 = 'Automatico' }
    Escrever ("Config. de despejo: {0}  AutoReboot={1}" -f $tipos[[int]$cc.CrashDumpEnabled], $cc.AutoReboot)
    if ([int]$cc.CrashDumpEnabled -eq 0) { $achados.Add('Gravacao de despejo de memoria DESATIVADA - telas azuis nao deixam rastro. Rode Ajustar-Estabilidade.ps1.') }
}

# ---------------------------------------------------------------------------
# 5. Hardware: WHEA, disco, NTFS
# ---------------------------------------------------------------------------
Titulo '5. Hardware (WHEA / disco / controladora / NTFS)'
$hw = $todos | Where-Object { $_.Grupo -match 'WHEA|Disco|StorAHCI|NTFS' } | Sort-Object Data -Descending
if (-not $hw) { Escrever 'Nenhum erro de hardware/disco registrado.' 'Green' }
foreach ($h in ($hw | Select-Object -First 25)) {
    Escrever ("{0:dd/MM/yyyy HH:mm:ss}  {1,-12} {2,4}  {3}" -f $h.Data, $h.Origem, $h.Id, $h.Mensagem.Substring(0, [Math]::Min(200, $h.Mensagem.Length))) 'Red'
}
if ($hw | Where-Object Grupo -like 'WHEA*') { $achados.Add('Erros WHEA: suspeitar de RAM, CPU (overclock/temperatura), placa-mae, slot PCIe ou fonte. Rodar MemTest86 e verificar temperatura.') }
if ($hw | Where-Object Grupo -match 'Disco|StorAHCI') { $achados.Add('Erros de disco/controladora: verificar cabos SATA/energia, SMART, firmware do SSD/HD e driver da controladora.') }
if ($hw | Where-Object Grupo -like 'NTFS*') { $achados.Add('Erro NTFS: executar "chkdsk C: /scan" (e /f em janela de manutencao).') }

try {
    Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
        $r = $_ | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        $cor = if ($_.HealthStatus -ne 'Healthy') { 'Red' } else { 'Gray' }
        Escrever ("Disco {0,-30} {1,-8} Saude={2,-9} Temp={3}C Erros leitura={4} escrita={5} Desgaste={6}%" -f $_.FriendlyName, $_.MediaType, $_.HealthStatus, $r.Temperature, $r.ReadErrorsTotal, $r.WriteErrorsTotal, $r.Wear) $cor
        if ($_.HealthStatus -ne 'Healthy') { $achados.Add("Disco $($_.FriendlyName) com saude $($_.HealthStatus) - substituir.") }
    }
} catch { Escrever 'Nao foi possivel ler a saude dos discos.' }

# ---------------------------------------------------------------------------
# 6. Temperatura e energia
# ---------------------------------------------------------------------------
Titulo '6. Temperatura e configuracao de energia'
try {
    Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | ForEach-Object {
        $c = [math]::Round($_.CurrentTemperature / 10 - 273.15, 1)
        $cor = if ($c -ge 85) { 'Red' } elseif ($c -ge 70) { 'Yellow' } else { 'Gray' }
        Escrever ("Zona termica {0}: {1} C" -f $_.InstanceName, $c) $cor
        if ($c -ge 85) { $achados.Add("Temperatura alta ($c C): limpar poeira, conferir ventoinhas/pasta termica.") }
    }
} catch { Escrever 'Sensor ACPI de temperatura indisponivel (use HWiNFO para medir CPU/GPU/discos).' }
$termico = $todos | Where-Object Grupo -like 'Termico*'
if ($termico) { $achados.Add('Eventos termicos/energia do Kernel-Power/ACPI encontrados - suspeitar de superaquecimento.') }

Escrever ''
Escrever ('Plano ativo: ' + ((powercfg /getactivescheme) -join ' '))
foreach ($s in @(
        @{ G = 'SUB_SLEEP'; S = 'STANDBYIDLE'; N = 'Suspender apos (s)' },
        @{ G = 'SUB_SLEEP'; S = 'HIBERNATEIDLE'; N = 'Hibernar apos (s)' },
        @{ G = 'SUB_DISK'; S = 'DISKIDLE'; N = 'Desligar disco apos (s)' })) {
    $q = powercfg /query SCHEME_CURRENT $s.G $s.S 2>$null
    $linha = $q | Select-String 'Current AC Power Setting Index|CA Atual' | Select-Object -First 1
    $ac = if ($linha) { $linha.Line -replace '.*:\s*', '' }
    if ($ac) {
        $v = [Convert]::ToInt32($ac.Trim(), 16)
        $cor = if ($v -gt 0) { 'Yellow' } else { 'Green' }
        Escrever ("{0,-28} {1}" -f $s.N, $v) $cor
        if ($v -gt 0 -and $s.S -ne 'DISKIDLE') { $achados.Add("Plano de energia coloca a maquina para $($s.N.ToLower()) $v s - servidor de gravacao deve ficar sempre ligado.") }
    }
}
$hb = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue
if ($hb.HiberbootEnabled -eq 1) { Escrever 'Inicializacao rapida (Fast Startup): ATIVADA' 'Yellow' }
$sleep = Buscar-Eventos 'System' @('Microsoft-Windows-Kernel-Power') @(42, 107, 187)
if ($sleep) {
    Escrever ("Entradas em suspensao/hibernacao no periodo: {0}" -f $sleep.Count) 'Yellow'
    $achados.Add("A maquina entrou em suspensao/hibernacao $($sleep.Count) vez(es) - parece 'desligada' mas esta dormindo.")
}

# ---------------------------------------------------------------------------
# 7. Windows Update
# ---------------------------------------------------------------------------
Titulo '7. Windows Update (reinicios automaticos)'
$wu = Buscar-Eventos 'System' @('Microsoft-Windows-WindowsUpdateClient') @(19, 20, 43) | Select-Object -First 10
foreach ($e in $wu) { Escrever ("{0:dd/MM/yyyy HH:mm}  {1}" -f $e.TimeCreated, (Resumo-Mensagem $e 160)) }
$au = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
$ux = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -ErrorAction SilentlyContinue
Escrever ("NoAutoRebootWithLoggedOnUsers={0}  Horario ativo={1}h-{2}h" -f $au.NoAutoRebootWithLoggedOnUsers, $ux.ActiveHoursStart, $ux.ActiveHoursEnd)

# ---------------------------------------------------------------------------
# 8. Servicos FVR e aplicacao
# ---------------------------------------------------------------------------
Titulo '8. Servicos FVR VMS'
Get-Service -Name 'FVR*' -ErrorAction SilentlyContinue | ForEach-Object {
    $cor = if ($_.Status -ne 'Running') { 'Red' } else { 'Green' }
    Escrever ("{0,-30} {1,-10} {2}" -f $_.Name, $_.Status, $_.StartType) $cor
}
$scm = Buscar-Eventos 'System' @('Service Control Manager') @(7031, 7034, 7023, 7024) | Where-Object { $_.Message -match 'FVR' }
foreach ($e in ($scm | Select-Object -First 15)) { Escrever ("{0:dd/MM/yyyy HH:mm:ss}  {1}" -f $e.TimeCreated, (Resumo-Mensagem $e 200)) 'Yellow' }
if ($scm) { $achados.Add("Servicos FVR terminaram inesperadamente $($scm.Count) vez(es) (isso NAO desliga o Windows, mas para a gravacao).") }
$app = Buscar-Eventos 'Application' @('Application Error', '.NET Runtime') @(1000, 1026) | Where-Object { $_.Message -match 'FVR' } | Select-Object -First 10
foreach ($e in $app) { Escrever ("{0:dd/MM/yyyy HH:mm:ss}  {1}" -f $e.TimeCreated, (Resumo-Mensagem $e 200)) 'Yellow' }

# ---------------------------------------------------------------------------
# Conclusao
# ---------------------------------------------------------------------------
Titulo 'DIAGNOSTICO'
$n41 = ($todos | Where-Object Id -eq 41).Count
$nBsod = ($todos | Where-Object Grupo -like 'BugCheck*').Count
if ($n41 -gt 0 -and $nBsod -eq 0 -and -not ($todos | Where-Object Grupo -like 'WHEA*')) {
    $achados.Insert(0, "Kernel-Power 41 ($n41x) sem tela azul nem WHEA: causa mais provavel e ENERGIA - queda de rede, nobreak/UPS, fonte (PSU) fraca/defeituosa, cabo/regua. Verificar nobreak e trocar fonte se repetir.")
} elseif ($nBsod -gt 0) {
    $achados.Insert(0, "Telas azuis ($nBsod x): analisar o minidump para achar o driver (rede, video, controladora, antivirus) e atualiza-lo.")
}
if ($achados.Count -eq 0) { $achados.Add('Nenhuma causa evidente no periodo. Aumente -Dias ou rode logo apos o proximo desligamento.') }
$i = 1
foreach ($a in ($achados | Select-Object -Unique)) { Escrever ("{0}. {1}" -f $i++, $a) 'Magenta' }
Escrever ''
Escrever "Relatorio: $relatorio" 'Green'
Escrever ("CSV      : {0}" -f (Join-Path $Saida 'eventos-chave.csv')) 'Green'
Escrever 'Proximo passo: .\Ajustar-Estabilidade.ps1 (simulacao) e depois .\Ajustar-Estabilidade.ps1 -Aplicar' 'Green'
