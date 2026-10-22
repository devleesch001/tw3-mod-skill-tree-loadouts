<#
  Encodes strings\<lang>.csv into modSkillTreeLoadouts\content\<lang>.w3strings
  with the w3strings encoder (utils\w3strings encoder\w3strings.exe).

    .\tools\build-strings.ps1
#>
param(
    # 4-digit id space: string ids are 211<IdSpace>000..999 (must match the csv files)
    [int]$IdSpace = 7351
)

$ErrorActionPreference = "Stop"
$root    = Split-Path $PSScriptRoot -Parent
$encoder = Join-Path $root "utils\w3strings encoder\w3strings.exe"
$csvDir  = Join-Path $root "strings"
$outDir  = Join-Path $root "modSkillTreeLoadouts\content"
$tmpDir  = Join-Path $env:TEMP "stl-strings"

if (-not (Test-Path $encoder)) { throw "w3strings encoder not found: $encoder" }
New-Item -ItemType Directory -Force $tmpDir | Out-Null

foreach ($csv in Get-ChildItem $csvDir -Filter *.csv) {
    $lang = $csv.BaseName
    # the encoder writes next to its input, so work on a copy outside the repo
    $work = Join-Path $tmpDir $csv.Name
    Copy-Item $csv.FullName $work -Force
    & $encoder --encode $work --id-space $IdSpace
    if ($LASTEXITCODE -ne 0) { throw "encoding failed for $($csv.Name)" }
    Copy-Item "$work.w3strings" (Join-Path $outDir "$lang.w3strings") -Force
    Write-Host "$lang.w3strings built"
}
