# draws the cover picture into powerbi\assets\cover.png (re-run build_dashboard.ps1 after)
# F1: team colour stripes on carbon. Ibiza: sunset with Es Vedra
Add-Type -AssemblyName System.Drawing
$W = 1920; $H = 1080
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$isF1 = (Split-Path $projectRoot -Leaf) -like 'f1*'
$out = Join-Path $projectRoot 'powerbi\assets'; New-Item -ItemType Directory -Force $out | Out-Null
function Hex($h, $a = 255) { $c = [System.Drawing.ColorTranslator]::FromHtml($h); [System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B) }
function New-Canvas { $b = New-Object System.Drawing.Bitmap $W, $H; $g = [System.Drawing.Graphics]::FromImage($b); $g.SmoothingMode = 'AntiAlias'; $g.CompositingQuality = 'HighQuality'; @($b, $g) }
function Pt($x, $y) { New-Object System.Drawing.PointF ([single]$x), ([single]$y) }

# F1
if ($isF1) {
$b, $g = New-Canvas
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush (Pt 0 0), (Pt $W $H), (Hex '#1B1B26'), (Hex '#0B0B10')
$g.FillRectangle($bg, 0, 0, $W, $H)
# carbon-fibre weave texture
$weave = New-Object System.Drawing.Drawing2D.HatchBrush ([System.Drawing.Drawing2D.HatchStyle]::SmallCheckerBoard), (Hex '#FFFFFF' 9), ([System.Drawing.Color]::Transparent)
$g.FillRectangle($weave, 0, 0, $W, $H)
# sweeping livery stripes, one per current team
$teams = '#E8002D', '#FF8000', '#27F4D2', '#3671C6', '#229971', '#0093CC', '#005AFF', '#6692FF', '#2BB24C', '#B6BABD'
$sw = 34; $x0 = 820
for ($i = 0; $i -lt $teams.Count; $i++) {
    $off = $i * ($sw + 6)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddBezier((Pt ($x0 + $off) ($H + 40)), (Pt ($x0 + 260 + $off) 640), (Pt ($x0 + 520 + $off) 300), (Pt ($W + 60) (60 + $off * 0.6)))
    $pen = New-Object System.Drawing.Pen (Hex $teams[$i] 235), $sw
    $pen.StartCap = 'Flat'; $pen.EndCap = 'Flat'
    $g.DrawPath($pen, $path)
}
$rnd = New-Object System.Random 7
for ($i = 0; $i -lt 60; $i++) {
    $y = $rnd.Next(40, $H - 40); $x = $rnd.Next(700, $W); $len = $rnd.Next(80, 360)
    $g.DrawLine((New-Object System.Drawing.Pen (Hex '#FFFFFF' ($rnd.Next(12, 45))), 2), $x, $y, ($x + $len), ($y - $len * 0.18))
}
# chequered flag fading into the top-right corner
$sq = 44
for ($r = 0; $r -lt 9; $r++) { for ($c = 0; $c -lt 12; $c++) {
    if (($r + $c) % 2 -eq 0) { continue }
    $x = $W - ($c + 1) * $sq; $y = $r * $sq
    $alpha = [int](150 * (1 - $c / 12) * (1 - $r / 9))
    if ($alpha -gt 4) { $g.FillRectangle((New-Object System.Drawing.SolidBrush (Hex '#FFFFFF' $alpha)), $x, $y, $sq, $sq) }
} }
# F1-red accent bar along the bottom
$g.FillRectangle((New-Object System.Drawing.SolidBrush (Hex '#E10600')), 0, ($H - 14), $W, 14)
$b.Save("$out\cover.png", [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $b.Dispose()
}

# Ibiza
if (-not $isF1) {
$b, $g = New-Canvas
$hz = [int]($H * 0.64)   # horizon
$sky = New-Object System.Drawing.Drawing2D.LinearGradientBrush (Pt 0 0), (Pt 0 $hz), (Hex '#1B3A5C'), (Hex '#F29E4C')
$blend = New-Object System.Drawing.Drawing2D.ColorBlend 4
$blend.Colors = @((Hex '#14304D'), (Hex '#6A4C7A'), (Hex '#E8623F'), (Hex '#F7B267'))
$blend.Positions = @(0.0, 0.42, 0.78, 1.0)
$sky.InterpolationColors = $blend
$g.FillRectangle($sky, 0, 0, $W, $hz)
# sun, half set, with glow
$sx = 1340; $sr = 120
for ($k = 6; $k -ge 1; $k--) { $rr = $sr + $k * 38; $g.FillEllipse((New-Object System.Drawing.SolidBrush (Hex '#FFD27A' (14))), $sx - $rr, $hz - $rr, 2 * $rr, 2 * $rr) }
$g.FillEllipse((New-Object System.Drawing.SolidBrush (Hex '#FFE3A3')), $sx - $sr, $hz - $sr, 2 * $sr, 2 * $sr)
# Es Vedra-style rock on the horizon
$rock = @((Pt 1460 $hz), (Pt 1520 ($hz - 90)), (Pt 1575 ($hz - 210)), (Pt 1610 ($hz - 300)), (Pt 1640 ($hz - 270)), (Pt 1690 ($hz - 160)), (Pt 1760 ($hz - 70)), (Pt 1840 $hz))
$g.FillPolygon((New-Object System.Drawing.SolidBrush (Hex '#2A2238')), $rock)
$islet = @((Pt 1250 $hz), (Pt 1300 ($hz - 40)), (Pt 1350 ($hz - 55)), (Pt 1410 $hz))
$g.FillPolygon((New-Object System.Drawing.SolidBrush (Hex '#3A2D45')), $islet)
# sea
$sea = New-Object System.Drawing.Drawing2D.LinearGradientBrush (Pt 0 $hz), (Pt 0 $H), (Hex '#1B6CA8'), (Hex '#0F2A3F')
$g.FillRectangle($sea, 0, $hz, $W, $H - $hz)
# sun reflection: shimmering horizontal strokes
$rnd = New-Object System.Random 11
for ($i = 0; $i -lt 70; $i++) {
    $y = $hz + 6 + [Math]::Pow($rnd.NextDouble(), 1.6) * ($H - $hz - 20)
    $spread = 40 + ($y - $hz) * 0.9
    $x = $sx + ($rnd.NextDouble() * 2 - 1) * $spread
    $len = $rnd.Next(30, 140)
    $g.DrawLine((New-Object System.Drawing.Pen (Hex '#FFD27A' ($rnd.Next(60, 170))), 3), [single]($x - $len / 2), [single]$y, [single]($x + $len / 2), [single]$y)
}
# gentle wave lines
for ($i = 0; $i -lt 40; $i++) {
    $y = $hz + 20 + $rnd.NextDouble() * ($H - $hz - 30); $x = $rnd.Next(0, $W); $len = $rnd.Next(60, 220)
    $g.DrawLine((New-Object System.Drawing.Pen (Hex '#FFFFFF' 28), 2), [single]$x, [single]$y, [single]($x + $len), [single]$y)
}
# birds
$birdPen = New-Object System.Drawing.Pen (Hex '#2A2238' 200), 3
foreach ($bd in @(@(1080, 250, 1.0), @(1140, 220, 0.8), @(1010, 300, 0.7))) {
    $bx, $by, $s = $bd
    $g.DrawArc($birdPen, [single]($bx - 22 * $s), [single]$by, [single](22 * $s), [single](12 * $s), 200, 140)
    $g.DrawArc($birdPen, [single]$bx, [single]$by, [single](22 * $s), [single](12 * $s), 200, 140)
}
$b.Save("$out\cover.png", [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $b.Dispose()
}
"cover written: $out\cover.png"
