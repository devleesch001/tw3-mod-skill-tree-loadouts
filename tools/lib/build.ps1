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

# ---- UI: the game's skills screen with our ActionScript compiled in ----
#
# src/ui holds two kinds of files, by AS3 package path (red\game\...\Class):
#   <Class>.as.patch  our changes to a class of the game (the game's code is never versioned)
#   <Class>.as        a class entirely written for the mod, compiled as-is
# A patched class is edited as a full file in work/ui/<Class>.as (not versioned): each build
# rewrites the .patch from it, and recreates it from the game + .patch when it is missing.

# original .redswf from the game (extracted once into work/cache)
function Get-StlOriginalSwf($Cfg, $Tc) {
    $original = Join-Path $Cfg.Paths.Cache "$($Cfg.Ui.Bundle -replace '\.bundle$', '')\$($Cfg.Ui.Swf)"
    if (-not (Test-Path $original)) {
        Assert-StlTool 'REDkit wcc_lite' $Tc.Wcc
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
    $original
}

# original GFx movie of that .redswf (work/cache/ui-original/movie.gfx)
function Get-StlOriginalMovie($Cfg, $Tc, [string]$OriginalSwf) {
    $gfx = Join-Path $Cfg.Paths.Cache 'ui-original\movie.gfx'
    if (-not (Test-Path $gfx)) {
        Assert-StlTool 'Python' $Tc.Python
        New-Item -ItemType Directory -Force (Split-Path $gfx) | Out-Null
        Invoke-StlCr2w $Tc @('extract', $OriginalSwf, $gfx)
    }
    $gfx
}

function Read-StlText([string]$Path) {
    [IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding $false)) -replace "`r`n", "`n"
}

function Write-StlText([string]$Path, [string]$Text) {
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
}

# a class of the game as decompiled by FFDec, LF line endings (work/cache/ui-original/<Class>.as)
function Get-StlOriginalClass($Cfg, $Tc, [string]$Movie, [string]$Rel) {
    $cached = Join-Path $Cfg.Paths.Cache "ui-original\$Rel"
    if (-not (Test-Path $cached)) {
        Assert-StlTool 'FFDec' $Tc.FFDec
        $class = $Rel -replace '\.as$', '' -replace '\\', '.'
        $tmp = Join-Path $Cfg.Paths.Stage 'export\'
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        $log = & $Tc.FFDec -selectclass $class -export script $tmp $Movie 2>&1 | ForEach-Object { "$_" }
        $exported = Join-Path $tmp "scripts\$Rel"
        if (-not (Test-Path $exported)) { $log | Write-Host; throw "ui: class $class not found in the game's movie" }
        Write-StlText $cached (Read-StlText $exported)
    }
    $cached
}

# git does the diff and the patch, outside any repository (under %TEMP%)
function New-StlPatch($Cfg, [string]$Rel, [string]$Original, [string]$Edited) {
    $tmp = Join-Path $Cfg.Paths.Stage 'diff'
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    $relUnix = $Rel -replace '\\', '/'
    Write-StlText (Join-Path $tmp "a\$Rel") (Read-StlText $Original)
    Write-StlText (Join-Path $tmp "b\$Rel") (Read-StlText $Edited)
    Push-Location $tmp
    try {
        $diff = & git -c core.autocrlf=false diff --no-index --no-prefix --text --no-color -- "a/$relUnix" "b/$relUnix" 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -gt 1) { $diff | Write-Host; throw "ui: git diff failed for $Rel" }
    } finally { Pop-Location }
    if (-not $diff) { return '' }
    ($diff -join "`n") + "`n"
}

function Invoke-StlApplyPatch($Cfg, [string]$Rel, [string]$Original, [string]$Patch, [string]$Target) {
    $tmp = Join-Path $Cfg.Paths.Stage 'apply'
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-StlText (Join-Path $tmp $Rel) (Read-StlText $Original)
    Push-Location $tmp
    try {
        # the patch names the file a/<Rel> and b/<Rel>: -p1 drops that first component
        $log = & git -c core.autocrlf=false apply --whitespace=nowarn -p1 $Patch 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0) {
            $log | Write-Host
            throw "ui: $Rel.patch does not apply to the game's current class (game update?)"
        }
    } finally { Pop-Location }
    Write-StlText $Target (Read-StlText (Join-Path $tmp $Rel))
}

