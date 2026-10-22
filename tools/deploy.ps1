<#
  Deploys Skill Tree Loadouts (modSkillTreeLoadouts) to the game by linking (junction) the workspace mod folder
  into <GameDir>\Mods. Safe to run repeatedly.

    .\tools\deploy.ps1            # create/verify the junction
    .\tools\deploy.ps1 -Launch    # same, then start the game (DX12)
#>
param(
    [string]$GameDir = "B:\SteamLibrary\steamapps\common\The Witcher 3",
    [switch]$Launch
)

$ErrorActionPreference = "Stop"
$modName = "modSkillTreeLoadouts"
$source  = Join-Path (Split-Path $PSScriptRoot -Parent) $modName
$target  = Join-Path $GameDir "Mods\$modName"

if (-not (Test-Path $source)) { throw "Mod source not found: $source" }

$existing = Get-Item $target -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.LinkType -eq "Junction" -and $existing.Target -contains $source) {
        Write-Host "Junction OK: $target -> $source"
    } else {
        throw "$target already exists and is not a junction to $source. Remove it manually."
    }
} else {
    New-Item -ItemType Junction -Path $target -Target $source | Out-Null
    Write-Host "Junction created: $target -> $source"
}

if ($Launch) {
    $exe = Join-Path $GameDir "bin\x64_dx12\witcher3.exe"
    Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)
    Write-Host "Game started. Script compile errors are shown at startup."
}
