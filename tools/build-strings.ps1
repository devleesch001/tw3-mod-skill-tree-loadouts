<#
  Encodes strings\<lang>.csv into modSkillTreeLoadouts\content\<lang>.w3strings
  with "w3strings Remastered" (utils\w3stringsr.exe, Nexus 13094). Remastered (5.0) reads
  only the v164 UTF-8 format, which is that encoder's default; rmemr's encoder writes v162
  and shows garbled text in game.

    .\tools\build-strings.ps1
#>
param(
    # 4-digit id space: string ids are 211<IdSpace>000..999 (must match the csv files)
    [int]$IdSpace = 7351
)

$ErrorActionPreference = "Stop"
$root    = Split-Path $PSScriptRoot -Parent
$encoder = Join-Path $root "utils\w3stringsr.exe"
$csvDir  = Join-Path $root "strings"
$outDir  = Join-Path $root "modSkillTreeLoadouts\content"

if (-not (Test-Path $encoder)) { throw "w3strings Remastered encoder not found: $encoder" }

foreach ($csv in Get-ChildItem $csvDir -Filter *.csv) {
    $out = Join-Path $outDir "$($csv.BaseName).w3strings"
    & $encoder --id-space $IdSpace $csv.FullName $out
    if ($LASTEXITCODE -ne 0) { throw "encoding failed for $($csv.Name)" }
    Write-Host "$($csv.BaseName).w3strings built"
}
