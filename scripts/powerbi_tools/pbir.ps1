# helpers for writing PBIR report json. dot-source it, build pages with the New-* functions, then Write-Report

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:VisualSchema = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.0.0/schema.json"
$script:PageSchema = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.0.0/schema.json"

# colours + fonts get overridden by each report's build script
$C = @{
    Accent = '#A3661F'; Amber = '#A3661F'; Teal = '#2F5C55'; Grey = '#8C959F'; Red = '#9A3A26'; Green = '#3D6B47'
    Ink = '#1E2A38'; Muted = '#6B7480'; Paper = '#FAF7F0'; White = '#FFFFFF'; Rule = '#E4DED0'
}
$Style = @{ Font = 'Segoe UI'; HeadFont = 'Segoe UI Semibold'; CardFont = 'Segoe UI Semibold'; CoverValueSize = 30; Radius = 6; CardBar = $null; ContentsTitle = 'INSIDE THIS REPORT'; ContentsNumber = '{0:D2}  ' }

function Save-Json($Path, $Obj) {
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $json = ConvertTo-Json -InputObject $Obj -Depth 80
    [IO.File]::WriteAllText($Path, $json, $script:Utf8NoBom)
}

function L($v) {
    if ($v -is [bool]) { $s = if ($v) { 'true' } else { 'false' } }
    elseif ($v -is [int] -or $v -is [long]) { $s = "${v}L" }
    elseif ($v -is [double] -or $v -is [decimal]) { $s = "${v}D" }
    else { $s = "'" + ($v -replace "'", "''") + "'" }
    @{ expr = @{ Literal = @{ Value = $s } } }
}
function LitRaw($v) {
    # same but without the expr wrapper (filters/selectors)
    if ($v -is [bool]) { $s = if ($v) { 'true' } else { 'false' } }
    elseif ($v -is [int] -or $v -is [long]) { $s = "${v}L" }
    elseif ($v -is [double]) { $s = "${v}D" }
    else { $s = "'" + ($v -replace "'", "''") + "'" }
    @{ Literal = @{ Value = $s } }
}
function Solid($hex) { @{ solid = @{ color = (L $hex) } } }
function Col($t, $c) { @{ Column = @{ Expression = @{ SourceRef = @{ Entity = $t } }; Property = $c } } }
function Meas($t, $m) { @{ Measure = @{ Expression = @{ SourceRef = @{ Entity = $t } }; Property = $m } } }
function MeasFill($t, $m) {
    # colour from a measure that returns a hex code
    @{ solid = @{ color = @{ expr = (Meas $t $m) } } }
}
function Proj($field, $display) {
    $p = $field.Values | Select-Object -First 1
    $entity = $p.Expression.SourceRef.Entity; $prop = $p.Property
    $o = [ordered]@{ field = $field; queryRef = "$entity.$prop"; nativeQueryRef = $prop }
    if ($display) { $o.displayName = $display }
    $o
}
function Role([object[]]$projs) { @{ projections = @($projs) } }
function Props([hashtable]$h) { , @(@{ properties = $h }) }
function PropsSel([hashtable]$h, $sel) { @{ properties = $h; selector = $sel } }
function AllPoints { @{ data = @(@{ dataViewWildcard = @{ matchingOption = 1 } }) } }
function MetaSel($t, $m) { @{ metadata = "$t.$m" } }
function ValueSel($t, $c, $v) {
    @{ data = @(@{ scopeId = @{ Comparison = @{ ComparisonKind = 0; Left = (Col $t $c); Right = (LitRaw $v) } } }) }
}

