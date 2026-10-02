<#
.SYNOPSIS
    Configura o ThinkCentre para religar sozinho depois de desligar.

.DESCRIPTION
    Um PC desligado nao executa nada, entao o religamento tem que vir da BIOS ou de
    outro aparelho na rede. Este script prepara as duas coisas:

      1. BIOS Lenovo (pela interface WMI da Lenovo, sem entrar no setup):
           - "After Power Loss" = Power On   -> liga quando a energia volta.
           - "Wake on LAN"      = Automatic  -> liga ao receber o "pacote magico".
      2. Placa de rede no Windows: aceita o pacote magico (Wake on Magic Packet),
         sem deixar o Windows desligar a placa para economizar energia.
      3. Mostra o MAC e o IP para usar no Vigiar-E-Religar.ps1 em outro PC.

    Sem -Aplicar apenas mostra o estado atual. Se a BIOS tiver senha de supervisor,
    informe-a em -SenhaBios.

.EXAMPLE
    .\Configurar-Religamento.ps1                 # mostra como esta
    .\Configurar-Religamento.ps1 -Aplicar        # aplica (como Administrador)
#>
[CmdletBinding()]
param(
    [switch]$Aplicar,
    [string]$SenhaBios = ''
)

$ErrorActionPreference = 'Continue'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Execute o PowerShell como Administrador.' }
if (-not $Aplicar) { Write-Host 'Modo CONSULTA - nada sera alterado. Use -Aplicar para efetivar.' -ForegroundColor Cyan }

# ---------------------------------------------------------------------------
# 1. BIOS Lenovo
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '== BIOS ==' -ForegroundColor Cyan
$bios = @(Get-WmiObject -Namespace root\wmi -Class Lenovo_BiosSetting -ErrorAction SilentlyContinue |
        Where-Object { $_.CurrentSetting })
$alterou = $false

function Ajustar-Bios([string]$padraoNome, [string[]]$preferidos) {
    # CurrentSetting vem como "Nome,Valor" ou "Nome,Valor;[Optional:A,B,C]"
    $item = $bios | Where-Object { ($_.CurrentSetting -split ',')[0] -match $padraoNome } | Select-Object -First 1
    if (-not $item) {
        Write-Host "[--]   Opcao '$padraoNome' nao encontrada nesta BIOS - ajuste manualmente (F1 ao ligar)." -ForegroundColor Yellow
        return
    }
    $texto = $item.CurrentSetting
    $nome = ($texto -split ',')[0]
    $atual = (($texto -split ';')[0] -split ',', 2)[1]
    $opcoes = if ($texto -match '\[Optional:([^\]]+)\]') { $Matches[1] -split ',' } else { @() }
    $alvo = $preferidos | Where-Object { -not $opcoes -or $opcoes -contains $_ } | Select-Object -First 1
    $info = if ($opcoes) { " (opcoes: $($opcoes -join ', '))" } else { '' }
    if ($atual -eq $alvo) {
        Write-Host "[OK]   $nome = $atual" -ForegroundColor Green
        return
    }
    if (-not $Aplicar) {
        Write-Host "[MUDAR] $nome = $atual  ->  $alvo$info" -ForegroundColor Yellow
        return
    }
    $arg = "$nome,$alvo"
    if ($SenhaBios) { $arg += ",$SenhaBios,ascii,us" }
    $r = (Get-WmiObject -Namespace root\wmi -Class Lenovo_SetBiosSetting).SetBiosSetting($arg).return
    if ($r -eq 'Success') {
        Write-Host "[OK]   $nome : $atual -> $alvo" -ForegroundColor Green
        $script:alterou = $true
    } else {
        Write-Host "[FALHA] $nome -> $alvo : $r$info" -ForegroundColor Red
        if ($r -match 'Access Denied') { Write-Host '        A BIOS tem senha: rode de novo com -SenhaBios "suasenha".' -ForegroundColor Red }
    }
}

