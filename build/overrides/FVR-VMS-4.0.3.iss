; ============================================================
; FVR VMS 4.0.3 - Instalador Windows x64 validado pós-instalação
; ============================================================

#define MyAppName "FVR VMS"
#define MyAppVersion "4.0.3"
#define MyAppPublisher "FVR"
#define PublishDir "..\publish"

[Setup]
AppId={{B4C1F6A0-9F2E-4B7A-9C1D-F40000040000}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\FVR VMS
DefaultGroupName=FVR VMS
DisableProgramGroupPage=yes
OutputDir=..\publish\installer-output
OutputBaseFilename=FVR-VMS-{#MyAppVersion}-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
UninstallLogging=yes

[Types]
Name: "full"; Description: "Instalação completa (Management Server + Recording Server + Client)"
Name: "server"; Description: "Servidor (Management + Recording)"
Name: "client"; Description: "Somente Monitoring Client"
Name: "custom"; Description: "Customizada"; Flags: iscustom

[Components]
Name: "mgmt"; Description: "FVR Management Server + PostgreSQL dedicado"; Types: full server
Name: "recorder"; Description: "FVR Recording Server (Windows Service)"; Types: full server
Name: "client"; Description: "FVR Monitoring Client"; Types: full client

[Files]
Source: "{#PublishDir}\ManagementServer\*"; DestDir: "{app}\ManagementServer"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: mgmt
Source: "{#PublishDir}\RecordingServer\*"; DestDir: "{app}\RecordingServer"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: recorder
Source: "{#PublishDir}\MonitoringClient\*"; DestDir: "{app}\MonitoringClient"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: client
Source: "{#PublishDir}\database\*"; DestDir: "{app}\database"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: mgmt recorder
Source: "{#PublishDir}\PostgreSQL\*"; DestDir: "{app}\PostgreSQL"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: mgmt

[Dirs]
Name: "{commonappdata}\FVR VMS\PostgreSQL"; Components: mgmt
Name: "{commonappdata}\FVR VMS\Recordings"; Components: recorder
Name: "{commonappdata}\FVR VMS\Logs"

[Icons]
Name: "{group}\FVR Monitoring Client"; Filename: "{app}\MonitoringClient\FVR.MonitoringClient.exe"; Components: client
Name: "{commondesktop}\FVR Monitoring Client"; Filename: "{app}\MonitoringClient\FVR.MonitoringClient.exe"; Components: client; Tasks: desktopicon
Name: "{group}\Diagnóstico FVR VMS"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\database\diagnose-fvr-vms.ps1"""; Components: mgmt recorder
Name: "{group}\Desinstalar FVR VMS"; Filename: "{uninstallexe}"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos:"; Components: client

[Run]
Filename: "{app}\MonitoringClient\FVR.MonitoringClient.exe"; Description: "Abrir FVR Monitoring Client"; Flags: postinstall nowait skipifsilent; Components: client; Check: CanLaunchClient

[UninstallRun]
Filename: "cmd.exe"; Parameters: "/C net stop ""FVR Recording Server"" >nul 2>&1 & sc delete ""FVR Recording Server"" >nul 2>&1 & exit /b 0"; Flags: runhidden; Components: recorder
Filename: "cmd.exe"; Parameters: "/C net stop ""FVR Management Server"" >nul 2>&1 & sc delete ""FVR Management Server"" >nul 2>&1 & exit /b 0"; Flags: runhidden; Components: mgmt
Filename: "cmd.exe"; Parameters: "/C net stop ""FVR PostgreSQL 18"" >nul 2>&1 & sc delete ""FVR PostgreSQL 18"" >nul 2>&1 & exit /b 0"; Flags: runhidden; Components: mgmt
Filename: "netsh.exe"; Parameters: "advfirewall firewall delete rule name=""FVR VMS Management Server"""; Flags: runhidden; Components: mgmt

[Messages]
WelcomeLabel1=Instalação do FVR VMS 4.0.3
WelcomeLabel2=Esta versão valida a instalação real dos serviços antes de concluir.%n%nO Setup configura PostgreSQL, Management Server e Recording Server, registra o Recording Server no Management Server e executa testes de saúde e login.
FinishedLabel=Instalação concluída e validada.%n%nNa mesma máquina:%nManagement Server: 127.0.0.1%nUsuário: admin%nSenha: FVR@2026!%n%nLogs técnicos ficam em C:\ProgramData\FVR VMS\Logs.

[Code]
var
  PostInstallFailed: Boolean;
  PostInstallError: String;
  PostInstallExitCode: Integer;

function CanLaunchClient: Boolean;
begin
  Result := not PostInstallFailed;
end;

function GetCustomSetupExitCode: Integer;
begin
  if PostInstallFailed then
    Result := PostInstallExitCode
  else
    Result := 0;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Params: String;
  ResultCode: Integer;
  Ok: Boolean;
begin
  if CurStep = ssPostInstall then
  begin
    PostInstallFailed := False;
    PostInstallExitCode := 0;
    Params := '-NoProfile -ExecutionPolicy Bypass -File "' +
      ExpandConstant('{app}\database\install-fvr-vms.ps1') + '"' +
      ' -AppRoot "' + ExpandConstant('{app}') + '"' +
      ' -DataDir "' + ExpandConstant('{commonappdata}\FVR VMS\PostgreSQL\data') + '"';

    if WizardIsComponentSelected('mgmt') then
      Params := Params + ' -InstallManagement';
    if WizardIsComponentSelected('recorder') then
      Params := Params + ' -InstallRecorder';
    if WizardIsComponentSelected('client') then
      Params := Params + ' -InstallClient';

    WizardForm.StatusLabel.Caption := 'Validando serviços e comunicação do FVR VMS...';
    Ok := Exec('powershell.exe', Params, ExpandConstant('{app}'), SW_HIDE,
      ewWaitUntilTerminated, ResultCode);

    if not Ok then
    begin
      PostInstallFailed := True;
      PostInstallExitCode := 1001;
      PostInstallError := 'Não foi possível executar a configuração pós-instalação. Erro do Windows: ' + SysErrorMessage(ResultCode);
    end
    else if ResultCode <> 0 then
    begin
      PostInstallFailed := True;
      PostInstallExitCode := 1002;
      PostInstallError := 'A configuração dos serviços do FVR VMS falhou com código ' + IntToStr(ResultCode) + '.';
    end;

    if PostInstallFailed then
    begin
      WizardForm.FinishedLabel.Caption :=
        'A instalação NÃO foi concluída corretamente.' + #13#10 + #13#10 +
        PostInstallError + #13#10 + #13#10 +
        'Não abra o Monitoring Client até corrigir o problema.' + #13#10 +
        'Consulte C:\ProgramData\FVR VMS\Logs.';
      SuppressibleMsgBox(
        PostInstallError + #13#10 + #13#10 +
        'O Setup retornará um código de erro e o Monitoring Client não será iniciado.' + #13#10 +
        'Logs: C:\ProgramData\FVR VMS\Logs',
        mbError, MB_OK, IDOK);
    end;
  end;
end;
