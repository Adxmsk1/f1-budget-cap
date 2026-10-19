param([Parameter(Mandatory)] [string]$PowerBiDir, [Parameter(Mandatory)] [string]$Name)
# opens the pbip, refreshes, then ctrl+s in desktop so cache.abf is written and it opens with data
# e.g. .\save_with_data.ps1 -PowerBiDir ..\..\powerbi -Name "F1 Budget Cap"
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\pbi.ps1"
if (-not ('FgWin' -as [type])) {
Add-Type @"
using System; using System.Runtime.InteropServices;
public class FgWin {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
"@
}
$PowerBiDir = (Resolve-Path $PowerBiDir).Path
$rpt = Join-Path $PowerBiDir "$Name.Report"
$cache = Join-Path $PowerBiDir "$Name.SemanticModel\.pbi\cache.abf"
$order = (Get-Content (Join-Path $rpt 'definition\pages\pages.json') -Raw | ConvertFrom-Json).pageOrder
Set-ActivePage $rpt $order[0]
Stop-Pbi $Name
$s = Start-Pbi (Join-Path $PowerBiDir "$Name.pbip")
$db = Get-DbName $s.Port
Invoke-Tmsl $s.Port "{`"refresh`":{`"type`":`"full`",`"objects`":[{`"database`":`"$db`"}]}}"
$states = Invoke-Dax $s.Port 'select [State] from $SYSTEM.TMSCHEMA_PARTITIONS' | ForEach-Object State | Sort-Object -Unique
"partition states after refresh: $($states -join ',')  (1 = loaded)"
Start-Sleep 20
$h = (Get-Process -Id $s.Pid).MainWindowHandle
# tapping alt lets us steal focus, then ctrl+s
$fgOk = $false
for ($try = 0; $try -lt 5 -and -not $fgOk; $try++) {
    [FgWin]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [FgWin]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    [FgWin]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 700
    $fgOk = ([FgWin]::GetForegroundWindow() -eq $h)
}
if (-not $fgOk) { throw 'Could not bring Power BI to the foreground - save manually with Ctrl+S' }
$before = if (Test-Path $cache) { (Get-Item $cache).LastWriteTime } else { $null }
[FgWin]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)          # Ctrl down
[FgWin]::keybd_event(0x53, 0, 0, [UIntPtr]::Zero)          # S
[FgWin]::keybd_event(0x53, 0, 2, [UIntPtr]::Zero)
[FgWin]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)          # Ctrl up
$deadline = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $deadline) {
    Start-Sleep 3
    if ((Test-Path $cache) -and ((Get-Item $cache).LastWriteTime -ne $before) -and (Get-Item $cache).Length -gt 0) { break }
}
Start-Sleep 5
Stop-Pbi $Name
if (Test-Path $cache) { "cache.abf: $((Get-Item $cache).Length) bytes, $((Get-Item $cache).LastWriteTime)" } else { Write-Warning 'cache.abf not written' }
