$ErrorActionPreference = 'Continue'
$root = Join-Path $env:ProgramData 'FVR VMS'
$logDir = Join-Path $root 'Logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$report = Join-Path $logDir ('diagnostic-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')

$lines = New-Object System.Collections.Generic.List[string]
function Add([string]$s) { $lines.Add($s); Write-Host $s }
Add 'FVR VMS 4.0.3 - Diagnóstico'
Add ('Data: ' + (Get-Date))
Add ('Computador: ' + $env:COMPUTERNAME)
Add ''
foreach ($name in @('FVR PostgreSQL 18','FVR Management Server','FVR Recording Server')) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc) { Add ("SERVICE $name = $($svc.Status)") } else { Add ("SERVICE $name = NÃO INSTALADO") }
}
Add ''
try {
    $h = Invoke-RestMethod 'http://127.0.0.1:5000/health' -TimeoutSec 5
    Add ("HEALTH = OK / version=$($h.version) / service=$($h.service)")
} catch { Add ('HEALTH = FALHA / ' + $_.Exception.Message) }
try {
    $body = @{username='admin';password='FVR@2026!'} | ConvertTo-Json
    $l = Invoke-RestMethod 'http://127.0.0.1:5000/api/auth/login' -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 5
    if ($l.accessToken) { Add 'LOGIN admin = OK' } else { Add 'LOGIN admin = FALHA SEM TOKEN' }
} catch { Add ('LOGIN admin = FALHA / ' + $_.Exception.Message) }
Add ''
try {
    $listeners = @(Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction Stop)
    foreach ($x in $listeners) { Add ("PORT 5000 = LISTENING PID=$($x.OwningProcess)") }
} catch { Add 'PORT 5000 = SEM LISTENER' }
Add ''
$installLog = Get-ChildItem $logDir -Filter 'install-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($installLog) { Add ('Último log de instalação: ' + $installLog.FullName) }
$lines | Set-Content -Path $report -Encoding UTF8
Write-Host "Relatório salvo em: $report"
