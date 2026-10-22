# 'cli.ps1 build': src/ -> dist/Mods/<mod>/content/

# tools/lib/cr2w_swf.py (isolated mode: never imports from the current folder)
function Invoke-StlCr2w($Tc, [string[]]$PyArgs) {
    $log = & $Tc.Python -I $Tc.Cr2wSwf @PyArgs 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) {
        $log | Write-Host
        throw "cr2w_swf.py $($PyArgs[0]) failed"
    }
}

function Get-StlContentDir($Cfg) {
    $dir = Join-Path $Cfg.Paths.ModDist 'content'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $dir
}

# runs wcc_lite from its own folder (it finds gameconf.cfg relative to the current folder)
function Invoke-StlWcc($Tc, [string[]]$WccArgs) {
    Push-Location $Tc.WccDir
    try {
        $log = & .\wcc_lite.exe @WccArgs 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0) {
            $log | Select-Object -Last 20 | Write-Host
            throw "wcc_lite $($WccArgs[0]) failed (exit $LASTEXITCODE)"
        }
    } finally {
        Pop-Location
    }
}

# .ws files are used as-is: the game compiles them at startup
function Build-StlScripts($Cfg) {
    $out = Join-Path (Get-StlContentDir $Cfg) 'scripts\local'
    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    New-Item -ItemType Directory -Force $out | Out-Null
    $files = Get-ChildItem (Join-Path $Cfg.Paths.Src 'scripts') -Filter *.ws
    $files | Copy-Item -Destination $out
    Write-Host "scripts: $($files.Count) file(s)"
}

# first string id of the id space: 211nnnn000 (4 digits) or 21nnnnn000 (5 digits)
function Get-StlStringBase([int]$IdSpace) {
    if ($IdSpace -lt 10000) { return [long]2110000000 + [long]$IdSpace * 1000 }
    [long]2100000000 + [long]$IdSpace * 1000
}

# key -> sorted "$n$" markers of a strings csv
function Get-StlStringMarkers([string]$Csv) {
    $map = @{}
    foreach ($line in [IO.File]::ReadAllLines($Csv, (New-Object Text.UTF8Encoding $false))) {
        $cols = $line.Split('|')
        if ($line -match '^\d{10}\|' -and $cols.Count -ge 4) {
            $map[$cols[2].Trim()] = (([regex]::Matches($cols[3], '\$\d\$') | ForEach-Object Value | Sort-Object) -join ' ')
        }
    }
    $map
}

# every language must have the keys of en.csv, with the same markers per key
function Test-StlStrings($Cfg) {
    $ref = Get-StlStringMarkers (Join-Path $Cfg.Paths.Src 'strings\en.csv')
    $problems = @()
    foreach ($lang in $Cfg.Strings.Languages) {
        $csv = Join-Path $Cfg.Paths.Src "strings\$lang.csv"
        if (-not (Test-Path $csv)) { $problems += "${lang}: src\strings\$lang.csv missing"; continue }
        $map = Get-StlStringMarkers $csv
        foreach ($key in $ref.Keys) {
            if (-not $map.ContainsKey($key)) { $problems += "${lang}: missing $key" }
            elseif ($map[$key] -ne $ref[$key]) { $problems += "${lang}: $key has markers '$($map[$key])', expected '$($ref[$key])'" }
        }
        foreach ($key in $map.Keys) {
            if (-not $ref.ContainsKey($key)) { $problems += "${lang}: unknown key $key (not in en.csv)" }
        }
    }
    $problems
}

# src/strings/<lang>.csv -> <lang>.w3strings (v164, the format Remastered reads).
# Only the last 3 digits of each id in the csv matter: the id space comes from the config.
function Build-StlStrings($Cfg, $Tc) {
    Assert-StlTool 'w3strings encoder' $Tc.W3Strings
    $problems = @(Test-StlStrings $Cfg)
    if ($problems.Count) { $problems | ForEach-Object { Write-Host "  $_" }; throw "strings: $($problems.Count) problem(s) in src\strings" }
    $out = Get-StlContentDir $Cfg
    $base = Get-StlStringBase $Cfg.Strings.IdSpace
    $tmp = Join-Path $Cfg.Paths.Build 'strings'
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $utf8 = New-Object Text.UTF8Encoding $false
    foreach ($lang in $Cfg.Strings.Languages) {
        $lines = [IO.File]::ReadAllLines((Join-Path $Cfg.Paths.Src "strings\$lang.csv"), $utf8)
        $lines = $lines | ForEach-Object {
            if ($_ -match '^(\d{10})\|') { ($base + [long]$Matches[1] % 1000).ToString() + $_.Substring(10) } else { $_ }
        }
        $csv = Join-Path $tmp "$lang.csv"
        [IO.File]::WriteAllLines($csv, [string[]]$lines, $utf8)
        $target = Join-Path $out "$lang.w3strings"
        $log = & $Tc.W3Strings --id-space $Cfg.Strings.IdSpace $csv $target 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0) { $log | Write-Host; throw "strings: encoding $lang.csv failed" }
    }
    Write-Host "strings: $($Cfg.Strings.Languages -join ', ')"
}

