$ErrorActionPreference = 'Continue'
$diag = Join-Path $env:GITHUB_WORKSPACE 'install-diagnostics'
New-Item -ItemType Directory -Path $diag -Force | Out-Null

function Capture([string]$Name, [scriptblock]$Block) {
    $path = Join-Path $diag $Name
    try { & $Block 2>&1 | Out-String -Width 4096 | Set-Content $path -Encoding UTF8 }
    catch { ($_ | Out-String) | Set-Content $path -Encoding UTF8 }
}

# Copia todos os logs gerados pelo instalador/aplicação para uma única raiz de artefato.
$programDataLogs = 'C:\ProgramData\FVR VMS\Logs'
if (Test-Path $programDataLogs) {
    Copy-Item (Join-Path $programDataLogs '*') $diag -Recurse -Force -ErrorAction SilentlyContinue
}
$setupLog = Join-Path $env:RUNNER_TEMP 'FVR-VMS-4.0.3-setup-install.log'
if (Test-Path $setupLog) { Copy-Item $setupLog (Join-Path $diag 'setup-install.log') -Force }
$publishLog = Join-Path $env:GITHUB_WORKSPACE 'publish.log'
if (Test-Path $publishLog) { Copy-Item $publishLog (Join-Path $diag 'publish.log') -Force }

Capture 'services.txt' {
    Get-Service | Where-Object { $_.Name -like 'FVR*' -or $_.DisplayName -like 'FVR*' } |
        Format-Table Name, DisplayName, Status, StartType -AutoSize
}
Capture 'sc-management-queryex.txt' { sc.exe queryex 'FVR Management Server' }
Capture 'sc-management-qc.txt' { sc.exe qc 'FVR Management Server' }
Capture 'sc-management-qfailure.txt' { sc.exe qfailure 'FVR Management Server' }
Capture 'sc-recorder-queryex.txt' { sc.exe queryex 'FVR Recording Server' }
Capture 'sc-recorder-qc.txt' { sc.exe qc 'FVR Recording Server' }
Capture 'sc-postgres-queryex.txt' { sc.exe queryex 'FVR PostgreSQL 18' }
Capture 'port-5000.txt' { Get-NetTCPConnection -LocalPort 5000 -ErrorAction SilentlyContinue | Format-List * }
Capture 'processes.txt' { Get-Process | Where-Object { $_.ProcessName -like 'FVR*' -or $_.ProcessName -like 'postgres*' } | Format-Table Id, ProcessName, Path, StartTime -AutoSize }

$since = (Get-Date).AddMinutes(-30)
Capture 'application-events.txt' {
    Get-WinEvent -FilterHashtable @{ LogName='Application'; StartTime=$since } -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProviderName -in @('.NET Runtime','Application Error','Windows Error Reporting') -or
            $_.Message -match 'FVR|ManagementServer|RecordingServer'
        } |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
        Format-List
}
Capture 'system-service-events.txt' {
    Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Service Control Manager'; StartTime=$since } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'FVR|PostgreSQL' } |
        Select-Object TimeCreated, Id, LevelDisplayName, Message |
        Format-List
}

$mgmtDir = 'C:\Program Files\FVR VMS\ManagementServer'
$mgmtExe = Join-Path $mgmtDir 'FVR.ManagementServer.exe'
if (Test-Path $mgmtDir) {
    Copy-Item (Join-Path $mgmtDir 'appsettings.json') (Join-Path $diag 'installed-management-appsettings.json') -Force -ErrorAction SilentlyContinue
    Get-ChildItem $mgmtDir -File | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize |
        Out-String -Width 4096 | Set-Content (Join-Path $diag 'management-files.txt') -Encoding UTF8
}

# Se o serviço caiu, executa o MESMO binário diretamente para distinguir falha da aplicação de falha do SCM.
$svc = Get-Service -Name 'FVR Management Server' -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne 'Running' -and (Test-Path $mgmtExe)) {
    $stdout = Join-Path $diag 'management-direct-stdout.txt'
    $stderr = Join-Path $diag 'management-direct-stderr.txt'
    try {
        $existing = Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue
        if ($existing) {
            "Teste direto não iniciado: porta 5000 já possuía listener." | Set-Content (Join-Path $diag 'management-direct-result.txt')
        }
        else {
            $p = Start-Process -FilePath $mgmtExe -WorkingDirectory $mgmtDir -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
            Start-Sleep -Seconds 15
            if ($p.HasExited) {
                "EXITED=True; ExitCode=$($p.ExitCode); PID=$($p.Id)" | Set-Content (Join-Path $diag 'management-direct-result.txt')
            }
            else {
                $healthText = ''
                try {
                    $h = Invoke-RestMethod 'http://127.0.0.1:5000/health' -TimeoutSec 5
                    $healthText = $h | ConvertTo-Json -Compress
                } catch { $healthText = "HEALTH_ERROR=$($_.Exception.Message)" }
                "EXITED=False; PID=$($p.Id); $healthText" | Set-Content (Join-Path $diag 'management-direct-result.txt')
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        ($_ | Out-String) | Set-Content (Join-Path $diag 'management-direct-result.txt') -Encoding UTF8
    }
}

# Recolhe novamente o lifecycle log após o teste direto, caso o processo tenha acrescentado linhas.
$lifecycle = 'C:\ProgramData\FVR VMS\Logs\management-lifecycle.log'
if (Test-Path $lifecycle) { Copy-Item $lifecycle (Join-Path $diag 'management-lifecycle.log') -Force }

Write-Host "Diagnostics collected in $diag"
Get-ChildItem $diag | Select-Object Name, Length | Format-Table -AutoSize
if (Test-Path (Join-Path $diag 'management-lifecycle.log')) {
    Write-Host '===== MANAGEMENT LIFECYCLE ====='
    Get-Content (Join-Path $diag 'management-lifecycle.log') -Tail 100
}
if (Test-Path (Join-Path $diag 'management-direct-result.txt')) {
    Write-Host '===== MANAGEMENT DIRECT RESULT ====='
    Get-Content (Join-Path $diag 'management-direct-result.txt')
}
