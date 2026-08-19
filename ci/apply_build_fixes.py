from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else 'fullsrc')

def read(rel):
    return (root / rel).read_text(encoding='utf-8')

def write(rel, text):
    p = root / rel
    p.write_text(text, encoding='utf-8', newline='\n')
    print(f'patched {rel}')

def replace_once(rel, old, new):
    text = read(rel)
    if old not in text:
        raise SystemExit(f'expected text not found in {rel}: {old[:120]!r}')
    write(rel, text.replace(old, new, 1))

replace_once('src/FVR.Common/PlaybackTicketCodec.cs','s += s.Length % 4 switch { 2 => "==", 3 => "=", _ => "" };','s += (s.Length % 4) switch { 2 => "==", 3 => "=", _ => "" };')

rel='src/FVR.Management.Service/ManagementRepository.Etapa6.cs'; text=read(rel)
text=text.replace('const string sql="""INSERT INTO fvr.audit_log','const string sql="""\n                INSERT INTO fvr.audit_log',1).replace('@ip,@outcome,@app,@corr)""";','@ip,@outcome,@app,@corr)\n                """;',1).replace('var sql="""SELECT a.id,u.username','var sql="""\n            SELECT a.id,u.username',1).replace('a.occurred_at<=@end""";','a.occurred_at<=@end\n            """;',1); write(rel,text)

for proj in ['src/FVR.Monitoring.Client/FVR.Monitoring.Client.csproj','src/FVR.Setup.Wizard/FVR.Setup.Wizard.csproj']:
    text=read(proj)
    if '<ImplicitUsings>disable</ImplicitUsings>' not in text:text=text.replace('<TargetFramework>net10.0-windows</TargetFramework>','<TargetFramework>net10.0-windows</TargetFramework>\n    <ImplicitUsings>disable</ImplicitUsings>',1)
    write(proj,text)
globals_text='global using System;\nglobal using System.Collections.Generic;\nglobal using System.IO;\nglobal using System.Linq;\nglobal using System.Threading;\nglobal using System.Threading.Tasks;\n'
write('src/FVR.Monitoring.Client/GlobalUsings.BuildFix.cs',globals_text); write('src/FVR.Setup.Wizard/GlobalUsings.BuildFix.cs',globals_text)

rel='src/FVR.Monitoring.Client/MainWindow.Etapa9.cs'; text=read(rel).replace('private void InitializeEtapa10()','private void InitializeEtapa9()',1).replace('private void ShutdownEtapa10()','private void ShutdownEtapa9()',1); write(rel,text)
rel='src/FVR.Monitoring.Client/MainWindow.xaml.cs'; text=read(rel).replace('_playbackTimer.Start();InitializeEtapa10();','_playbackTimer.Start();InitializeEtapa9();InitializeEtapa10();',1).replace('        ShutdownEtapa10();\n        _playbackTimer.Stop();','        ShutdownEtapa10();\n        ShutdownEtapa9();\n        _playbackTimer.Stop();',1)
marker='    private void Window_Closing(object? sender,CancelEventArgs e)\n'
timeline_methods='''    private async Task LoadTimelineEventsAsync(List<CameraInfo> cams)\n    {\n        _timelineEvents.Clear();\n        if(_client is null||string.IsNullOrWhiteSpace(_token)){RenderEventMarkers();return;}\n        var response=await _client.RequestAsync<EventsQueryResponse>(new EventsQueryRequest{Token=_token,CameraIds=cams.Select(c=>c.Id).ToList(),StartTimeUtc=_rangeStartUtc,EndTimeUtc=_rangeEndUtc,MaxItems=2000});\n        if(response.Ok)_timelineEvents.AddRange(response.Events.OrderBy(e=>e.OccurredAtUtc));\n        RenderEventMarkers();\n    }\n\n    private void RenderEventMarkers()\n    {\n        EventMarkerCanvas.Children.Clear(); var total=(_rangeEndUtc-_rangeStartUtc).TotalSeconds; var width=EventMarkerCanvas.ActualWidth; if(total<=0||width<=0)return;\n        foreach(var ev in _timelineEvents){var seconds=(ev.OccurredAtUtc-_rangeStartUtc).TotalSeconds;if(seconds<0||seconds>total)continue;var fill=ev.Severity.ToLowerInvariant() switch{\"critical\"=>Brushes.OrangeRed,\"high\"=>Brushes.OrangeRed,\"warning\"=>Brushes.Gold,_=>Brushes.DeepSkyBlue};var m=new System.Windows.Shapes.Rectangle{Width=2,Height=14,Fill=fill,Opacity=.9};Canvas.SetLeft(m,Math.Max(0,Math.Min(width-2,(seconds/total)*width)));Canvas.SetTop(m,2);EventMarkerCanvas.Children.Add(m);}\n    }\n\n'''
if 'private async Task LoadTimelineEventsAsync' not in text:
    if marker not in text:raise SystemExit('Window_Closing marker not found')
    text=text.replace(marker,timeline_methods+marker,1)
