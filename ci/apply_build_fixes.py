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

replace_once(
    'src/FVR.Common/PlaybackTicketCodec.cs',
    's += s.Length % 4 switch { 2 => "==", 3 => "=", _ => "" };',
    's += (s.Length % 4) switch { 2 => "==", 3 => "=", _ => "" };')

rel = 'src/FVR.Management.Service/ManagementRepository.Etapa6.cs'
text = read(rel)
text = text.replace('const string sql="""INSERT INTO fvr.audit_log', 'const string sql="""\n                INSERT INTO fvr.audit_log', 1)
text = text.replace('@ip,@outcome,@app,@corr)""";', '@ip,@outcome,@app,@corr)\n                """;', 1)
text = text.replace('var sql="""SELECT a.id,u.username', 'var sql="""\n            SELECT a.id,u.username', 1)
text = text.replace('a.occurred_at<=@end""";', 'a.occurred_at<=@end\n            """;', 1)
write(rel, text)

for proj in ['src/FVR.Monitoring.Client/FVR.Monitoring.Client.csproj', 'src/FVR.Setup.Wizard/FVR.Setup.Wizard.csproj']:
    text = read(proj)
    if '<ImplicitUsings>disable</ImplicitUsings>' not in text:
        text = text.replace('<TargetFramework>net10.0-windows</TargetFramework>', '<TargetFramework>net10.0-windows</TargetFramework>\n    <ImplicitUsings>disable</ImplicitUsings>', 1)
    write(proj, text)

globals_text = 'global using System;\nglobal using System.Collections.Generic;\nglobal using System.IO;\nglobal using System.Linq;\nglobal using System.Threading;\nglobal using System.Threading.Tasks;\n'
write('src/FVR.Monitoring.Client/GlobalUsings.BuildFix.cs', globals_text)
write('src/FVR.Setup.Wizard/GlobalUsings.BuildFix.cs', globals_text)

rel = 'src/FVR.Monitoring.Client/MainWindow.Etapa9.cs'
text = read(rel)
text = text.replace('private void InitializeEtapa10()', 'private void InitializeEtapa9()', 1)
text = text.replace('private void ShutdownEtapa10()', 'private void ShutdownEtapa9()', 1)
write(rel, text)

rel = 'src/FVR.Monitoring.Client/MainWindow.xaml.cs'
text = read(rel)
text = text.replace('_playbackTimer.Start();InitializeEtapa10();', '_playbackTimer.Start();InitializeEtapa9();InitializeEtapa10();', 1)
text = text.replace('        ShutdownEtapa10();\n        _playbackTimer.Stop();', '        ShutdownEtapa10();\n        ShutdownEtapa9();\n        _playbackTimer.Stop();', 1)
write(rel, text)

rel = 'src/FVR.Management.Console/MainWindow.xaml.cs'
text = read(rel)
start_marker = '\n}\n\n\npublic sealed class AuditRow\n{\n    public string OccurredLocal{get;}public string? UserName{get;}public string Action{get;}public string Outcome{get;}public string? DetailsJson{get;}\n    public AuditRow(AuditInfo a){OccurredLocal=a.OccurredAtUtc.ToLocalTime().ToString("dd/MM/yyyy HH:mm:ss");UserName=a.UserName;Action=a.Action;Outcome=a.Outcome;DetailsJson=a.DetailsJson;}\n\nprivate async void RefreshLicense_Click'
if start_marker not in text:
    raise SystemExit('Management Console misplaced AuditRow marker not found')
text = text.replace(start_marker, '\n\nprivate async void RefreshLicense_Click', 1)
storage_marker = '\n}\n\n\npublic sealed class StorageRow\n'
audit_class = '''\n}\n\npublic sealed class AuditRow\n{\n    public string OccurredLocal { get; }\n    public string? UserName { get; }\n    public string Action { get; }\n    public string Outcome { get; }\n    public string? DetailsJson { get; }\n\n    public AuditRow(AuditInfo a)\n    {\n        OccurredLocal = a.OccurredAtUtc.ToLocalTime().ToString("dd/MM/yyyy HH:mm:ss");\n        UserName = a.UserName;\n        Action = a.Action;\n        Outcome = a.Outcome;\n        DetailsJson = a.DetailsJson;\n    }\n}\n\npublic sealed class StorageRow\n'''
if storage_marker not in text:
    raise SystemExit('Management Console StorageRow marker not found')
text = text.replace(storage_marker, audit_class, 1)
write(rel, text)

print('all build fixes applied')