function FilterIn($name, $t, $c, [object[]]$values) {
    [ordered]@{
        name = $name; field = (Col $t $c); type = 'Categorical'
        filter = @{
            Version = 2; From = @(@{ Name = 's'; Entity = $t; Type = 0 })
            Where = @(@{ Condition = @{ In = @{
                Expressions = @(@{ Column = @{ Expression = @{ SourceRef = @{ Source = 's' } }; Property = $c } })
                Values = @($values | ForEach-Object { , @(LitRaw $_) })
            } } })
        }
    }
}
function FilterRange($name, $t, $c, $min, $max) {
    $colRef = @{ Column = @{ Expression = @{ SourceRef = @{ Source = 's' } }; Property = $c } }
    $conds = @()
    if ($null -ne $min) { $conds += @{ Comparison = @{ ComparisonKind = 2; Left = $colRef; Right = (LitRaw $min) } } }
    if ($null -ne $max) { $conds += @{ Comparison = @{ ComparisonKind = 4; Left = $colRef; Right = (LitRaw $max) } } }
    $cond = if ($conds.Count -eq 2) { @{ And = @{ Left = $conds[0]; Right = $conds[1] } } } else { $conds[0] }
    [ordered]@{
        name = $name; field = (Col $t $c); type = 'Advanced'
        filter = @{ Version = 2; From = @(@{ Name = 's'; Entity = $t; Type = 0 }); Where = @(@{ Condition = $cond }) }
    }
}

$script:Z = 0
function New-Visual {
    param($Name, $Type, [int[]]$Pos, $Query, $Objects, $Container, $Filters, $Sort, [switch]$NoBackground, $BgColor, [switch]$NoPadding, [switch]$NoBorder, $BgTransparency = 0)
    $script:Z += 100
    $vco = if ($Container) { $Container } else { @{} }
    if (-not $vco.ContainsKey('background')) {
        $bgc = if ($BgColor) { $BgColor } else { $C.White }
        $vco.background = Props @{ show = (L ((-not $NoBackground) -or [bool]$BgColor)); color = (Solid $bgc); transparency = (L ([double]$BgTransparency)) }
    }
    if (-not $vco.ContainsKey('border')) {
        $vco.border = Props @{ show = (L (-not ($NoBackground -or $NoBorder))); color = (Solid $C.Rule); radius = (L $(if ($BgColor) { 0D } else { [double]$Style.Radius })) }
    }
    if (-not $vco.ContainsKey('padding')) {
        $pad = if ($NoPadding) { 0D } else { 10D }
        $vco.padding = Props @{ top = (L $pad); bottom = (L $pad); left = (L ($pad * 1.2)); right = (L ($pad * 1.2)) }
    }
    $vco.visualHeader = Props @{ show = (L $false) }
    $visual = [ordered]@{ visualType = $Type }
    if ($Query) {
        $q = [ordered]@{ queryState = $Query }
        if ($Sort) { $q.sortDefinition = @{ sort = @($Sort); isDefaultSort = $true } }
        $visual.query = $q
    }
    if ($Objects) { $visual.objects = $Objects }
    $visual.visualContainerObjects = $vco
    $visual.drillFilterOtherVisuals = $true
    $v = [ordered]@{
        '$schema' = $script:VisualSchema
        name      = $Name
        position  = [ordered]@{ x = $Pos[0]; y = $Pos[1]; z = $script:Z; width = $Pos[2]; height = $Pos[3]; tabOrder = $script:Z }
        visual    = $visual
    }
    if ($Filters) { $v.filterConfig = @{ filters = @($Filters) } }
    $v
}

function Title($text, $MeasureTable, $Measure) {
    $t = if ($Measure) { @{ expr = (Meas $MeasureTable $Measure) } } else { (L $text) }
    Props @{ show = (L $true); text = $t; fontColor = (Solid $C.Ink); fontSize = (L 12D); bold = (L $true) }
}

# measure-is-not-blank filter, stops slicers listing values with no data on the page
function FilterHasData($name, $t, $m) {
    [ordered]@{
        name = $name; field = (Meas $t $m); type = 'Advanced'
        filter = @{
            Version = 2; From = @(@{ Name = 'm'; Entity = $t; Type = 0 })
            Where = @(@{ Condition = @{ Not = @{ Expression = @{ Comparison = @{
                ComparisonKind = 0
                Left = @{ Measure = @{ Expression = @{ SourceRef = @{ Source = 'm' } }; Property = $m } }
                Right = @{ Literal = @{ Value = 'null' } }
            } } } } })
        }
    }
}