# editable full files in work/ui <-> versioned patches in src/ui; returns the files to compile
function Sync-StlUiSources($Cfg, $Tc, [string]$Movie) {
    $uiDir = Join-Path $Cfg.Paths.Src 'ui'
    $editDir = Join-Path $Cfg.Paths.Work 'ui'
    $files = @()
    foreach ($p in Get-ChildItem $uiDir -Recurse -Filter *.as.patch) {
        $rel = $p.FullName.Substring($uiDir.Length + 1) -replace '\.patch$', ''
        $original = Get-StlOriginalClass $Cfg $Tc $Movie $rel
        $edited = Join-Path $editDir $rel
        if (Test-Path $edited) {
            $patch = New-StlPatch $Cfg $rel $original $edited
            if ($patch -ne (Read-StlText $p.FullName)) {
                Write-StlText $p.FullName $patch
                Write-Host "ui: src\ui\$rel.patch updated from work\ui\$rel"
            }
        } else {
            Invoke-StlApplyPatch $Cfg $rel $original $p.FullName $edited
            Write-Host "ui: work\ui\$rel created from the game + patch"
        }
        $files += [pscustomobject]@{ Rel = $rel; Path = $edited }
    }
    foreach ($as in Get-ChildItem $uiDir -Recurse -Filter *.as) {
        $files += [pscustomobject]@{ Rel = $as.FullName.Substring($uiDir.Length + 1); Path = $as.FullName }
    }
    $files
}

# fingerprint of everything the UI bundle is built from
function Get-StlUiStamp($Cfg, $Files) {
    $parts = @("$($Cfg.Ui.Bundle)|$($Cfg.Ui.Swf)")
    foreach ($f in $Files | Sort-Object Rel) { $parts += "$($f.Rel)=$((Get-FileHash $f.Path).Hash)" }
    $parts += (Get-FileHash (Join-Path $PSScriptRoot 'cr2w_swf.py')).Hash
    $sha = [Security.Cryptography.SHA256]::Create()
    [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($parts -join "`n"))) -replace '-', ''
}

# -> blob0.bundle + metadata.store
function Build-StlUi($Cfg, $Tc, [switch]$Force) {
    $out = Get-StlContentDir $Cfg
    $bundleOut = Join-Path $out 'blob0.bundle'
    $stampFile = Join-Path $Cfg.Paths.Build 'ui.stamp'

    $originalSwf = Get-StlOriginalSwf $Cfg $Tc
    $movie = Get-StlOriginalMovie $Cfg $Tc $originalSwf
    $files = @(Sync-StlUiSources $Cfg $Tc $movie)
    $stamp = Get-StlUiStamp $Cfg $files
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

    # the original movie with each class recompiled by FFDec
    New-Item -ItemType Directory -Force $Cfg.Paths.Build | Out-Null
    $gfx = Join-Path $Cfg.Paths.Build 'movie.gfx'
    Copy-Item $movie $gfx -Force
    foreach ($f in $files) {
        $class = $f.Rel -replace '\.as$', '' -replace '\\', '.'
        $next = Join-Path $Cfg.Paths.Build 'movie.next.gfx'
        Remove-Item $next -ErrorAction SilentlyContinue
        $log = & $Tc.FFDec -replace $gfx $next $class $f.Path 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $next)) { $log | Write-Host; throw "ui: FFDec could not compile $class" }
        Move-Item $next $gfx -Force
        Write-Host "ui: compiled $class"
    }

    # movie back into the .redswf (sizes and CRCs checked by the patcher), packed with wcc_lite
    $pack = Join-Path $Cfg.Paths.Stage 'pack\'
    $packed = Join-Path $Cfg.Paths.Stage 'packed\'
    Remove-Item $pack, $packed -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force (Join-Path $pack (Split-Path $Cfg.Ui.Swf)), $packed | Out-Null
    Invoke-StlCr2w $Tc @('patch', $originalSwf, $gfx, (Join-Path $pack $Cfg.Ui.Swf))
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
