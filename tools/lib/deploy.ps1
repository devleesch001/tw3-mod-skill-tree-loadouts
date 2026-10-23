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
        if ($item.Target -contains $Cfg.Paths.ModDist) {
            Write-Host "link: $link -> dist (ok)"
            Install-StlOptions $Cfg $tc
            return
        }
        cmd /c rmdir "$link"    # removes the junction only, never its target
    }
    New-Item -ItemType Junction -Path $link -Target $Cfg.Paths.ModDist | Out-Null
    Write-Host "link: $link -> $($Cfg.Paths.ModDist)"
    Install-StlOptions $Cfg $tc
}

# The options file lives in the game's bin folder, outside Mods: it is copied there (a junction
# cannot point at a file, and dist is on another drive than the game for a hard link).
function Install-StlOptions($Cfg, $Tc) {
    $target = Join-Path $Tc.GameDir "$($Cfg.Options.Dir)\$($Cfg.Options.File)"
    if (-not (Test-Path $Cfg.Paths.OptionsDist)) { Write-Host "link: no options file in dist yet, run '.\cli.ps1 build scripts'"; return }
    if ((Test-Path $target) -and (Get-FileHash $target).Hash -eq (Get-FileHash $Cfg.Paths.OptionsDist).Hash) {
        Write-Host "link: options $target (ok)"
        return
    }
    Copy-Item $Cfg.Paths.OptionsDist $target -Force
    Write-Host "link: options copied to $target (the game reads it at startup)"
}

function Remove-StlLink($Cfg) {
    $tc = Resolve-StlToolchain $Cfg
    $link = Join-Path $tc.GameDir "Mods\$($Cfg.Mod.Name)"
    $item = Get-Item $link -ErrorAction SilentlyContinue
    if (-not $item) { Write-Host 'unlink: no mod link' }
    elseif ($item.LinkType -ne 'Junction') { throw "$link is a real folder, not a junction: left untouched" }
    else { cmd /c rmdir "$link"; Write-Host "unlink: $link removed" }
    # the options file only when it is the one 'link' copied
    $target = Join-Path $tc.GameDir "$($Cfg.Options.Dir)\$($Cfg.Options.File)"
    if (-not (Test-Path $target)) { return }
    if ((Test-Path $Cfg.Paths.OptionsDist) -and (Get-FileHash $target).Hash -eq (Get-FileHash $Cfg.Paths.OptionsDist).Hash) {
        Remove-Item $target
        Write-Host "unlink: $target removed"
    } else {
        Write-Host "unlink: $target differs from dist, left untouched" -ForegroundColor Yellow
    }
}

function Start-StlGame($Cfg) {
    $tc = Resolve-StlToolchain $Cfg
    if (Test-StlGameRunning) { throw 'the game is already running' }
    Start-Process -FilePath $tc.GameExe -WorkingDirectory (Split-Path $tc.GameExe)
    Write-Host 'run: game started (script compile errors are shown at startup)'
}

# file:line that sets Mod.Version (stl.local.psd1 wins over stl.config.psd1, as in Get-StlConfig)
function Get-StlVersionSource($Cfg) {
    foreach ($file in $Cfg.LocalFile, (Join-Path $Cfg.Paths.Root 'stl.config.psd1')) {
        if (-not $file -or -not (Test-Path $file)) { continue }
        $hit = Select-String -Path $file -Pattern '^\s*Version\s*=' | Select-Object -First 1
        if ($hit) { return "$(Split-Path $file -Leaf):$($hit.LineNumber)" }
    }
    'stl.config.psd1 (Mod.Version)'
}

# version tags (vX.Y.Z) on the current commit
function Get-StlHeadTags($Cfg) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return @() }
    $ErrorActionPreference = 'Continue'
    @(& git -C $Cfg.Paths.Root tag --points-at HEAD 2>$null | Where-Object { $_ -match '^v\d' })
}

# which version the zip gets, where it is set, and whether the git tag agrees
function Show-StlVersionInfo($Cfg, [string]$Zip) {
    $version = $Cfg.Mod.Version
    $source = Get-StlVersionSource $Cfg
    $tags = Get-StlHeadTags $Cfg
    Write-Host "  version used : $version  (set in $source)"
    Write-Host "  git tag      : $(if ($tags) { $tags -join ', ' } else { 'none on the current commit' })"
    if ($tags -and $tags -notcontains "v$version") {
        Write-Host "  mismatch     : the commit is tagged $($tags -join ', ') but the version is $version" -ForegroundColor Yellow
    }
    if ($Zip -and (Test-Path $Zip)) {
        Write-Host "  existing zip : $Zip ($((Get-Item $Zip).LastWriteTime))"
    }
    Write-Host "  new version  : change Version in $source, then run '.\cli.ps1 package' again"
}