# a DAX text measure shown as a paragraph (one-cell table, header hidden)
function New-TextMeasure {
    param($Name, [int[]]$Pos, $Table, $Measure, $FontSize = 10, $FontFamily = $Style.Font)
    New-Visual -Name $Name -Type 'tableEx' -Pos $Pos -NoBackground -NoPadding `
        -Query @{ Values = (Role (Proj (Meas $Table $Measure) ' ')) } `
        -Objects @{
            values        = (Props @{ wordWrap = (L $true); fontColor = (Solid $C.Ink); fontSize = (L ([double]$FontSize)); backColorPrimary = (Solid $C.White); backColorSecondary = (Solid $C.White); fontFamily = (L $FontFamily) })
            columnHeaders = (Props @{ fontColor = (Solid $C.White); backColor = (Solid $C.White); fontSize = (L 1D); wordWrap = (L $false) })
            grid          = (Props @{ gridVertical = (L $false); gridHorizontal = (L $false); outlineColor = (Solid $C.White); rowPadding = (L 0D); outlineWeight = (L 0D) })
            total         = (Props @{ totals = (L $false) })
            columnWidth   = @(PropsSel @{ value = (L ([double]($Pos[2] - 24))) } (MetaSel $Table $Measure))
        }
}

function New-TextBox {
    param($Name, [int[]]$Pos, [object[]]$Paragraphs, [switch]$Panel, $BgColor, $BgTransparency = 0)
    $vco = @{}
    $vis = New-Visual -Name $Name -Type 'textbox' -Pos $Pos -NoBackground:(-not $Panel) -Container $vco -NoPadding:(-not $Panel) -BgColor $BgColor -BgTransparency $BgTransparency -NoBorder:([bool]$BgColor) `
        -Objects @{ general = (Props @{ paragraphs = @($Paragraphs) }) }
    $vis
}
function Para([object[]]$runs, $align) {
    $p = [ordered]@{ textRuns = @($runs) }
    if ($align) { $p.horizontalTextAlignment = $align }
    $p
}
function Run($text, $size = 11, $color = $C.Ink, [switch]$Bold, [switch]$Head, [switch]$Italic) {
    $family = if ($Head) { $Style.HeadFont } else { $Style.Font }
    $style = [ordered]@{ fontFamily = $family; fontSize = "${size}pt"; color = $color }
    if ($Bold) { $style.fontWeight = 'bold' }
    if ($Italic) { $style.fontStyle = 'italic' }
    [ordered]@{ value = $text; textStyle = $style }
}

function New-Card {
    param($Name, [int[]]$Pos, $Table, $Measure, $Label, $Color = $C.Ink, [switch]$Transparent, $LabelColor = $C.Muted, $ValueSize = 24, $LabelSize = 10, [switch]$NoLabel)
    New-Visual -Name $Name -Type 'card' -Pos $Pos -NoBorder -NoBackground:$Transparent `
        -Query @{ Values = (Role (Proj (Meas $Table $Measure) $Label)) } `
        -Objects @{
            labels         = (Props @{ color = (Solid $Color); fontSize = (L ([double]$ValueSize)); fontFamily = (L $Style.CardFont) })
            categoryLabels = (Props @{ show = (L (-not $NoLabel)); color = (Solid $LabelColor); fontSize = (L ([double]$LabelSize)) })
        }
}

function New-Slicer {
    param($Name, [int[]]$Pos, $Table, $Column, $Header, $Selected, [switch]$Single, [object[]]$HasData)
    $objects = @{
        data   = (Props @{ mode = (L 'Dropdown') })
        header = (Props @{ show = (L $true); text = (L $Header); fontColor = (Solid $C.Muted); textSize = (L 9D) })
        items  = (Props @{ fontColor = (Solid $C.Ink); textSize = (L 10D) })
    }
    if ($Single) { $objects.selection = (Props @{ strictSingleSelect = (L $true) }) }
    if ($Selected) {
        $f = FilterIn 'sel' $Table $Column $Selected
        $objects.general = (Props @{ filter = @{ filter = $f.filter } })
    }
    $filters = if ($HasData) { @(FilterHasData 'hasdata' $HasData[0] $HasData[1]) } else { $null }
    New-Visual -Name $Name -Type 'slicer' -Pos $Pos -Query @{ Values = (Role (Proj (Col $Table $Column))) } -Objects $objects `
        -Container @{ padding = (Props @{ top = (L 4D); bottom = (L 4D); left = (L 8D); right = (L 8D) }) } -Filters $filters
}

