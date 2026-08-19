; ============================================================
; FVR VMS 4.0.2 - Instalador Windows x64
; Correção de descoberta/conexão do Management Server.
; ============================================================

#define MyAppName "FVR VMS"
#define MyAppVersion "4.0.2"
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

[Types]
Name: "full"; Description: "Instalação completa (Management Server + Recording Server + Client)"
Name: "server"; Description: "Somente servidores (Management + Recording)"
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
Source: "{#PublishDir}\database\*"; DestDir: "{app}\database"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: mgmt
Source: "{#PublishDir}\PostgreSQL\*"; DestDir: "{app}\PostgreSQL"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: mgmt

[Dirs]
Name: "{commonappdata}\FVR VMS\PostgreSQL"; Components: mgmt
Name: "{commonappdata}\FVR VMS\Recordings"; Components: recorder

[Icons]
Name: "{group}\FVR Monitoring Client"; Filename: "{app}\MonitoringClient\FVR.MonitoringClient.exe"; Components: client
Name: "{commondesktop}\FVR Monitoring Client"; Filename: "{app}\MonitoringClient\FVR.MonitoringClient.exe"; Components: client; Tasks: desktopicon
Name: "{group}\Desinstalar FVR VMS"; Filename: "{uninstallexe}"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos:"; Components: client

[Run]
Filename: "cmd.exe"; Parameters: "/C net stop ""FVR Recording Server"" >nul 2>&1 & exit /b 0"; Flags: runhidden; Components: recorder
Filename: "cmd.exe"; Parameters: "/C net stop ""FVR Management Server"" >nul 2>&1 & exit /b 0"; Flags: runhidden; Components: mgmt

Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\database\bootstrap-postgres.ps1"" -AppRoot ""{app}"" -DataDir ""{commonappdata}\FVR VMS\PostgreSQL\data"""; Flags: runhidden waituntilterminated; Components: mgmt; StatusMsg: "Configurando banco PostgreSQL do FVR VMS..."

Filename: "cmd.exe"; Parameters: "/C sc query ""FVR Management Server"" >nul 2>&1 || sc create ""FVR Management Server"" binPath= """"{app}\ManagementServer\FVR.ManagementServer.exe"""" start= auto"; Flags: runhidden; Components: mgmt; StatusMsg: "Registrando FVR Management Server..."
Filename: "sc.exe"; Parameters: "config ""FVR Management Server"" binPath= """"{app}\ManagementServer\FVR.ManagementServer.exe"""" start= auto depend= ""FVR PostgreSQL 18"""; Flags: runhidden; Components: mgmt
Filename: "sc.exe"; Parameters: "description ""FVR Management Server"" ""Gerenciamento, autenticação e API do FVR VMS"""; Flags: runhidden; Components: mgmt
Filename: "sc.exe"; Parameters: "failure ""FVR Management Server"" reset= 86400 actions= restart/5000/restart/5000/restart/5000"; Flags: runhidden; Components: mgmt
Filename: "sc.exe"; Parameters: "failureflag ""FVR Management Server"" 1"; Flags: runhidden; Components: mgmt

Filename: "cmd.exe"; Parameters: "/C sc query ""FVR Recording Server"" >nul 2>&1 || sc create ""FVR Recording Server"" binPath= """"{app}\RecordingServer\FVR.RecordingServer.exe"""" start= auto"; Flags: runhidden; Components: recorder; StatusMsg: "Registrando FVR Recording Server..."
Filename: "sc.exe"; Parameters: "config ""FVR Recording Server"" binPath= """"{app}\RecordingServer\FVR.RecordingServer.exe"""" start= auto depend= ""FVR Management Server"""; Flags: runhidden; Components: recorder
Filename: "sc.exe"; Parameters: "description ""FVR Recording Server"" ""Grava e monitora câmeras IP do FVR VMS"""; Flags: runhidden; Components: recorder
Filename: "sc.exe"; Parameters: "failure ""FVR Recording Server"" reset= 86400 actions= restart/5000/restart/5000/restart/5000"; Flags: runhidden; Components: recorder
Filename: "sc.exe"; Parameters: "failureflag ""FVR Recording Server"" 1"; Flags: runhidden; Components: recorder

Filename: "netsh.exe"; Parameters: "advfirewall firewall delete rule name=""FVR VMS Management Server"""; Flags: runhidden; Components: mgmt
Filename: "netsh.exe"; Parameters: "advfirewall firewall add rule name=""FVR VMS Management Server"" dir=in action=allow protocol=TCP localport=5000"; Flags: runhidden; Components: mgmt

Filename: "net.exe"; Parameters: "start ""FVR Management Server"""; Flags: runhidden waituntilterminated; Components: mgmt; StatusMsg: "Iniciando FVR Management Server..."
Filename: "net.exe"; Parameters: "start ""FVR Recording Server"""; Flags: runhidden waituntilterminated; Components: recorder; StatusMsg: "Iniciando FVR Recording Server..."

Filename: "{app}\MonitoringClient\FVR.MonitoringClient.exe"; Description: "Abrir FVR Monitoring Client"; Flags: postinstall nowait skipifsilent; Components: client

[UninstallRun]
Filename: "cmd.exe"; Parameters: "/C net stop ""FVR Recording Server"" >nul 2>&1 & sc delete ""FVR Recording Server"" >nul 2>&1 & exit /b 0"; Flags: runhidden; Components: recorder
Filename: "cmd.exe"; Parameters: "/C net stop ""FVR Management Server"" >nul 2>&1 & sc delete ""FVR Management Server"" >nul 2>&1 & exit /b 0"; Flags: runhidden; Components: mgmt
Filename: "cmd.exe"; Parameters: "/C net stop ""FVR PostgreSQL 18"" >nul 2>&1 & sc delete ""FVR PostgreSQL 18"" >nul 2>&1 & exit /b 0"; Flags: runhidden; Components: mgmt
Filename: "netsh.exe"; Parameters: "advfirewall firewall delete rule name=""FVR VMS Management Server"""; Flags: runhidden; Components: mgmt

[Messages]
WelcomeLabel1=Instalação do FVR VMS 4.0.2
WelcomeLabel2=Esta versão corrige a conexão entre Monitoring Client e Management Server.%n%nO cliente agora permite informar o endereço do Management Server na tela de login e valida a comunicação antes de autenticar.
FinishedLabel=Instalação concluída.%n%nNa mesma máquina:%nManagement Server: 127.0.0.1%nUsuário: admin%nSenha: FVR@2026!%n%nEm outro computador, informe no campo Management Server o IP do servidor Windows onde o FVR Management Server está instalado. A porta padrão é 5000.
