param(
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [Parameter(Mandatory = $true)][string]$DataDir
)

$ErrorActionPreference = 'Stop'
$ServiceName = 'FVR PostgreSQL 18'
$PgRoot = Join-Path $AppRoot 'PostgreSQL'
$Bin = Join-Path $PgRoot 'bin'
$InitDb = Join-Path $Bin 'initdb.exe'
$PgCtl = Join-Path $Bin 'pg_ctl.exe'
$PgIsReady = Join-Path $Bin 'pg_isready.exe'
$Psql = Join-Path $Bin 'psql.exe'
$SchemaFile = Join-Path $AppRoot 'database\001_init_schema.sql'
$Port = 55432
$SuperPassword = 'FVR-PG-Local@4.0.1!'
$AppPassword = 'FVR-DB-Local@4.0.1!'

foreach ($exe in @($InitDb, $PgCtl, $PgIsReady, $Psql)) {
    if (-not (Test-Path $exe)) { throw "PostgreSQL incompleto: $exe não encontrado." }
}
if (-not (Test-Path $SchemaFile)) { throw "Schema do FVR VMS não encontrado: $SchemaFile" }

New-Item -ItemType Directory -Force -Path (Split-Path $DataDir -Parent) | Out-Null

if (-not (Test-Path (Join-Path $DataDir 'PG_VERSION'))) {
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    $pwFile = Join-Path $env:TEMP 'fvr_pg_superuser_password.txt'
    [IO.File]::WriteAllText($pwFile, $SuperPassword, (New-Object System.Text.UTF8Encoding($false)))
    try {
        & $InitDb -D $DataDir -U postgres --pwfile=$pwFile --encoding=UTF8 --locale=C --auth-host=scram-sha-256 --auth-local=trust
        if ($LASTEXITCODE -ne 0) { throw "initdb falhou com código $LASTEXITCODE" }
    }
    finally {
        Remove-Item $pwFile -Force -ErrorAction SilentlyContinue
    }

    Add-Content -Path (Join-Path $DataDir 'postgresql.conf') -Value @"

# FVR VMS 4.0.1 - PostgreSQL dedicado
listen_addresses = '127.0.0.1'
port = $Port
password_encryption = 'scram-sha-256'
max_connections = 100
shared_buffers = '256MB'
"@
}

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    & $PgCtl register -N $ServiceName -D $DataDir -S auto
    if ($LASTEXITCODE -ne 0) { throw "Falha ao registrar o serviço $ServiceName" }
}

$service = Get-Service -Name $ServiceName -ErrorAction Stop
if ($service.Status -ne 'Running') {
    Start-Service -Name $ServiceName
}

$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    & $PgIsReady -h 127.0.0.1 -p $Port -U postgres | Out-Null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $ready) { throw 'PostgreSQL FVR não ficou disponível dentro de 60 segundos.' }

$env:PGPASSWORD = $SuperPassword
try {
    $bootstrapSql = Join-Path $env:TEMP 'fvr_vms_bootstrap.sql'
    @"
DO `$`$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'fvr_app') THEN
        CREATE ROLE fvr_app LOGIN PASSWORD '$AppPassword';
    ELSE
        ALTER ROLE fvr_app WITH LOGIN PASSWORD '$AppPassword';
    END IF;
END
`$`$;

SELECT 'CREATE DATABASE fvr_vms OWNER fvr_app'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'fvr_vms')\gexec
"@ | Set-Content -Path $bootstrapSql -Encoding UTF8

    & $Psql -h 127.0.0.1 -p $Port -U postgres -d postgres -v ON_ERROR_STOP=1 -f $bootstrapSql
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar usuário/banco fvr_vms.' }

    $schemaExists = (& $Psql -h 127.0.0.1 -p $Port -U postgres -d fvr_vms -tA -c "SELECT CASE WHEN to_regclass('fvr.users') IS NULL THEN '0' ELSE '1' END;").Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao verificar schema fvr.' }

    if ($schemaExists -ne '1') {
        & $Psql -h 127.0.0.1 -p $Port -U postgres -d fvr_vms -v ON_ERROR_STOP=1 -f $SchemaFile
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao aplicar schema do FVR VMS.' }
    }

    $grantSql = @"
GRANT CONNECT ON DATABASE fvr_vms TO fvr_app;
GRANT USAGE, CREATE ON SCHEMA fvr TO fvr_app;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA fvr TO fvr_app;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA fvr TO fvr_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA fvr GRANT ALL PRIVILEGES ON TABLES TO fvr_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA fvr GRANT ALL PRIVILEGES ON SEQUENCES TO fvr_app;
"@
    & $Psql -h 127.0.0.1 -p $Port -U postgres -d fvr_vms -v ON_ERROR_STOP=1 -c $grantSql
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao conceder permissões ao usuário fvr_app.' }
}
finally {
    Remove-Item (Join-Path $env:TEMP 'fvr_vms_bootstrap.sql') -Force -ErrorAction SilentlyContinue
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}

Write-Host 'PostgreSQL FVR inicializado com sucesso.'