function Axis-Objects {
    param([switch]$NoGrid, $ValueStart, $ValueEnd, [switch]$Invert, [switch]$Categorical, $ValueFormatUnits, [switch]$HideValueAxis, $CatMargin, $CatPadding)
    $va = @{ show = (L (-not $HideValueAxis)); labelColor = (Solid $C.Muted); fontSize = (L 9D); showAxisTitle = (L $false); gridlineShow = (L (-not $NoGrid)); gridlineColor = (Solid $C.Rule) }
    if ($null -ne $ValueStart) { $va.start = (L ([double]$ValueStart)) }
    if ($null -ne $ValueEnd) { $va.end = (L ([double]$ValueEnd)) }
    if ($Invert) { $va.invertAxis = (L $true) }
    if ($ValueFormatUnits) { $va.labelDisplayUnits = (L ([double]$ValueFormatUnits)) }
    $ca = @{ show = (L $true); labelColor = (Solid $C.Ink); fontSize = (L 9D); showAxisTitle = (L $false) }
    if ($Categorical) { $ca.axisType = (L 'Categorical') }
    if ($CatMargin) { $ca.maxMarginFactor = (L ([int]$CatMargin)) }
    if ($null -ne $CatPadding) { $ca.innerPadding = (L ([int]$CatPadding)) }
    @{ valueAxis = (Props $va); categoryAxis = (Props $ca) }
}

function Write-Report {
    param($ReportDir, [object[]]$Pages, $ActivePage)
    $pagesDir = Join-Path $ReportDir 'definition\pages'
    if (Test-Path $pagesDir) { Remove-Item -Recurse -Force $pagesDir }
    foreach ($p in $Pages) {
        $pd = Join-Path $pagesDir $p.Name
        $page = [ordered]@{
            '$schema'     = $script:PageSchema
            name          = $p.Name
            displayName   = $p.DisplayName
            displayOption = 'FitToPage'
            height        = 720
            width         = 1280
            objects       = @{
                background = (Props @{ color = (Solid $C.Paper); transparency = (L 0D) })
            }
        }
        if ($p.Filters) { $page.filterConfig = @{ filters = @($p.Filters) } }
        # pairs of (slicer, visual) that shouldn't filter each other
        if ($p.NoFilter) {
            $page.visualInteractions = @($p.NoFilter | ForEach-Object { [ordered]@{ source = $_[0]; target = $_[1]; type = 'NoFilter' } })
        }
        Save-Json (Join-Path $pd 'page.json') $page
        foreach ($v in $p.Visuals) {
            Save-Json (Join-Path $pd "visuals\$($v.name)\visual.json") $v
        }
    }
    Write-ReportJson $ReportDir
    if (-not $ActivePage) { $ActivePage = $Pages[0].Name }
    Save-Json (Join-Path $pagesDir 'pages.json') ([ordered]@{
        '$schema'      = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/pagesMetadata/1.0.0/schema.json"
        pageOrder      = @($Pages | ForEach-Object { $_.Name })
        activePageName = $ActivePage
    })
}

# title, subtitle, slicers, footer
function Page-Chrome {
    param($Prefix, $TitleText, $SubtitleText, $Footer, [object[]]$Slicers, [string[]]$Band, $Kicker)
    $v = @()
    if ($script:BandItem) { $v += New-Image "${Prefix}_band" @(0, 0, 1280, 6) $script:BandItem }
    if ($Kicker) { $v += New-TextBox "${Prefix}_kicker" @(20, 10, 820, 20) @(Para @(Run $Kicker 9 $C.Accent -Bold)) }
    $v += New-TextBox "${Prefix}_title" @(20, 26, 820, 40) @(Para @(Run $TitleText 19 $C.Ink -Bold -Head))
    $v += New-TextBox "${Prefix}_subtitle" @(20, 64, 820, 28) @(Para @(Run $SubtitleText 10 $C.Muted))
    $v += $Slicers
    $v += New-TextBox "${Prefix}_footer" @(20, 692, 1240, 22) @(Para @(Run $Footer 8 $C.Muted))
    $v
}

