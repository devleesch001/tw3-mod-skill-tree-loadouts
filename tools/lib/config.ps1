# Configuration and toolchain resolution for stl.ps1.

function Merge-StlHashtable([hashtable]$Base, [hashtable]$Over) {
    foreach ($key in $Over.Keys) {
        if ($Base[$key] -is [hashtable] -and $Over[$key] -is [hashtable]) {
            Merge-StlHashtable $Base[$key] $Over[$key]
        } else {
            $Base[$key] = $Over[$key]
        }
    }
}

# stl.config.psd1, then stl.local.psd1 merged over it, plus the derived project paths
function Get-StlConfig([string]$Root) {
    $cfg = Import-PowerShellDataFile (Join-Path $Root 'stl.config.psd1')
    $local = Join-Path $Root 'stl.local.psd1'
    $cfg.LocalFile = $null
    if (Test-Path $local) {
        Merge-StlHashtable $cfg (Import-PowerShellDataFile $local)
        $cfg.LocalFile = $local
    }
    $dist = Join-Path $Root 'dist'
    $work = Join-Path $Root 'work'
    $cfg.Paths = @{
        Root     = $Root
        Src      = Join-Path $Root 'src'
        Dist     = $dist
        ModDist  = Join-Path $dist "Mods\$($cfg.Mod.Name)"
        Work     = $work
        Cache    = Join-Path $work 'cache'       # files extracted from the game (kept by 'clean')
        Build    = Join-Path $work 'build'       # intermediates and stamps
        Release  = Join-Path $Root 'release'
        # wcc_lite does not accept spaces in its arguments: its staging lives under %TEMP%
        Stage    = Join-Path $env:TEMP 'stl-build'
    }
    $cfg
}

# Steam install folder of an app, from every Steam library; $Probe must exist inside it
function Find-SteamApp([string]$Folder, [string]$Probe) {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { return $null }
    $libs = @(Join-Path $steam 'steamapps')
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
            $libs += Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps'
        }
    }
    foreach ($lib in $libs | Select-Object -Unique) {
        $dir = Join-Path $lib "common\$Folder"
        if (Test-Path (Join-Path $dir $Probe)) { return $dir }
    }
    $null
}

# absolute tool paths ($null when not found); Source tells whether a path came from the config
function Resolve-StlToolchain($Cfg) {
    $t = $Cfg.Toolchain
    $game = $t.GameDir
    $gameSource = 'config'
    if (-not $game) { $game = Find-SteamApp 'The Witcher 3' 'bin\x64_dx12\witcher3.exe'; $gameSource = 'auto-detected' }
    $redkit = $t.REDkitDir
    $redkitSource = 'config'
    if (-not $redkit) { $redkit = Find-SteamApp 'The Witcher 3 REDkit' 'bin\x64_RedKit\wcc_lite.exe'; $redkitSource = 'auto-detected' }
    $w3s = $t.W3Strings
    if ($w3s -and -not [IO.Path]::IsPathRooted($w3s)) { $w3s = Join-Path $Cfg.Paths.Root $w3s }
    $java = Get-Command java -ErrorAction SilentlyContinue

    [pscustomobject]@{
        GameDir      = $game
        GameSource   = $gameSource
        GameExe      = if ($game) { Join-Path $game 'bin\x64_dx12\witcher3.exe' } else { $null }
        REDkitDir    = $redkit
        REDkitSource = $redkitSource
        WccDir       = if ($redkit) { Join-Path $redkit 'bin\x64_RedKit' } else { $null }
        Wcc          = if ($redkit) { Join-Path $redkit 'bin\x64_RedKit\wcc_lite.exe' } else { $null }
        FFDec        = $t.FFDec
        W3Strings    = $w3s
        Java         = if ($java) { $java.Source } else { $null }
    }
}

function Test-StlGameRunning {
    [bool](Get-Process witcher3 -ErrorAction SilentlyContinue)
}

# throws with a pointer to 'doctor' when a tool needed by a command is missing
function Assert-StlTool([string]$Name, [string]$Path) {
    if (-not $Path -or -not (Test-Path $Path)) {
        throw "$Name not found ($Path). Run '.\stl.ps1 doctor' for details."
    }
}
