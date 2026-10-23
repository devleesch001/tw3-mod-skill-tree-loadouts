<#
.SYNOPSIS
  Skill Tree Loadouts - development CLI (build, deploy, package, toolchain checks).

.DESCRIPTION
  .\cli.ps1 doctor             check the toolchain and the game install
  .\cli.ps1 build [target]     build src/ into dist/  (target: all, scripts, strings, ui)
  .\cli.ps1 check              compile the scripts with the game's, as at game start (REDkit wcc_lite)
  .\cli.ps1 link               junction <GameDir>\Mods\<mod> -> dist\Mods\<mod>
  .\cli.ps1 unlink             remove that junction
  .\cli.ps1 run                build all + link + start the game
  .\cli.ps1 package            zip dist/ into release/ (extract into the game folder)
  .\cli.ps1 clean              delete dist/ and build intermediates (-All: also the game files cache)
  .\cli.ps1 help

  -Force    build: rebuild the UI bundle even if its sources did not change
            package: replace the zip of this version if it already exists
  -NoBuild  'run' only links and starts the game

  Settings: stl.config.psd1 (versioned) and stl.local.psd1 (this machine, optional).
#>
param(
    [Parameter(Position = 0)][string]$Command = 'help',
    [Parameter(Position = 1)][string]$Target = 'all',
    [switch]$Force,
    [switch]$NoBuild,
    [switch]$All
)

$ErrorActionPreference = 'Stop'
foreach ($lib in 'config', 'doctor', 'build', 'deploy') {
    . (Join-Path $PSScriptRoot "tools\lib\$lib.ps1")
}

try {
    $cfg = Get-StlConfig $PSScriptRoot
    switch ($Command) {
        'doctor'  { if (-not (Invoke-StlDoctor $cfg)) { exit 1 } }
        'build'   { Invoke-StlBuild $cfg $Target -Force:$Force }
        'check'   { Test-StlScripts $cfg (Resolve-StlToolchain $cfg) }
        'link'    { Set-StlLink $cfg }
        'unlink'  { Remove-StlLink $cfg }
        'run'     {
            if (-not $NoBuild) { Invoke-StlBuild $cfg 'all' -Force:$Force }
            Set-StlLink $cfg
            Start-StlGame $cfg
        }
        'package' { New-StlPackage $cfg -Force:$Force }
        'clean'   {
            if (Test-StlFileLocked (Join-Path $cfg.Paths.ModDist 'content\blob0.bundle')) { throw 'clean: the game is using dist/; quit it first' }
            Clear-StlOutputs $cfg -All:$All
        }
        'help'    {
            $h = Get-Help $PSCommandPath
            Write-Host $h.Synopsis
            Write-Host ''
            Write-Host (($h.description | ForEach-Object Text) -join "`n")
        }
        default   { throw "unknown command '$Command' (try: .\cli.ps1 help)" }
    }
} catch {
    Write-Host "error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
# success: never pass on the last native tool's code (git diff --no-index exits 1 on differences)
exit 0