write(rel,text)

rel='src/FVR.Management.Service/ManagementWorker.cs'; text=read(rel)
repls={'await AuditAsync(s,"layout.save","view_layout",null,true,new{r.Name,r.GridSize},null);':'await _repository.WriteAuditAsync(s.UserId,"layout.save","view_layout",null,"success","Monitoring Client",null,System.Text.Json.JsonSerializer.Serialize(new{r.Name,r.GridSize}),token);','await AuditAsync(s,"videowall.save","video_wall",null,true,new{r.Name,Screens=r.Screens.Count},null);':'await _repository.WriteAuditAsync(s.UserId,"videowall.save","video_wall",null,"success","Monitoring Client",null,System.Text.Json.JsonSerializer.Serialize(new{r.Name,Screens=r.Screens.Count}),token);','await AuditAsync(s,"emap.save","e_map",id,true,new{r.Name,Pins=r.Pins.Count},null);':'await _repository.WriteAuditAsync(s.UserId,"emap.save","e_map",id,"success","Monitoring Client",null,System.Text.Json.JsonSerializer.Serialize(new{r.Name,Pins=r.Pins.Count}),token);'}
for old,new in repls.items():
    if old not in text:raise SystemExit(f'ManagementWorker audit call not found: {old}')
    text=text.replace(old,new,1)
write(rel,text)

rel='src/FVR.Management.Console/MainWindow.xaml.cs'; text=read(rel)
start_marker='\n}\n\n\npublic sealed class AuditRow\n{\n    public string OccurredLocal{get;}public string? UserName{get;}public string Action{get;}public string Outcome{get;}public string? DetailsJson{get;}\n    public AuditRow(AuditInfo a){OccurredLocal=a.OccurredAtUtc.ToLocalTime().ToString("dd/MM/yyyy HH:mm:ss");UserName=a.UserName;Action=a.Action;Outcome=a.Outcome;DetailsJson=a.DetailsJson;}\n\nprivate async void RefreshLicense_Click'
if start_marker not in text:raise SystemExit('Management Console misplaced AuditRow marker not found')
text=text.replace(start_marker,'\n\nprivate async void RefreshLicense_Click',1)
storage_marker='\n}\n\n\npublic sealed class StorageRow\n'; audit_class='''\n}\n\npublic sealed class AuditRow\n{\n    public string OccurredLocal { get; } public string? UserName { get; } public string Action { get; } public string Outcome { get; } public string? DetailsJson { get; }\n    public AuditRow(AuditInfo a){OccurredLocal=a.OccurredAtUtc.ToLocalTime().ToString("dd/MM/yyyy HH:mm:ss");UserName=a.UserName;Action=a.Action;Outcome=a.Outcome;DetailsJson=a.DetailsJson;}\n}\n\npublic sealed class StorageRow\n'''
if storage_marker not in text:raise SystemExit('Management Console StorageRow marker not found')
write(rel,text.replace(storage_marker,audit_class,1))

