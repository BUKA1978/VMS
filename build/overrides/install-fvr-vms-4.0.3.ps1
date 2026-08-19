param(
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [Parameter(Mandatory = $true)][string]$DataDir,
    [switch]$InstallManagement,
    [switch]$InstallRecorder,
    [switch]$InstallClient
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ProgramDataRoot = Join-Path $env:ProgramData 'FVR VMS'
$LogDir = Join-Path $ProgramDataRoot 'Logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogFile = Join-Path $LogDir ('install-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Start-Transcript -Path $LogFile -Force | Out-Null

function Write-Step([string]$Message) { Write-Host "[FVR VMS] $Message" }

function Invoke-Sc([string[]]$Arguments) {
    & sc.exe @Arguments | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "sc.exe $($Arguments -join ' ') falhou com código $LASTEXITCODE." }
}

function Wait-ServiceState([string]$Name, [string]$State = 'Running', [int]$TimeoutSeconds = 45) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status.ToString() -eq $State) { return $svc }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    $actual = if ($svc) { $svc.Status } else { 'não encontrado' }
    throw "Serviço '$Name' não atingiu estado $State. Estado atual: $actual"
}

function Ensure-Service([string]$Name, [string]$DisplayName, [string]$ExePath, [string[]]$DependsOn, [string]$Description) {
    if (-not (Test-Path $ExePath)) { throw "Executável de serviço não encontrado: $ExePath" }
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -ne 'Stopped') {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
            try { Wait-ServiceState -Name $Name -State 'Stopped' -TimeoutSeconds 20 | Out-Null } catch { }
        }
        $binPath = '"' + $ExePath + '"'
        $args = @('config', $Name, 'binPath=', $binPath, 'start=', 'auto')
        if ($DependsOn.Count -gt 0) { $args += @('depend=', ($DependsOn -join '/')) }
        Invoke-Sc $args
    }
    else {
        New-Service -Name $Name -BinaryPathName ('"' + $ExePath + '"') -DisplayName $DisplayName -StartupType Automatic -DependsOn $DependsOn -Description $Description | Out-Null
    }
    Invoke-Sc @('failure', $Name, 'reset=', '86400', 'actions=', 'restart/5000/restart/5000/restart/5000')
    Invoke-Sc @('failureflag', $Name, '1')
}

function Wait-Management([int]$TimeoutSeconds = 60) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $health = Invoke-RestMethod -Uri 'http://127.0.0.1:5000/health' -TimeoutSec 3
            if ($health.status -eq 'ok' -and $health.service -eq 'Management Server') { return $health }
        } catch { }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    throw 'Management Server não respondeu em http://127.0.0.1:5000/health.'
}

function Login-Admin {
    $body = @{ username = 'admin'; password = 'FVR@2026!' } | ConvertTo-Json
    $login = Invoke-RestMethod -Uri 'http://127.0.0.1:5000/api/auth/login' -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 8
    if (-not $login.accessToken) { throw 'Login do administrador não retornou accessToken.' }
    return $login.accessToken
}

function Test-PortConflict([int]$Port) {
    $listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    if ($listeners.Count -eq 0) { return }
    foreach ($l in $listeners) {
        $p = Get-Process -Id $l.OwningProcess -ErrorAction SilentlyContinue
        $pname = if ($p) { $p.ProcessName } else { 'desconhecido' }
        throw "A porta TCP $Port já está em uso pelo processo PID $($l.OwningProcess) ($pname)."
    }
}

