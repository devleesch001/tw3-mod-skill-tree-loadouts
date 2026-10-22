<#
  Builds the skills-screen UI bundle (modSkillTreeLoadouts\content\blob0.bundle + metadata.store).

  1. extracts panel_character_dupe.redswf from the game's r4gui.bundle (once, into work\)
  2. takes its GFx movie and recompiles every class found under ui\scripts\ with FFDec
     (ui\scripts\red\game\...\MenuCharacterDupe.as -> red.game....MenuCharacterDupe)
  3. puts the GFx back into the .redswf (tools\cr2w_swf.py) and packs it with wcc_lite

    .\tools\build-ui.ps1
#>
param(
    [string]$GameDir   = "B:\SteamLibrary\steamapps\common\The Witcher 3",
    [string]$REDkitDir = "B:\SteamLibrary\steamapps\common\The Witcher 3 REDkit",
    [string]$FFDec     = "C:\Program Files (x86)\FFDec\ffdec-cli.exe"
)

$ErrorActionPreference = "Stop"
$root    = Split-Path $PSScriptRoot -Parent
$work    = Join-Path $root "work"
$uiDir   = Join-Path $root "ui\scripts"
$modDir  = Join-Path $root "modSkillTreeLoadouts\content"
$swfPath = "gameplay\gui_new\swf\character\panel_character_dupe.redswf"
$wccDir  = Join-Path $REDkitDir "bin\x64_RedKit"
# wcc_lite does not handle spaces in its arguments: stage under %TEMP%
$tmp     = Join-Path $env:TEMP "stl-ui"

function Invoke-Wcc([string[]]$wccArgs) {
    Push-Location $wccDir   # wcc_lite finds gameconf.cfg relative to the current folder
    try {
        $log = & .\wcc_lite.exe @wccArgs 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0) { $log | Select-Object -Last 20 | Write-Host; throw "wcc_lite $($wccArgs[0]) failed" }
        $log | Select-String '\]\[WCC\]' | Select-Object -Last 3 | ForEach-Object { $_.Line -replace '^\[[^\]]+\]', '' }
    } finally { Pop-Location }
}

# 1. original .redswf from the game
$original = Join-Path $work "r4gui\$swfPath"
if (-not (Test-Path $original)) {
    $bundles = Join-Path $tmp "r4gui-bundle\"
    New-Item -ItemType Directory -Force $bundles | Out-Null
    Copy-Item (Join-Path $GameDir "content\content0\bundles\r4gui.bundle") $bundles -Force
    Invoke-Wcc @("unbundle", "-dir=$bundles", "-outdir=$tmp\r4gui\")
    New-Item -ItemType Directory -Force (Split-Path $original) | Out-Null
    Copy-Item (Join-Path $tmp "r4gui\$swfPath") $original -Force
}

# 2. GFx movie with our classes compiled in
New-Item -ItemType Directory -Force $tmp | Out-Null
$gfx = Join-Path $tmp "movie.gfx"
python -I (Join-Path $PSScriptRoot "cr2w_swf.py") extract $original $gfx
if ($LASTEXITCODE -ne 0) { throw "gfx extraction failed" }
if (Test-Path $uiDir) {
    foreach ($as in Get-ChildItem $uiDir -Recurse -Filter *.as) {
        $class = $as.FullName.Substring($uiDir.Length + 1) -replace '\.as$', '' -replace '\\', '.'
        $next = Join-Path $tmp "movie.next.gfx"
        & $FFDec -replace $gfx $next $class $as.FullName 2>&1 | Where-Object { $_ -notmatch 'EXPERIMENTAL' }
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $next)) { throw "FFDec failed on $class" }
        Move-Item $next $gfx -Force
        Write-Host "compiled $class"
    }
}

# 3. .redswf -> bundle
$stage  = Join-Path $tmp "pack\"
$bundle = Join-Path $tmp "bundle\"
Remove-Item $stage, $bundle -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Join-Path $stage (Split-Path $swfPath)), $bundle | Out-Null
python -I (Join-Path $PSScriptRoot "cr2w_swf.py") patch $original $gfx (Join-Path $stage $swfPath)
if ($LASTEXITCODE -ne 0) { throw "redswf patch failed" }
Invoke-Wcc @("pack", "-dir=$stage", "-outdir=$bundle")
Invoke-Wcc @("metadatastore", "-path=$bundle")
if (Get-Process witcher3 -ErrorAction SilentlyContinue) {
    throw "The game is running and locks the mod bundle: quit it, then run this script again (built bundle kept in $bundle)"
}
Copy-Item (Join-Path $bundle "blob0.bundle"), (Join-Path $bundle "metadata.store") $modDir -Force
Write-Host "UI bundle written to $modDir"