ffmpeg=r'''$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $PSScriptRoot
$Dest=Join-Path $Root "src\FVR.Recording.Service\tools\ffmpeg.exe"
function Test-FvrFfmpeg([string]$Path){try{$null=& $Path -version 2>&1;return ($LASTEXITCODE -eq 0)}catch{return $false}}
if((Test-Path $Dest)-and(Test-FvrFfmpeg $Dest)){Write-Host "FFmpeg pronto em: $Dest" -ForegroundColor Green;& $Dest -version|Select-Object -First 2;exit 0}
$candidates=@();$cmd=Get-Command ffmpeg.exe -ErrorAction SilentlyContinue;if($null-ne$cmd){$candidates+=$cmd.Source}
if(Test-Path 'C:\ProgramData\chocolatey\lib\ffmpeg\tools'){$candidates+=Get-ChildItem 'C:\ProgramData\chocolatey\lib\ffmpeg\tools' -Filter ffmpeg.exe -File -Recurse|ForEach-Object FullName}
foreach($candidate in($candidates|Select-Object -Unique)){if(-not(Test-FvrFfmpeg $candidate)){continue};New-Item -ItemType Directory -Force -Path(Split-Path -Parent $Dest)|Out-Null;Copy-Item $candidate $Dest -Force;if(Test-FvrFfmpeg $Dest){Write-Host "FFmpeg copiado para: $Dest" -ForegroundColor Green;& $Dest -version|Select-Object -First 2;exit 0}}
throw "FFmpeg real não foi encontrado ou não pôde ser validado."
'''; write('scripts/Prepare-FFmpeg.ps1',ffmpeg)

rel='installer/FVR.VMS.Installer.wxs'; text=read(rel)
text=text.replace('Version="4.0.10.0"','Version="4.0.10"',1)
text=text.replace('<Files Directory="MGMTDIR" Include="..\\release\\Management-Service\\**" Exclude="..\\release\\Management-Service\\FVR.Management.Service.exe" />','<Files Directory="MGMTDIR" Include="..\\release\\Management-Service\\**">\n      <Exclude Files="..\\release\\Management-Service\\FVR.Management.Service.exe" />\n    </Files>',1)
text=text.replace('<Files Directory="RECDIR" Include="..\\release\\Recording-Service\\**" Exclude="..\\release\\Recording-Service\\FVR.Recording.Service.exe" />','<Files Directory="RECDIR" Include="..\\release\\Recording-Service\\**">\n      <Exclude Files="..\\release\\Recording-Service\\FVR.Recording.Service.exe" />\n    </Files>',1)
write(rel,text)

rel='scripts/Build-Installer.ps1'; text=read(rel)
old='''$wix=Get-Command wix -ErrorAction SilentlyContinue\nif(!$wix){\n    Write-Host "Instalando WiX CLI..." -ForegroundColor Yellow\n    dotnet tool install --global wix\n    $env:PATH += ";$env:USERPROFILE\\.dotnet\\tools"\n}'''
new='''$env:PATH += ";$env:USERPROFILE\\.dotnet\\tools"\n$wix=Get-Command wix -ErrorAction SilentlyContinue\nif($wix){\n    $current=(& wix --version).Trim()\n    if($current -ne "6.0.2"){dotnet tool uninstall --global wix | Out-Null;$wix=$null}\n}\nif(!$wix){\n    Write-Host "Instalando WiX CLI 6.0.2..." -ForegroundColor Yellow\n    dotnet tool install --global wix --version 6.0.2\n    if($LASTEXITCODE -ne 0){throw "Falha ao instalar WiX 6.0.2"}\n}'''
if old not in text:raise SystemExit('Build-Installer WiX install block not found')
write(rel,text.replace(old,new,1))

print('all build fixes applied')