# zip of dist/, laid out like the game folder: extract it into <GameDir>.
# The running game keeps dist's bundle open, so the bundle files come from the copy that
# 'build ui' keeps in work/build/ui. An existing zip of the same version is only replaced with -Force.
function New-StlPackage($Cfg, [switch]$Force) {
    $zip = Join-Path $Cfg.Paths.Release ("{0}-{1}.zip" -f ($Cfg.Mod.DisplayName -replace '\s', ''), $Cfg.Mod.Version)
    if ((Test-Path $zip) -and -not $Force) {
        Write-Host "package: $(Split-Path $zip -Leaf) already exists" -ForegroundColor Yellow
        Show-StlVersionInfo $Cfg $zip
        throw "package: zip left untouched; use -Force to replace it"
    }
    $tags = Get-StlHeadTags $Cfg
    if ($tags -and $tags -notcontains "v$($Cfg.Mod.Version)") {
        Write-Host "package: the git tag does not match the version" -ForegroundColor Yellow
        Show-StlVersionInfo $Cfg $null
    }
    $content = Join-Path $Cfg.Paths.ModDist 'content'
    $keep = Join-Path $Cfg.Paths.Build 'ui'
    foreach ($f in 'scripts\local', 'en.w3strings') {
        if (-not (Test-Path (Join-Path $content $f))) { throw "package: dist is incomplete ($f), run '.\cli.ps1 build' first" }
    }
    foreach ($f in 'blob0.bundle', 'metadata.store') {
        if (-not (Test-Path (Join-Path $keep $f))) { throw "package: no built UI bundle in work\build\ui, run '.\cli.ps1 build ui -Force' (game closed) once" }
    }
    # the strings and the UI bundle must have been built from the sources as they are now
    $tc = Resolve-StlToolchain $Cfg
    $checks = @(
        @{ What = 'strings'; Stamp = 'strings.stamp'; Now = (Get-StlStringsStamp $Cfg); Fix = "'.\cli.ps1 build strings'" },
        @{ What = 'UI'; Stamp = 'ui.stamp'; Now = (Get-StlCurrentUiStamp $Cfg $tc); Fix = "'.\cli.ps1 build ui' (game closed)" }
    )
    foreach ($c in $checks) {
        $file = Join-Path $Cfg.Paths.Build $c.Stamp
        if (-not (Test-Path $file) -or (Get-Content $file -Raw).Trim() -ne $c.Now) {
            throw "package: the $($c.What) sources changed since the last build, run $($c.Fix) first"
        }
    }
    # scripts and options file in dist must be the ones of src, unchanged
    $expected = @(@(Get-StlScriptFiles $Cfg) + @(Get-Item $Cfg.Paths.OptionsSrc) | ForEach-Object { "$($_.Name)=$((Get-FileHash $_.FullName).Hash)" } | Sort-Object)
    $actual = @(@(Get-ChildItem (Join-Path $content 'scripts\local') -Filter *.ws) + @(Get-Item $Cfg.Paths.OptionsDist -ErrorAction SilentlyContinue) | ForEach-Object { "$($_.Name)=$((Get-FileHash $_.FullName).Hash)" } | Sort-Object)
    if (Compare-Object $expected $actual) {
        throw "package: the scripts or options file in dist differ from src, run '.\cli.ps1 build scripts' first"
    }
    Test-StlScripts $Cfg $tc
    # the player README and the license ship inside the mod folder, as other mods do
    Copy-Item (Join-Path $Cfg.Paths.Src 'release\README.md') (Join-Path $Cfg.Paths.ModDist 'README.md') -Force
    foreach ($f in 'LICENSE', 'LICENSE-EXCEPTION') {
        Copy-Item (Join-Path $Cfg.Paths.Root $f) (Join-Path $Cfg.Paths.ModDist $f) -Force
    }
    New-Item -ItemType Directory -Force $Cfg.Paths.Release | Out-Null
    Remove-Item $zip -ErrorAction SilentlyContinue
    # entries use '/' as the zip format requires (Compress-Archive in PowerShell 5.1 writes '\',
    # which some extractors turn into flat file names)
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    # only what build and package put in dist: dist is linked into the game's Mods folder, so
    # other tools (Vortex backups, ...) can drop files there
    $modDir = [regex]::Escape("Mods/$($Cfg.Mod.Name)")
    $optionsRel = "$($Cfg.Options.Dir)\$($Cfg.Options.File)" -replace '\\', '/'
    $options = [regex]::Escape($optionsRel)
    $shipped = "^($modDir/(README\.md|LICENSE|LICENSE-EXCEPTION|content/(blob0\.bundle|metadata\.store|[a-z]+\.w3strings|scripts/local/[^/]+\.ws))|$options)$"
    $files = @()
    $skipped = @()
    foreach ($file in Get-ChildItem $Cfg.Paths.Dist -Recurse -File) {
        $rel = $file.FullName.Substring($Cfg.Paths.Dist.Length + 1) -replace '\\', '/'
        if ($rel -match $shipped) { $files += $file } else { $skipped += $rel }
    }
    if ($skipped) {
        Write-Host "package: $($skipped.Count) file(s) in dist not built by the CLI, left out of the zip:" -ForegroundColor Yellow
        $skipped | ForEach-Object { Write-Host "  $_" }
    }
    $archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $files) {
            $entry = $file.FullName.Substring($Cfg.Paths.Dist.Length + 1) -replace '\\', '/'
            $source = $file.FullName
            if ($file.DirectoryName -eq $content -and $file.Name -in 'blob0.bundle', 'metadata.store') {
                $source = Join-Path $keep $file.Name
            }
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $source, $entry, [IO.Compression.CompressionLevel]::Optimal)
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