$script:Resources = @()
function Add-ReportImage($ReportDir, $Source, $ItemName) {
    $dir = Join-Path $ReportDir 'StaticResources\RegisteredResources'
    New-Item -ItemType Directory -Force $dir | Out-Null
    Copy-Item $Source (Join-Path $dir $ItemName) -Force
    $script:Resources += $ItemName
}
function New-Image($Name, [int[]]$Pos, $ItemName, $Scaling = 'Fill') {
    New-Visual -Name $Name -Type 'image' -Pos $Pos -NoBackground -Container @{ padding = (Props @{ top = (L 0D); bottom = (L 0D); left = (L 0D); right = (L 0D) }) } `
        -Objects @{
            general      = (Props @{ imageUrl = @{ expr = @{ ResourcePackageItem = @{ PackageName = 'RegisteredResources'; PackageType = 1; ItemName = $ItemName } } } })
            imageScaling = (Props @{ imageScalingType = (L $Scaling) })
        }
}
function Write-ReportJson($ReportDir) {
    $items = @($script:Resources | Select-Object -Unique | ForEach-Object { [ordered]@{ name = $_; path = $_; type = 'Image' } })
    $pkgs = @()
    if ($items) { $pkgs += [ordered]@{ name = 'RegisteredResources'; type = 'RegisteredResources'; items = $items } }
    Save-Json (Join-Path $ReportDir 'definition\report.json') ([ordered]@{
        '$schema'        = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/report/3.0.0/schema.json"
        themeCollection  = @{}
        resourcePackages = $pkgs
        settings         = [ordered]@{ useStylableVisualContainerHeader = $true; useEnhancedTooltips = $true }
    })
}

# cover: full page image, see-through panel with the text, kpi cards on the right
function Cover-Page {
    param($Prefix, $ImageItem, $Kicker, $TitleText, $SubtitleText, [string[]]$Contents, $PanelColor, $KickerColor, $LogoItem, [object[]]$Cards, $Footer)
    $v = @()
    $v += New-Image "${Prefix}_image" @(0, 0, 1280, 720) $ImageItem
    $v += New-TextBox "${Prefix}_panel" @(40, 40, 600, 640) @(Para @(Run ' ' 2)) -BgColor $PanelColor -BgTransparency 12
    $top = 70
    if ($LogoItem) { $v += New-Image "${Prefix}_logo" @(72, 64, 150, 60) $LogoItem 'Fit'; $top = 140 }
    $paras = @(
        (Para @(Run $Kicker 11 $KickerColor -Bold))
        (Para @(Run ' ' 4))
        (Para @(Run $TitleText 30 '#FFFFFF' -Bold -Head))
        (Para @(Run ' ' 4))
        (Para @(Run $SubtitleText 13 '#D9DEE5'))
        (Para @(Run ' ' 10))
        (Para @(Run $Style.ContentsTitle 10 $KickerColor -Bold))
    )
    $n = 1
    foreach ($c in $Contents) { $paras += Para @((Run ($Style.ContentsNumber -f $n) 12 $KickerColor -Bold), (Run $c 12 '#FFFFFF')); $n++ }
    $paras += Para @(Run ' ' 10)
    $paras += Para @(Run $Footer 9 '#AEB6C2')
    $v += New-TextBox "${Prefix}_text" @(72, $top, 540, (640 - ($top - 40) - 20)) $paras
    if ($Cards) {
        $w = 290; $h = 96; $gap = 12; $y0 = 680 - ($Cards.Count * $h + ($Cards.Count - 1) * $gap)
        for ($i = 0; $i -lt $Cards.Count; $i++) {
            $c = $Cards[$i]
            $v += New-Card "${Prefix}_kpi$i" @(950, ($y0 + $i * ($h + $gap)), $w, $h) $c[0] $c[1] $c[2] $c[3]
        }
    }
    $v
}

# other cover style - title straight on the photo, numbers + contents in a band along the bottom
function Cover-Page-Band {
    param($Prefix, $ImageItem, $Kicker, $TitleText, $SubtitleText, [string[]]$Contents, $BandColor, $KickerColor, [object[]]$Stats, $Footer)
    $v = @()
    $v += New-Image "${Prefix}_image" @(0, 0, 1280, 720) $ImageItem
    $v += New-TextBox "${Prefix}_title" @(60, 54, 700, 230) @(
        (Para @(Run $Kicker 11 $KickerColor -Bold))
        (Para @(Run ' ' 4))
        (Para @(Run $TitleText 36 '#FFFFFF' -Bold -Head))
        (Para @(Run ' ' 4))
        (Para @(Run $SubtitleText 13 '#F3E9DC'))
    )
    $v += New-TextBox "${Prefix}_band" @(0, 488, 1280, 232) @(Para @(Run ' ' 2)) -BgColor $BandColor -BgTransparency 18
    $sw = 230
    for ($i = 0; $i -lt $Stats.Count; $i++) {
        $s = $Stats[$i]; $x = 48 + $i * ($sw + 20)
        $v += New-Card "${Prefix}_stat$i" @($x, 520, $sw, 120) $s[0] $s[1] $s[2] $s[3] -Transparent -LabelColor '#E6EEF5' -ValueSize $Style.CoverValueSize -LabelSize 10
        if ($i -gt 0) { $v += New-TextBox "${Prefix}_rule$i" @(($x - 12), 536, 2, 88) @() -BgColor '#FFFFFF' -BgTransparency 65 }
    }
    $cx = 48 + $Stats.Count * ($sw + 20) + 10
    $v += New-TextBox "${Prefix}_rule_c" @(($cx - 16), 520, 2, 140) @() -BgColor '#FFFFFF' -BgTransparency 65
    $paras = @((Para @(Run $Style.ContentsTitle 10 $KickerColor -Bold)))
    $n = 1
    foreach ($c in $Contents) { $paras += Para @((Run ($Style.ContentsNumber -f $n) 11 $KickerColor -Bold), (Run $c 11 '#FFFFFF')); $n++ }
    $v += New-TextBox "${Prefix}_contents" @($cx, 512, (1240 - $cx), 160) $paras
    $v += New-TextBox "${Prefix}_footer" @(48, 680, 1180, 24) @(Para @(Run $Footer 9 '#C9D6E2'))
    $v
}
# coloured stripe image for the top of each page
function Set-Band($ReportDir, [string[]]$Colours, $ItemName = 'band.png') {
    Add-Type -AssemblyName System.Drawing
    $w = 2560; $h = 12
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $seg = $w / $Colours.Count
    for ($i = 0; $i -lt $Colours.Count; $i++) {
        $br = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($Colours[$i]))
        $g.FillRectangle($br, [single]($i * $seg), 0, [single]($seg + 1), $h)
    }
    $tmp = Join-Path $env:TEMP $ItemName
    $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
    Add-ReportImage $ReportDir $tmp $ItemName
    $script:BandItem = $ItemName
}
function Card-Row($p, [object[]]$cards) {
    # cards: @(table, measure, label, colour[, valueSize])
    $n = $cards.Count; $gap = 16; $w = [int]((1240 - ($n - 1) * $gap) / $n)
    for ($i = 0; $i -lt $n; $i++) {
        $c = $cards[$i]; $size = if ($c.Count -gt 4) { $c[4] } else { 24 }
        $x = 20 + $i * ($w + $gap)
        New-Card "${p}_card$i" @($x, 94, $w, 82) $c[0] $c[1] $c[2] $c[3] -ValueSize $size
        if ($Style.CardBar) { New-TextBox "${p}_cardbar$i" @($x, 94, 4, 82) @() -BgColor $Style.CardBar }
    }
}
function Header-Slicers([object[]]$specs) {
    # specs: @(name, table, column, header, hasDataTable, hasDataMeasure[, selected[, single]])
    $xs = if ($specs.Count -eq 1) { @(1060) } else { @(852, 1060) }
    for ($i = 0; $i -lt $specs.Count; $i++) {
        $s = $specs[$i]
        $sel = if ($s.Count -gt 6) { $s[6] } else { $null }
        $single = ($s.Count -gt 7) -and $s[7]
        New-Slicer $s[0] @($xs[$i], 14, 200, 60) $s[1] $s[2] $s[3] -HasData @($s[4], $s[5]) -Selected $sel -Single:$single
    }
}
# story panel on the right - headline + paragraph measures that follow the slicers, and a method note
function Story-Panel($p, $table, $headMeasure, $bodyMeasure, [string]$note) {
    $x = 636; $y = 186; $w = 624; $h = 500
    $inner = $w - 28
    # rough height for the note: ~5.1px a character, ~18.5px a line at 8pt
    $noteLines = [Math]::Ceiling(($note.Length * 5.1) / $inner)
    $noteH = [int]($noteLines * 18.5 + 10)
    $noteY = $y + $h - $noteH - 12
    $out = @()
    $out += New-TextBox "${p}_panel" @($x, $y, $w, $h) @(Para @(Run ' ' 2)) -Panel
    $out += New-TextMeasure "${p}_head" @(($x + 8), ($y + 12), ($w - 16), 58) $table $headMeasure 12 -FontFamily $Style.CardFont
    $out += New-TextMeasure "${p}_body" @(($x + 8), ($y + 76), ($w - 16), ($noteY - $y - 84)) $table $bodyMeasure 10
    $out += New-TextBox "${p}_note" @(($x + 14), $noteY, $inner, $noteH) @(Para @(Run $note 8 $C.Muted))
    $out
}

# last page - before/after scorecard on the left, takeaways on the right
function Verdict-Page {
    param($Prefix, $Kicker, $TitleText, $SubtitleText, $Footer, [object[]]$Rows, [object[]]$Takeaways, $ValueHeader = 'BEFORE  >  UNDER THE CAP', $HeaderY = 94)
    # Rows: @(table, measure, metric, explanation, verdict, chipColour)
    $v = Page-Chrome $Prefix $TitleText $SubtitleText $Footer @() $null $Kicker
    $v += New-TextBox "${Prefix}_hdr_m" @(36, $HeaderY, 300, 22) @(Para @(Run 'MEASURE' 8 $C.Muted -Bold))
    $v += New-TextBox "${Prefix}_hdr_v" @(372, $HeaderY, 240, 22) @(Para @(Run $ValueHeader 8 $C.Muted -Bold) 'center')
    $v += New-TextBox "${Prefix}_hdr_c" @(628, $HeaderY, 120, 22) @(Para @(Run 'VERDICT' 8 $C.Muted -Bold) 'center')
    $n = $Rows.Count; $top = $HeaderY + 22; $rowH = [int]((686 - $top) / $n)
    for ($i = 0; $i -lt $n; $i++) {
        $r = $Rows[$i]; $ry = $top + $i * $rowH
        $v += New-TextBox "${Prefix}_row$i" @(20, $ry, 740, ($rowH - 6)) @(Para @(Run ' ' 2)) -Panel
        $v += New-TextBox "${Prefix}_row${i}_m" @(36, ($ry + 7), 330, ($rowH - 18)) @(
            (Para @(Run $r[2] 10.5 $C.Ink -Bold))
            (Para @(Run $r[3] 8.5 $C.Muted)))
        $v += New-Card "${Prefix}_row${i}_v" @(372, ($ry + 3), 240, ($rowH - 12)) $r[0] $r[1] ' ' $C.Ink -ValueSize 17 -NoLabel -Transparent
        $chipY = $ry + [int](($rowH - 6) / 2) - 13
        $v += New-TextBox "${Prefix}_row${i}_c" @(632, $chipY, 112, 26) @(Para @(Run $r[4] 9 '#FFFFFF' -Bold) 'center') -BgColor $r[5]
    }
    $paras = @()
    foreach ($t in $Takeaways) {
        if ($t -is [array]) { $paras += Para @(Run $t[0] 11 $C.Accent -Bold); $paras += Para @(Run $t[1] 9.5 $C.Ink) }
        else { $paras += Para @(Run $t 9.5 $C.Ink) }
        $paras += Para @(Run ' ' 4)
    }
    $v += New-TextBox "${Prefix}_takeaways" @(776, ($HeaderY + 2), 484, (686 - $HeaderY - 2)) $paras -Panel
    $v
}