if (-not $bios) {
    Write-Host 'Interface WMI da BIOS Lenovo nao disponivel. Ajuste manualmente:' -ForegroundColor Yellow
    Write-Host '  F1 ao ligar -> Power -> After Power Loss = Power On'
    Write-Host '  F1 ao ligar -> Power -> Automatic Power On -> Wake on LAN = Automatic'
} else {
    Ajustar-Bios 'After ?Power ?Loss|AC ?Power ?Recovery|PowerLoss' @('Power On', 'On', 'Enabled')
    Ajustar-Bios '^Wake ?On ?LAN$|^WakeOnLAN$'                    @('Automatic', 'Primary', 'Enabled')
    if ($alterou) {
        $save = if ($SenhaBios) { "$SenhaBios,ascii,us" } else { '' }
        $r = (Get-WmiObject -Namespace root\wmi -Class Lenovo_SaveBiosSettings).SaveBiosSettings($save).return
        if ($r -eq 'Success') { Write-Host '[OK]   Configuracao da BIOS salva (vale a partir do proximo desligamento).' -ForegroundColor Green }
        else { Write-Host "[FALHA] Salvar BIOS: $r" -ForegroundColor Red }
    }
}

# ---------------------------------------------------------------------------
# 2. Placa de rede: Wake on LAN
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '== Placa de rede ==' -ForegroundColor Cyan
$nics = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.MediaType -eq '802.3' })
foreach ($nic in $nics) {
    if ($Aplicar) {
        try {
            Set-NetAdapterPowerManagement -Name $nic.Name -WakeOnMagicPacket Enabled -NoRestart -ErrorAction Stop
            # Mantem a placa sempre ligada com o Windows rodando; so acorda o PC quando desligado.
            Set-NetAdapterPowerManagement -Name $nic.Name -AllowComputerToTurnOffDevice Disabled -NoRestart -ErrorAction SilentlyContinue
            # Propriedades do driver Intel (nomes podem vir traduzidos)
            foreach ($prop in 'Wake on Magic Packet', 'Shutdown Wake-On-Lan', 'Ativar no Magic Packet', 'Wake-On-LAN') {
                Get-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName "*$prop*" -ErrorAction SilentlyContinue | ForEach-Object {
                    $v = $_.ValidDisplayValues | Where-Object { $_ -match 'Enabled|Habilitad|Ativad' } | Select-Object -First 1
                    if ($v) { Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName $_.DisplayName -DisplayValue $v -NoRestart -ErrorAction SilentlyContinue }
                }
            }
            Write-Host "[OK]   $($nic.Name): Wake on Magic Packet ativado" -ForegroundColor Green
        } catch {
            Write-Host "[FALHA] $($nic.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    $pm = Get-NetAdapterPowerManagement -Name $nic.Name -ErrorAction SilentlyContinue
    $ip = (Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    Write-Host ("{0}: MAC={1}  IP={2}  WakeOnMagicPacket={3}" -f $nic.Name, $nic.MacAddress, $ip, $pm.WakeOnMagicPacket)
}

# ---------------------------------------------------------------------------
# 3. Proximo passo
# ---------------------------------------------------------------------------
$principal = $nics | Where-Object Status -eq 'Up' | Select-Object -First 1
if (-not $principal) { $principal = $nics | Select-Object -First 1 }
$ipPrincipal = if ($principal) { (Get-NetIPAddress -InterfaceIndex $principal.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress }
Write-Host ''
Write-Host 'Para religar automaticamente, rode em OUTRO PC sempre ligado da mesma rede:' -ForegroundColor Cyan
Write-Host ("  powershell -ExecutionPolicy Bypass -File .\Vigiar-E-Religar.ps1 -Mac {0} -Ip {1} -Instalar" -f $principal.MacAddress, $ipPrincipal) -ForegroundColor White
Write-Host ''
Write-Host 'Teste: desligue este PC pelo menu Iniciar e veja se o outro PC o religa em ~2 minutos.'
Write-Host 'ATENCAO: se a fonte (PSU) entrar em protecao, nem BIOS nem Wake on LAN conseguem ligar -' -ForegroundColor Yellow
Write-Host '         so tirar e recolocar na tomada (ou uma tomada inteligente). A solucao definitiva e trocar a fonte.' -ForegroundColor Yellow
