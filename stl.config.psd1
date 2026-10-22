# Skill Tree Loadouts - project configuration, read by cli.ps1 (data only, never executed).
# Machine-specific values go in stl.local.psd1 (not versioned), with the same keys: it is
# merged over this file. Leave a toolchain path empty to auto-detect it.
@{
    Mod = @{
        Name        = 'modSkillTreeLoadouts'     # folder under <GameDir>\Mods
        DisplayName = 'Skill Tree Loadouts'
        Version     = '0.1.0'
    }

    Strings = @{
        # string ids are 211<IdSpace>000..211<IdSpace>999, as in src/strings/*.csv
        IdSpace   = 7351
        Languages = @('en', 'fr')                # src/strings/<lang>.csv -> <lang>.w3strings
    }

    Ui = @{
        # the skills screen is patched from the game's own file; every class under src/ui
        # (path = AS3 package) is compiled into it
        Bundle = 'r4gui.bundle'
        Swf    = 'gameplay\gui_new\swf\character\panel_character_dupe.redswf'
    }

    Toolchain = @{
        GameDir   = ''                                        # Steam libraries if empty
        REDkitDir = ''                                        # Steam libraries if empty
        FFDec     = 'C:\Program Files (x86)\FFDec\ffdec-cli.exe'
        W3Strings = 'utils\w3stringsr.exe'                    # "w3strings Remastered", relative to the repo
        Python    = ''                                        # python on PATH if empty (build time only)
    }
}