function Configure-LocalRecorder([string]$AccessToken) {
    $configPath = Join-Path $AppRoot 'RecordingServer\appsettings.json'
    if (-not (Test-Path $configPath)) { throw "Configuração do Recording Server não encontrada: $configPath" }
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
    $cfg.RecordingServer.ManagementServerUrl = 'http://127.0.0.1:5000'

    $headers = @{ Authorization = "Bearer $AccessToken" }
    $servers = @(Invoke-RestMethod -Uri 'http://127.0.0.1:5000/api/recordingservers' -Headers $headers -TimeoutSec 8)
    $existing = $servers | Where-Object { $_.hostname -eq $env:COMPUTERNAME } | Select-Object -First 1

    if ($existing) {
        Write-Step "Recording Server já cadastrado: $($existing.id). Rotacionando API Key."
        $rotated = Invoke-RestMethod -Uri ("http://127.0.0.1:5000/api/recordingservers/{0}/rotate-api-key" -f $existing.id) -Method Post -Headers $headers -TimeoutSec 8
        if (-not $rotated.apiKey) { throw 'Management Server não retornou nova API Key para o Recording Server.' }
        $serverId = [string]$existing.id
        $apiKey = [string]$rotated.apiKey
    }
    else {
        Write-Step 'Cadastrando Recording Server local no Management Server.'
        $payload = @{ name = "$env:COMPUTERNAME - Recording Server"; hostname = $env:COMPUTERNAME; port = 0 } | ConvertTo-Json
        $created = Invoke-RestMethod -Uri 'http://127.0.0.1:5000/api/recordingservers' -Method Post -Headers $headers -ContentType 'application/json' -Body $payload -TimeoutSec 8
        if (-not $created.server.id -or -not $created.apiKey) { throw 'Resposta inválida ao cadastrar Recording Server.' }
        $serverId = [string]$created.server.id
        $apiKey = [string]$created.apiKey
    }

    $cfg.RecordingServer.RecordingServerId = $serverId
    $cfg.RecordingServer.ApiKey = $apiKey
    $cfg.RecordingServer.StoragePaths[0].Path = (Join-Path $ProgramDataRoot 'Recordings')
    $cfg | ConvertTo-Json -Depth 20 | Set-Content -Path $configPath -Encoding UTF8
    return $serverId
}

function Wait-RecorderOnline([string]$ServerId, [string]$AccessToken, [int]$TimeoutSeconds = 45) {
    $headers = @{ Authorization = "Bearer $AccessToken" }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $servers = @(Invoke-RestMethod -Uri 'http://127.0.0.1:5000/api/recordingservers' -Headers $headers -TimeoutSec 5)
            $server = $servers | Where-Object { [string]$_.id -eq $ServerId } | Select-Object -First 1
            if ($server -and $server.status -eq 'online') { return $server }
        } catch { }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    throw "Recording Server $ServerId não ficou online no Management Server."
}

function Validate-Stability([string]$RecorderId) {
    Write-Step 'Executando validação final de estabilidade por 20 segundos.'
    Start-Sleep -Seconds 20

    if ($InstallManagement) {
        Wait-ServiceState -Name 'FVR PostgreSQL 18' -State 'Running' -TimeoutSeconds 5 | Out-Null
        Wait-ServiceState -Name 'FVR Management Server' -State 'Running' -TimeoutSeconds 5 | Out-Null
        $stableHealth = Wait-Management -TimeoutSeconds 10
        if ($stableHealth.status -ne 'ok') { throw 'Management Server perdeu o estado saudável durante a validação final.' }
        $stableToken = Login-Admin
        Write-Step 'Management Server permaneceu ativo, saudável e autenticando após 20 segundos.'
    }

    if ($InstallRecorder) {
        Wait-ServiceState -Name 'FVR Recording Server' -State 'Running' -TimeoutSeconds 5 | Out-Null
        $stableRecorder = Wait-RecorderOnline -ServerId $RecorderId -AccessToken $stableToken -TimeoutSeconds 10
        if ($stableRecorder.status -ne 'online') { throw 'Recording Server perdeu o estado online durante a validação final.' }
        Write-Step 'Recording Server permaneceu ativo e online após 20 segundos.'
    }
}

