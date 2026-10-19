param(
    [Parameter(Mandatory)] [string]$PowerBiDir,   # ...\powerbi
    [Parameter(Mandatory)] [string]$Name,         # e.g. "Ibiza Tourism Economics"
    [Parameter(Mandatory)] [string]$OutDir,       # where page PNGs go
    [string[]]$Pages,                             # page folder names; default = all, in report order
    [string]$Bg = '#FAF7F0',
    [int]$RenderWait = 25
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\pbi.ps1"
$rpt = Join-Path $PowerBiDir "$Name.Report"
$pbip = Join-Path $PowerBiDir "$Name.pbip"
$order = (Get-Content (Join-Path $rpt 'definition\pages\pages.json') -Raw | ConvertFrom-Json).pageOrder
if (-not $Pages) { $Pages = $order }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$raw = Join-Path $env:TEMP 'pbi_raw_captures'; New-Item -ItemType Directory -Force $raw | Out-Null

$pending = @(); $lastRect = $null
foreach ($pg in $Pages) {
    $idx = [array]::IndexOf($order, $pg) + 1
    Write-Output "== $pg"
    Set-ActivePage $rpt $pg
    Stop-Pbi $Name
    $s = Start-Pbi $pbip
    $db = Get-DbName $s.Port
    $c = Open-Conn $s.Port
    try {
        $cmd = $c.CreateCommand(); $cmd.CommandTimeout = 180
        $cmd.CommandText = "{`"refresh`":{`"type`":`"full`",`"objects`":[{`"database`":`"$db`"}]}}"
        $cmd.ExecuteNonQuery() | Out-Null
    } finally { $c.Close() }
    Start-Sleep $RenderWait
    $shots = @(Save-PbiShots $s.Pid (Join-Path $raw "$Name-$pg"))
    $shots | Write-Output
    if ($shots.Count -gt 1) { Write-Warning "Extra window(s) open - possible dialog: $($shots[1..($shots.Count-1)] -join '; ')" }
    $main = ($shots[0] -split '  \[')[0]
    $out = Join-Path $OutDir ("{0:D2}_{1}.png" -f $idx, ($pg -replace '^p\d+_', ''))
    if ($pg -like '*cover*') { $pending += , @($main, $out); "crop deferred for $pg (full-bleed image)"; continue }
    try { $lastRect = Save-CanvasCrop $main $out $Bg; "$out $($lastRect.Width)x$($lastRect.Height)" }
    catch { $pending += ,@($main, $out); "crop deferred for $pg (no page background visible)" }
}
foreach ($pd in $pending) {
    if ($lastRect) { Save-CanvasCrop $pd[0] $pd[1] $Bg $lastRect | Out-Null; "$($pd[1]) (geometry from other pages)" }
    else { Write-Warning "No page geometry available to crop $($pd[1])" }
}
Stop-Pbi $Name
# leave the report opening on page 1
Set-ActivePage $rpt $order[0]
'done'