# fingerprint of everything the UI bundle is built from
function Get-StlUiStamp($Cfg, [IO.FileInfo[]]$Classes) {
    $parts = @("$($Cfg.Ui.Bundle)|$($Cfg.Ui.Swf)")
    foreach ($f in $Classes | Sort-Object FullName) { $parts += "$($f.FullName)=$((Get-FileHash $f.FullName).Hash)" }
    $parts += (Get-FileHash (Join-Path $PSScriptRoot 'cr2w_swf.py')).Hash
    $sha = [Security.Cryptography.SHA256]::Create()
    [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($parts -join "`n"))) -replace '-', ''
}

# the game's skills screen with the classes of src/ui compiled in -> blob0.bundle + metadata.store
function Build-StlUi($Cfg, $Tc, [switch]$Force) {
    $uiDir = Join-Path $Cfg.Paths.Src 'ui'
    $classes = @(Get-ChildItem $uiDir -Recurse -Filter *.as)
    $out = Get-StlContentDir $Cfg
    $bundleOut = Join-Path $out 'blob0.bundle'
    $stampFile = Join-Path $Cfg.Paths.Build 'ui.stamp'
    $stamp = Get-StlUiStamp $Cfg $classes
    if (-not $Force -and (Test-Path $bundleOut) -and (Test-Path $stampFile) -and (Get-Content $stampFile -Raw).Trim() -eq $stamp) {
        Write-Host 'ui: up to date'
        return
    }
    if (Test-StlFileLocked $bundleOut) {
        throw 'ui: the game is using the mod bundle (dist is linked into its Mods folder); quit it first'
    }
    Assert-StlTool 'REDkit wcc_lite' $Tc.Wcc
    Assert-StlTool 'FFDec' $Tc.FFDec
    Assert-StlTool 'Python' $Tc.Python

    # 1. original .redswf, extracted once from the game into work/cache
    $original = Join-Path $Cfg.Paths.Cache "$($Cfg.Ui.Bundle -replace '\.bundle$', '')\$($Cfg.Ui.Swf)"
    if (-not (Test-Path $original)) {
        $bundles = Join-Path $Cfg.Paths.Stage 'bundles\'
        $extracted = Join-Path $Cfg.Paths.Stage 'unbundled\'
        Remove-Item $bundles, $extracted -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force $bundles, $extracted | Out-Null
        Copy-Item (Join-Path $Tc.GameDir "content\content0\bundles\$($Cfg.Ui.Bundle)") $bundles
        Invoke-StlWcc $Tc @('unbundle', "-dir=$bundles", "-outdir=$extracted")
        New-Item -ItemType Directory -Force (Split-Path $original) | Out-Null
        Copy-Item (Join-Path $extracted $Cfg.Ui.Swf) $original
        Write-Host "ui: extracted $($Cfg.Ui.Swf)"
    }

    # 2. its GFx movie, with each class of src/ui recompiled by FFDec
    New-Item -ItemType Directory -Force $Cfg.Paths.Build | Out-Null
    $gfx = Join-Path $Cfg.Paths.Build 'movie.gfx'
    Invoke-StlCr2w $Tc @('extract', $original, $gfx)
    foreach ($as in $classes) {
        $class = $as.FullName.Substring($uiDir.Length + 1) -replace '\.as$', '' -replace '\\', '.'
        $next = Join-Path $Cfg.Paths.Build 'movie.next.gfx'
        Remove-Item $next -ErrorAction SilentlyContinue
        $log = & $Tc.FFDec -replace $gfx $next $class $as.FullName 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $next)) { $log | Write-Host; throw "ui: FFDec could not compile $class" }
        Move-Item $next $gfx -Force
        Write-Host "ui: compiled $class"
    }

    # 3. movie back into the .redswf (sizes and CRCs checked by the patcher), packed with wcc_lite
    $pack = Join-Path $Cfg.Paths.Stage 'pack\'
    $packed = Join-Path $Cfg.Paths.Stage 'packed\'
    Remove-Item $pack, $packed -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force (Join-Path $pack (Split-Path $Cfg.Ui.Swf)), $packed | Out-Null
    Invoke-StlCr2w $Tc @('patch', $original, $gfx, (Join-Path $pack $Cfg.Ui.Swf))
    Invoke-StlWcc $Tc @('pack', "-dir=$pack", "-outdir=$packed")
    Invoke-StlWcc $Tc @('metadatastore', "-path=$packed")
    Copy-Item (Join-Path $packed 'blob0.bundle'), (Join-Path $packed 'metadata.store') $out -Force
    # second copy that the game never opens: 'package' reads this one, so it works with the game running
    $keep = Join-Path $Cfg.Paths.Build 'ui'
    New-Item -ItemType Directory -Force $keep | Out-Null
    Copy-Item (Join-Path $packed 'blob0.bundle'), (Join-Path $packed 'metadata.store') $keep -Force
    Set-Content -Path $stampFile -Value $stamp -Encoding ASCII
    Write-Host "ui: blob0.bundle ($([math]::Round((Get-Item $bundleOut).Length / 1MB, 1)) MB)"
}

function Invoke-StlBuild($Cfg, [string]$Target, [switch]$Force) {
    $tc = Resolve-StlToolchain $Cfg
    switch ($Target) {
        'scripts' { Build-StlScripts $Cfg }
        'strings' { Build-StlStrings $Cfg $tc }
        'ui'      { Build-StlUi $Cfg $tc -Force:$Force }
        'all'     { Build-StlScripts $Cfg; Build-StlStrings $Cfg $tc; Build-StlUi $Cfg $tc -Force:$Force }
        default   { throw "unknown build target '$Target' (scripts, strings, ui, all)" }
    }
}
