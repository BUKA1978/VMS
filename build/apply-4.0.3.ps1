param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
$Overrides = Join-Path (Split-Path $PSScriptRoot -Parent) 'build\overrides'
if (-not (Test-Path $Overrides)) { $Overrides = Join-Path $PSScriptRoot 'overrides' }

$copies = @{
  'FVR.ManagementServer.Program.4.0.3.cs'='FVR.ManagementServer\Program.cs'
  'FVR.ManagementServer.RecordingServersController.4.0.3.cs'='FVR.ManagementServer\Controllers\RecordingServersController.cs'
  'FVR.ManagementServer.appsettings.json'='FVR.ManagementServer\appsettings.json'
  'FVR.MonitoringClient.App.xaml.cs'='FVR.MonitoringClient\App.xaml.cs'
  'FVR.MonitoringClient.appsettings.json'='FVR.MonitoringClient\appsettings.json'
  'FVR.MonitoringClient.ApiClient.cs'='FVR.MonitoringClient\Services\ApiClient.cs'
  'FVR.MonitoringClient.LoginViewModel.cs'='FVR.MonitoringClient\ViewModels\LoginViewModel.cs'
  'FVR.MonitoringClient.LoginWindow.xaml'='FVR.MonitoringClient\Views\LoginWindow.xaml'
  'FVR.RecordingServer.appsettings.json'='FVR.RecordingServer\appsettings.json'
  'bootstrap-postgres-4.0.3.ps1'='database\bootstrap-postgres.ps1'
  'install-fvr-vms-4.0.3.ps1'='database\install-fvr-vms.ps1'
  'diagnose-fvr-vms-4.0.3.ps1'='database\diagnose-fvr-vms.ps1'
  'FVR-VMS-4.0.3.iss'='installer\FVR-VMS.iss'
}
foreach($kv in $copies.GetEnumerator()) { Copy-Item (Join-Path $Overrides $kv.Key) (Join-Path $Root $kv.Value) -Force }

$buildAllPath=Join-Path $Root 'installer\build-all.ps1'
$buildAll=Get-Content $buildAllPath -Raw
$needle='Publish-Project "FVR.ManagementServer" "ManagementServer" $true'
if($buildAll.Contains($needle)) { $buildAll=$buildAll.Replace($needle,'Publish-Project "FVR.ManagementServer" "ManagementServer" $false'); Set-Content $buildAllPath $buildAll -Encoding UTF8 }

$mgmtProject=Join-Path $Root 'FVR.ManagementServer\FVR.ManagementServer.csproj'
dotnet add $mgmtProject package Microsoft.Extensions.Hosting.WindowsServices --version 8.0.0
if($LASTEXITCODE -ne 0){throw 'Failed to add Windows Services package.'}

$client=Join-Path $Root 'FVR.MonitoringClient'
$clientProject=Join-Path $client 'FVR.MonitoringClient.csproj'
dotnet add $clientProject package Microsoft.Extensions.Configuration.Json --version 8.0.0
dotnet add $clientProject package Microsoft.Extensions.DependencyInjection --version 8.0.0
if($LASTEXITCODE -ne 0){throw 'Failed to add Monitoring Client packages.'}

function Replace-InFile([string]$path,[string]$old,[string]$new){
  $text=Get-Content $path -Raw
  if($text.Contains($old)){Set-Content $path ($text.Replace($old,$new)) -Encoding UTF8}
}
Replace-InFile (Join-Path $client 'Views\LoginWindow.xaml.cs') 'private async void PasswordBox_KeyDown(object sender, KeyEventArgs e)' 'private async void PasswordBox_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)'
Replace-InFile (Join-Path $client 'Views\WallWindow.xaml.cs') 'private void Window_KeyDown(object sender, KeyEventArgs e)' 'private void Window_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)'

$main=Join-Path $client 'Views\MainWindow.xaml.cs'
$mainText=Get-Content $main -Raw
$mainText=$mainText.Replace('private Point _dragStartPoint;','private System.Windows.Point _dragStartPoint;')
$mainText=$mainText.Replace('private void CameraListBox_MouseMove(object sender, MouseEventArgs e)','private void CameraListBox_MouseMove(object sender, System.Windows.Input.MouseEventArgs e)')
$mainText=$mainText.Replace('private void CameraTile_Drop(object sender, DragEventArgs e)','private void CameraTile_Drop(object sender, System.Windows.DragEventArgs e)')
$mainText=$mainText.Replace('DragDrop.DoDragDrop(CameraListBox, camera, DragDropEffects.Copy);','System.Windows.DragDrop.DoDragDrop(CameraListBox, camera, System.Windows.DragDropEffects.Copy);')
Set-Content $main $mainText -Encoding UTF8

foreach($relative in @('Services\ApiClient.cs','Services\PtzService.cs')){
  $path=Join-Path $client $relative; $text=Get-Content $path -Raw
  if(-not $text.Contains('using System.Net.Http;')){Set-Content $path ("using System.Net.Http;`r`n"+$text) -Encoding UTF8}
}
Write-Host 'FVR VMS 4.0.3 patches applied.'
