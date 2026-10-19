# scripting power bi desktop: open a pbip, query its local analysis services engine, screenshot the window

$PbiExe = 'C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe'
$WsRoot = "$env:LOCALAPPDATA\Microsoft\Power BI Desktop\AnalysisServicesWorkspaces"
try { Add-Type -Path 'C:\Program Files\Microsoft Power BI Desktop\bin\Microsoft.PowerBI.AdomdClient.dll' -ErrorAction Stop } catch {}
Add-Type -AssemblyName System.Drawing
if (-not ('PbiWin' -as [type])) {
Add-Type @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class PbiWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public struct RECT { public int L, T, R, B; }
  public static List<IntPtr> ForPid(uint pid) {
    var list = new List<IntPtr>();
    EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p);
      if (p == pid && IsWindowVisible(h)) list.Add(h); return true; }, IntPtr.Zero);
    return list;
  }
  public static string Title(IntPtr h) { var s = new StringBuilder(512); GetWindowText(h, s, 512); return s.ToString(); }
}
"@
}
[PbiWin]::SetProcessDPIAware() | Out-Null

function Stop-Pbi($TitleLike) {
    Get-Process PBIDesktop -ErrorAction SilentlyContinue | Where-Object { -not $TitleLike -or $_.MainWindowTitle -like "*$TitleLike*" } | ForEach-Object {
        $kids = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($_.Id)" -ErrorAction SilentlyContinue
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        $kids | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    Start-Sleep 2
}

function Start-Pbi($Pbip, [int]$TimeoutSec = 240) {
    $before = @(Get-ChildItem $WsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object Name)
    $proc = Start-Process $PbiExe -ArgumentList "`"$Pbip`"" -PassThru
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $port = $null
    while ((Get-Date) -lt $deadline -and -not $port) {
        Start-Sleep 3
        $ws = Get-ChildItem $WsRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.Name } | Select-Object -First 1
        if ($ws) {
            $pf = Join-Path $ws.FullName 'Data\msmdsrv.port.txt'
            if (Test-Path $pf) { $port = (Get-Content $pf -Encoding Unicode).Trim() }
        }
    }
    if (-not $port) { throw "Power BI engine did not start within $TimeoutSec s" }
    # wait until the model has been deployed into the engine
    while ((Get-Date) -lt $deadline) {
        try {
            $n = @(Invoke-Dax $port 'select [ID] from $SYSTEM.TMSCHEMA_TABLES').Count
            if ($n -gt 0) { break }
        } catch {}
        Start-Sleep 3
    }
    [pscustomobject]@{ Pid = $proc.Id; Port = $port }
}

function Open-Conn($port) {
    $c = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection("Data Source=localhost:$port")
    $c.Open(); $c
}
function Invoke-Dax($port, $q) {
    $c = Open-Conn $port
    try {
        $cmd = $c.CreateCommand(); $cmd.CommandText = $q; $r = $cmd.ExecuteReader(); $rows = @()
        while ($r.Read()) { $o = [ordered]@{}; for ($i = 0; $i -lt $r.FieldCount; $i++) { $o[$r.GetName($i)] = $r.GetValue($i) }; $rows += [pscustomobject]$o }
        $r.Close(); $rows
    } finally { $c.Close() }
}
function Invoke-Tmsl($port, $json) {
    $c = Open-Conn $port
    try { $cmd = $c.CreateCommand(); $cmd.CommandText = $json; $cmd.ExecuteNonQuery() | Out-Null } finally { $c.Close() }
}
function Get-DbName($port) { $c = Open-Conn $port; try { $c.Database } finally { $c.Close() } }

function Update-Cache($port, $SemanticModelDir) {
    $db = Get-DbName $port
    Invoke-Tmsl $port "{`"refresh`":{`"type`":`"full`",`"objects`":[{`"database`":`"$db`"}]}}"
    $bad = Invoke-Dax $port 'select [TableID],[State],[ErrorMessage] from $SYSTEM.TMSCHEMA_PARTITIONS' | Where-Object { $_.State -ne 1 }
    if ($bad) { $bad | Format-Table | Out-String | Write-Warning }
    $pbiDir = Join-Path $SemanticModelDir '.pbi'
    New-Item -ItemType Directory -Force $pbiDir | Out-Null
    $tmp = "cache_$([guid]::NewGuid().ToString('N')).abf"
    Invoke-Tmsl $port "{`"backup`":{`"database`":`"$db`",`"file`":`"$tmp`",`"allowOverwrite`":true,`"applyCompression`":true}}"
    $made = Get-ChildItem $WsRoot -Recurse -Filter $tmp -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $made) { throw "Backup file $tmp not found under $WsRoot" }
    Copy-Item $made.FullName (Join-Path $pbiDir 'cache.abf') -Force
    Remove-Item $made.FullName -Force
    "cache written: $((Get-Item (Join-Path $pbiDir 'cache.abf')).Length) bytes"
}

function Save-WindowShot($h, $Out) {
    $r = New-Object PbiWin+RECT; [PbiWin]::GetWindowRect($h, [ref]$r) | Out-Null
    $w = $r.R - $r.L; $hh = $r.B - $r.T
    if ($w -le 0 -or $hh -le 0) { return $null }
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $dc = $g.GetHdc(); [PbiWin]::PrintWindow($h, $dc, 2) | Out-Null; $g.ReleaseHdc($dc); $g.Dispose()
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    $Out
}

function Save-PbiShots($ProcId, $OutPrefix) {
    $i = 0
    foreach ($h in [PbiWin]::ForPid([uint32]$ProcId)) {
        $t = [PbiWin]::Title($h)
        $f = Save-WindowShot $h "$OutPrefix-$i.png"
        if ($f) { "$f  [$t]" }
        $i++
    }
}

# crop the page out of the window grab by finding the page background colour
function Save-CanvasCrop($Shot, $Out, $BgHex = '#FAF7F0', $Rect) {
    $bg = [System.Drawing.ColorTranslator]::FromHtml($BgHex)
    $bmp = [System.Drawing.Bitmap]::FromFile($Shot)
    if ($Rect) { $crop = $bmp.Clone($Rect, $bmp.PixelFormat); $crop.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $crop.Dispose(); $bmp.Dispose(); return $Rect }
    function Match($c) { [Math]::Abs($c.R - $bg.R) -le 2 -and [Math]::Abs($c.G - $bg.G) -le 2 -and [Math]::Abs($c.B - $bg.B) -le 2 }
    $xs = @(); $ys = @()
    foreach ($fy in 0.35, 0.5, 0.65) {
        $y = [int]($bmp.Height * $fy)
        for ($x = 0; $x -lt $bmp.Width; $x += 1) { if (Match $bmp.GetPixel($x, $y)) { $xs += $x } }
    }
    foreach ($fx in 0.3, 0.5) {
        $x = [int]($bmp.Width * $fx)
        for ($y = 0; $y -lt $bmp.Height; $y += 1) { if (Match $bmp.GetPixel($x, $y)) { $ys += $y } }
    }
    if (-not $xs -or -not $ys) { $bmp.Dispose(); throw "Canvas background not found in $Shot" }
    $l = ($xs | Measure-Object -Minimum).Minimum; $r = ($xs | Measure-Object -Maximum).Maximum
    $t = ($ys | Measure-Object -Minimum).Minimum; $b = ($ys | Measure-Object -Maximum).Maximum
    # page is 16:9, so work the top out from the width (the band at the top isn't background colour)
    $wid = $r - $l + 1; $hgt = [int][Math]::Round($wid * 720 / 1280)
    $t = [Math]::Max(0, $b + 1 - $hgt)
    $rect = New-Object System.Drawing.Rectangle $l, $t, $wid, ($b - $t + 1)
    $crop = $bmp.Clone($rect, $bmp.PixelFormat)
    $crop.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    $crop.Dispose(); $bmp.Dispose()
    $rect
}

function Set-ActivePage($ReportDir, $PageName) {
    $f = Join-Path $ReportDir 'definition\pages\pages.json'
    $j = Get-Content $f -Raw | ConvertFrom-Json
    $j.activePageName = $PageName
    [IO.File]::WriteAllText($f, (ConvertTo-Json $j -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
}
