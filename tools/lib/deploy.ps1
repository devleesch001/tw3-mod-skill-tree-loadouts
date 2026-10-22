# 'cli.ps1 link / unlink / run / package / clean'

# <GameDir>\Mods\<mod> -> dist\Mods\<mod> (junction: the game reads dist directly)
function Set-StlLink($Cfg) {
    $tc = Resolve-StlToolchain $Cfg
    Assert-StlTool 'Game' $tc.GameExe
    New-Item -ItemType Directory -Force $Cfg.Paths.ModDist | Out-Null
    $link = Join-Path $tc.GameDir "Mods\$($Cfg.Mod.Name)"
    $item = Get-Item $link -ErrorAction SilentlyContinue
    if ($item) {
        if ($item.LinkType -ne 'Junction') { throw "$link is a real folder, not a junction: move it away first" }
        if ($item.Target -contains $Cfg.Paths.ModDist) { Write-Host "link: $link -> dist (ok)"; return }
        cmd /c rmdir "$link"    # removes the junction only, never its target
    }
    New-Item -ItemType Junction -Path $link -Target $Cfg.Paths.ModDist | Out-Null
    Write-Host "link: $link -> $($Cfg.Paths.ModDist)"
}

function Remove-StlLink($Cfg) {
    $tc = Resolve-StlToolchain $Cfg
    $link = Join-Path $tc.GameDir "Mods\$($Cfg.Mod.Name)"
    $item = Get-Item $link -ErrorAction SilentlyContinue
    if (-not $item) { Write-Host 'unlink: nothing to remove'; return }
    if ($item.LinkType -ne 'Junction') { throw "$link is a real folder, not a junction: left untouched" }
    cmd /c rmdir "$link"
    Write-Host "unlink: $link removed"
}

function Start-StlGame($Cfg) {
    $tc = Resolve-StlToolchain $Cfg
    if (Test-StlGameRunning) { throw 'the game is already running' }
    Start-Process -FilePath $tc.GameExe -WorkingDirectory (Split-Path $tc.GameExe)
    Write-Host 'run: game started (script compile errors are shown at startup)'
}

# zip of dist/, laid out like the game folder: extract it into <GameDir>
function New-StlPackage($Cfg) {
    if (Test-StlGameRunning) { throw 'package: the game is running and locks the mod bundle; quit it first' }
    $content = Join-Path $Cfg.Paths.ModDist 'content'
    foreach ($f in 'scripts\local', 'blob0.bundle', 'metadata.store') {
        if (-not (Test-Path (Join-Path $content $f))) { throw "package: dist is incomplete ($f), run '.\cli.ps1 build' first" }
    }
    # the player README ships inside the mod folder, as other mods do
    Copy-Item (Join-Path $Cfg.Paths.Src 'release\README.md') (Join-Path $Cfg.Paths.ModDist 'README.md') -Force
    New-Item -ItemType Directory -Force $Cfg.Paths.Release | Out-Null
    $zip = Join-Path $Cfg.Paths.Release ("{0}-{1}.zip" -f ($Cfg.Mod.DisplayName -replace '\s', ''), $Cfg.Mod.Version)
    Remove-Item $zip -ErrorAction SilentlyContinue
    # entries use '/' as the zip format requires (Compress-Archive in PowerShell 5.1 writes '\',
    # which some extractors turn into flat file names)
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in Get-ChildItem $Cfg.Paths.Dist -Recurse -File) {
            $entry = $file.FullName.Substring($Cfg.Paths.Dist.Length + 1) -replace '\\', '/'
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $entry, [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally {
        $archive.Dispose()
    }
    Write-Host "package: $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"
}

# dist/ and build intermediates; -All also drops the files extracted from the game
function Clear-StlOutputs($Cfg, [switch]$All) {
    $targets = @($Cfg.Paths.Dist, $Cfg.Paths.Build, $Cfg.Paths.Stage)
    if ($All) { $targets += $Cfg.Paths.Cache }
    foreach ($t in $targets) {
        if (Test-Path $t) { Remove-Item $t -Recurse -Force; Write-Host "clean: $t" }
    }
}