try {
    Write-Step "Iniciando configuração pós-instalação. AppRoot=$AppRoot"
    New-Item -ItemType Directory -Path $ProgramDataRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ProgramDataRoot 'Recordings') -Force | Out-Null
    $serverId = $null

    if ($InstallManagement) {
        Write-Step 'Preparando PostgreSQL dedicado.'
        $pgService = Get-Service -Name 'FVR PostgreSQL 18' -ErrorAction SilentlyContinue
        if ($pgService) {
            if ($pgService.Status -ne 'Stopped') {
                Stop-Service -Name 'FVR PostgreSQL 18' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
            & sc.exe delete 'FVR PostgreSQL 18' | Out-Null
            Start-Sleep -Seconds 2
        }

        $bootstrap = Join-Path $AppRoot 'database\bootstrap-postgres.ps1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrap -AppRoot $AppRoot -DataDir $DataDir
        if ($LASTEXITCODE -ne 0) { throw "Bootstrap PostgreSQL falhou com código $LASTEXITCODE." }
        Wait-ServiceState -Name 'FVR PostgreSQL 18' -State 'Running' -TimeoutSeconds 45 | Out-Null

        $mgmtSvc = Get-Service -Name 'FVR Management Server' -ErrorAction SilentlyContinue
        if ($mgmtSvc -and $mgmtSvc.Status -ne 'Stopped') {
            Stop-Service -Name 'FVR Management Server' -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        Test-PortConflict -Port 5000
        Ensure-Service -Name 'FVR Management Server' -DisplayName 'FVR Management Server' -ExePath (Join-Path $AppRoot 'ManagementServer\FVR.ManagementServer.exe') -DependsOn @('FVR PostgreSQL 18') -Description 'Gerenciamento, autenticação e API do FVR VMS'

        & netsh.exe advfirewall firewall delete rule name='FVR VMS Management Server' | Out-Null
        & netsh.exe advfirewall firewall add rule name='FVR VMS Management Server' dir=in action=allow protocol=TCP localport=5000 profile=any | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar regra de Firewall TCP 5000.' }

        Start-Service -Name 'FVR Management Server'
        Wait-ServiceState -Name 'FVR Management Server' -State 'Running' -TimeoutSeconds 45 | Out-Null
        $health = Wait-Management -TimeoutSeconds 60
        Write-Step "Management Server saudável. Versão: $($health.version)"
        $accessToken = Login-Admin
        Write-Step 'Login admin validado com sucesso.'
    }

    if ($InstallRecorder) {
        if (-not $InstallManagement) { throw 'A instalação do Recording Server 4.0.3 exige Management Server local. Use o tipo Servidor ou Completo.' }
        $serverId = Configure-LocalRecorder -AccessToken $accessToken
        Ensure-Service -Name 'FVR Recording Server' -DisplayName 'FVR Recording Server' -ExePath (Join-Path $AppRoot 'RecordingServer\FVR.RecordingServer.exe') -DependsOn @('FVR Management Server') -Description 'Grava e monitora câmeras IP do FVR VMS'
        Start-Service -Name 'FVR Recording Server'
        Wait-ServiceState -Name 'FVR Recording Server' -State 'Running' -TimeoutSeconds 45 | Out-Null
        $online = Wait-RecorderOnline -ServerId $serverId -AccessToken $accessToken -TimeoutSeconds 45
        Write-Step "Recording Server online no Management Server: $($online.id)"
    }

    if ($InstallClient -and $InstallManagement) {
        $clientConfigPath = Join-Path $AppRoot 'MonitoringClient\appsettings.json'
        if (Test-Path $clientConfigPath) {
            $clientCfg = Get-Content $clientConfigPath -Raw | ConvertFrom-Json
            $clientCfg.ManagementServerUrl = 'http://127.0.0.1:5000'
            $clientCfg | ConvertTo-Json -Depth 10 | Set-Content -Path $clientConfigPath -Encoding UTF8
        }
    }

    Validate-Stability -RecorderId $serverId
    Write-Step 'Pós-instalação concluída e estabilidade validada com sucesso.'
    Write-Host "INSTALL_LOG=$LogFile"
    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Error $_
    Write-Host "INSTALL_LOG=$LogFile"
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
