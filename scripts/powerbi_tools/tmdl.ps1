# add measures / columns / relationships to the TMDL. fine to run again - measures get replaced,
# columns and relationships that are already there get skipped

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Format-Measure($m) {
    # $m = @{ Name; Expr; Format }  - Expr may be multi-line.
    $lines = @()
    $exprLines = ($m.Expr.Trim() -split "`r?`n")
    if ($exprLines.Count -eq 1) {
        $lines += "`tmeasure '$($m.Name)' = $($exprLines[0])"
    } else {
        $lines += "`tmeasure '$($m.Name)' ="
        # Expression body must sit deeper than the measure's own properties (2 tabs).
        $exprLines | ForEach-Object { $lines += "`t`t`t" + $_.TrimEnd() }
    }
    if ($m.Format) { $lines += "`t`tformatString: $($m.Format)" }
    $lines += "`t`tlineageTag: $([guid]::NewGuid())"
    $lines += ""
    $lines -join "`n"
}

function Test-ModelHas($defDir, [string]$pattern) {
    $null -ne (Get-ChildItem $defDir -Recurse -Filter *.tmdl | Select-String -Pattern $pattern -SimpleMatch | Select-Object -First 1)
}

# cut out the block starting at $header, up to the next object at the same level
function Remove-Block([string]$text, [string]$headerRegex) {
    $lines = $text -split "`n"
    $out = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($l in $lines) {
        if ($skip -and $l -match "^`t[^`t]") { $skip = $false }
        if (-not $skip -and $l -match $headerRegex) { $skip = $true; continue }
        if (-not $skip) { $out.Add($l) }
    }
    ($out -join "`n")
}

function Add-ToTable($defDir, $table, [object[]]$measures) {
        foreach ($m in $measures) {
        $rx = "^`tmeasure '?" + [regex]::Escape($m.Name) + "'? ="
        foreach ($tf in Get-ChildItem (Join-Path $defDir 'tables') -Filter *.tmdl) {
            $t = [IO.File]::ReadAllText($tf.FullName).Replace("`r`n", "`n")
            if ($t -match "(?m)$rx") { [IO.File]::WriteAllText($tf.FullName, (Remove-Block $t $rx), $script:Utf8NoBom) }
        }
    }
    $f = Join-Path $defDir "tables\$table.tmdl"
    $text = [IO.File]::ReadAllText($f).Replace("`r`n", "`n")
    $nl = $text.IndexOf("`n", $text.IndexOf("lineageTag:")) + 1
    $insert = "`n" + (($measures | ForEach-Object { Format-Measure $_ }) -join "`n")
    [IO.File]::WriteAllText($f, $text.Insert($nl, $insert), $script:Utf8NoBom)
}

function Remove-Measures($defDir, [string[]]$names) {
    foreach ($nm in $names) {
        $rx = "^`tmeasure '?" + [regex]::Escape($nm) + "'? ="
        foreach ($tf in Get-ChildItem (Join-Path $defDir 'tables') -Filter *.tmdl) {
            $t = [IO.File]::ReadAllText($tf.FullName).Replace("`r`n", "`n")
            if ($t -match "(?m)$rx") { [IO.File]::WriteAllText($tf.FullName, (Remove-Block $t $rx), $script:Utf8NoBom) }
        }
    }
}

function Add-CalcColumn($defDir, $table, $name, $expr, $dataType = 'string', $sortBy) {
    $f = Join-Path $defDir "tables\$table.tmdl"
    $text = [IO.File]::ReadAllText($f).Replace("`r`n", "`n")
    if ($text -match "(?m)^`tcolumn '?$([regex]::Escape($name))'?( |$)") { return }
    $block = "`tcolumn $name = $expr`n`t`tdataType: $dataType`n`t`tlineageTag: $([guid]::NewGuid())`n`t`tsummarizeBy: none`n"
    if ($sortBy) { $block += "`t`tsortByColumn: $sortBy`n" }
    $block += "`n"
    $at = $text.IndexOf("`n`tpartition ")
    [IO.File]::WriteAllText($f, $text.Insert($at + 1, $block), $script:Utf8NoBom)
}

function Edit-Table($defDir, $table, [scriptblock]$transform) {
    $f = Join-Path $defDir "tables\$table.tmdl"
    $text = & $transform ([IO.File]::ReadAllText($f).Replace("`r`n", "`n"))
    [IO.File]::WriteAllText($f, $text, $script:Utf8NoBom)
}

function Add-Relationship($defDir, $from, $to) {
    $f = Join-Path $defDir 'relationships.tmdl'
    $text = [IO.File]::ReadAllText($f).Replace("`r`n", "`n")
    if ($text -match [regex]::Escape("fromColumn: $from")) { return }
    $text = $text.TrimEnd() + "`n`nrelationship $([guid]::NewGuid())`n`tfromColumn: $from`n`ttoColumn: $to`n"
    [IO.File]::WriteAllText($f, $text, $script:Utf8NoBom)
}
