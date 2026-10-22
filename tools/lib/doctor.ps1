# 'cli.ps1 doctor': checks every piece of the toolchain and the game install.

function Write-StlCheck([string]$Status, [string]$Label, [string]$Detail) {
    $color = @{ OK = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'Gray' }[$Status]
    Write-Host ('[{0,-4}] ' -f $Status) -ForegroundColor $color -NoNewline
    Write-Host ('{0,-22} {1}' -f $Label, $Detail)
}

# first line printed by a native tool (stdout or stderr)
function Get-StlToolVersion([string]$Exe, [string[]]$ToolArgs) {
    # java prints its version on stderr, which PowerShell 5.1 turns into errors under 'Stop'
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $Exe @ToolArgs 2>&1 | ForEach-Object { "$_" } | Where-Object { $_.Trim() } | Select-Object -First 1
        if ($out) { return $out.Trim() }
    } catch { }
    $null
}

function Invoke-StlDoctor($Cfg) {
    $tc = Resolve-StlToolchain $Cfg
    $fails = 0

    Write-StlCheck INFO 'PowerShell' "$($PSVersionTable.PSVersion)"
    if ($Cfg.LocalFile) { Write-StlCheck INFO 'Local config' $Cfg.LocalFile }
    else { Write-StlCheck INFO 'Local config' 'none (stl.local.psd1), using stl.config.psd1 only' }

    # game
    if ($tc.GameExe -and (Test-Path $tc.GameExe)) {
        $ver = (Get-Item $tc.GameExe).VersionInfo.ProductVersion
        Write-StlCheck OK 'Game' "$($tc.GameDir) ($($tc.GameSource), exe $ver)"
        $launcher = Join-Path $tc.GameDir 'launcher-configuration.json'
        if ((Test-Path $launcher) -and (Get-Content $launcher -Raw) -match 'remasteredEdition') {
            Write-StlCheck OK 'Game edition' 'Remastered'
        } else {
            Write-StlCheck WARN 'Game edition' 'not detected as Remastered: the mod targets the 5.x skill tree'
        }
        $strings = Join-Path $tc.GameDir 'content\content0\en.w3strings'
        if (Test-Path $strings) {
            $head = New-Object byte[] 8
            $fs = [IO.File]::OpenRead($strings); [void]$fs.Read($head, 0, 8); $fs.Close()
            $sv = [BitConverter]::ToUInt32($head, 4)
            if ($sv -eq 164) { Write-StlCheck OK 'Game strings format' 'w3strings v164 (UTF-8)' }
            else { Write-StlCheck WARN 'Game strings format' "w3strings v${sv}: the strings encoder may need other options" }
        }
        $bundle = Join-Path $tc.GameDir "content\content0\bundles\$($Cfg.Ui.Bundle)"
        if (Test-Path $bundle) { Write-StlCheck OK 'UI source bundle' $Cfg.Ui.Bundle }
        else { Write-StlCheck FAIL 'UI source bundle' "$bundle missing"; $fails++ }
        $ini = Join-Path $tc.GameDir 'bin\config\base\general.ini'
        if ((Test-Path $ini) -and (Get-Content $ini -Raw) -match 'DBGConsoleOn\s*=\s*true') {
            Write-StlCheck OK 'Debug console' 'enabled (stl_* commands available)'
        } else {
            Write-StlCheck WARN 'Debug console' 'DBGConsoleOn=true missing in bin\config\base\general.ini'
        }
    } else {
        Write-StlCheck FAIL 'Game' "witcher3.exe not found ($($tc.GameDir)): set Toolchain.GameDir in stl.local.psd1"
        $fails++
    }

    # REDkit / wcc_lite
    if ($tc.Wcc -and (Test-Path $tc.Wcc)) {
        Write-StlCheck OK 'REDkit wcc_lite' "$($tc.Wcc) ($($tc.REDkitSource))"
    } else {
        Write-StlCheck FAIL 'REDkit wcc_lite' 'not found: install "The Witcher 3 REDkit" from Steam or set Toolchain.REDkitDir'
        $fails++
    }

    # FFDec + Java
    if ($tc.FFDec -and (Test-Path $tc.FFDec)) {
        Write-StlCheck OK 'FFDec' "$($tc.FFDec) ($((Get-Item $tc.FFDec).VersionInfo.ProductVersion))"
    } else {
        Write-StlCheck FAIL 'FFDec' 'not found: winget install JPEXS.FFDec, or set Toolchain.FFDec'
        $fails++
    }
    if ($tc.Java) {
        Write-StlCheck OK 'Java (for FFDec)' "$($tc.Java) - $(Get-StlToolVersion $tc.Java @('-version'))"
    } else {
        Write-StlCheck FAIL 'Java (for FFDec)' 'java not on PATH: winget install EclipseAdoptium.Temurin.21.JRE'
        $fails++
    }

    # strings encoder
    if ($tc.W3Strings -and (Test-Path $tc.W3Strings)) {
        Write-StlCheck OK 'w3strings encoder' "$($tc.W3Strings) - $(Get-StlToolVersion $tc.W3Strings @('--version'))"
    } else {
        Write-StlCheck FAIL 'w3strings encoder' "not found ($($tc.W3Strings)): get 'w3strings Remastered' (Nexus 13094)"
        $fails++
    }

    # Python runs tools\lib\cr2w_swf.py, which puts the UI movie back into the .redswf
    if ($tc.Python -and (Test-Path $tc.Python)) {
        $pyVer = Get-StlToolVersion $tc.Python @('--version')
        if ($pyVer -match 'Python 3\.(\d+)' -and [int]$Matches[1] -ge 8) {
            Write-StlCheck OK 'Python (build only)' "$($tc.Python) - $pyVer"
        } else {
            Write-StlCheck FAIL 'Python (build only)' "${pyVer}: Python 3.8 or newer is needed"
            $fails++
        }
    } else {
        Write-StlCheck FAIL 'Python (build only)' 'python not on PATH: winget install Python.Python.3.13, or set Toolchain.Python'
        $fails++
    }

    # sources
    foreach ($lang in $Cfg.Strings.Languages) {
        $csv = Join-Path $Cfg.Paths.Src "strings\$lang.csv"
        if (-not (Test-Path $csv)) { Write-StlCheck FAIL "Strings ($lang)" "$csv missing"; $fails++; continue }
        $b = [IO.File]::ReadAllBytes($csv)
        if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
            Write-StlCheck FAIL "Strings ($lang)" 'file has a UTF-8 BOM: save it as UTF-8 without BOM'
            $fails++
        } else {
            Write-StlCheck OK "Strings ($lang)" "src\strings\$lang.csv"
        }
    }

    # deployment
    if ($tc.GameDir) {
        $link = Join-Path $tc.GameDir "Mods\$($Cfg.Mod.Name)"
        $item = Get-Item $link -ErrorAction SilentlyContinue
        if (-not $item) { Write-StlCheck WARN 'Mod link' "not linked yet: run '.\cli.ps1 link'" }
        elseif ($item.LinkType -eq 'Junction' -and $item.Target -contains $Cfg.Paths.ModDist) { Write-StlCheck OK 'Mod link' "$link -> dist" }
        elseif ($item.LinkType -eq 'Junction') { Write-StlCheck WARN 'Mod link' "points to $($item.Target): run '.\cli.ps1 link'" }
        else { Write-StlCheck FAIL 'Mod link' "$link is a real folder, not a junction: move it away"; $fails++ }
    }
    if (Test-StlGameRunning) { Write-StlCheck WARN 'Game process' 'running: the UI bundle cannot be rebuilt until it is closed' }

    Write-Host ''
    if ($fails) { Write-Host "$fails problem(s) found." -ForegroundColor Red }
    else { Write-Host 'Toolchain ready.' -ForegroundColor Green }
    $fails -eq 0
}
