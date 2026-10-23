# Skill Tree Loadouts - project configuration, read by cli.ps1 (data only, never executed).
# Machine-specific values go in stl.local.psd1 (not versioned), with the same keys: it is
# merged over this file. Leave a toolchain path empty to auto-detect it.
@{
    Mod = @{
        Name        = 'modSkillTreeLoadouts'     # folder under <GameDir>\Mods
        DisplayName = 'Skill Tree Loadouts'
        Version     = '1.2.0'
    }

    # the mod's options in the game's Options menu: src/config/<File>, installed as
    # <GameDir>\<Dir>\<File> (the game reads every .xml of that folder)
    Options = @{
        Dir  = 'bin\config\r4game\user_config_matrix\pc'
        File = 'modSkillTreeLoadouts.xml'
    }

    Strings = @{
        # string ids are 21<IdSpace>NNN (4 digits: 211nnnnNNN, 5 digits: 21nnnnnNNN), as in
        # src/strings/*.csv. Use the Nexus mod id once the mod page exists.
        IdSpace   = 14755                        # Nexus mod id
        # every language of the game; src/strings/<lang>.csv -> <lang>.w3strings
        # (en is the reference: the others must have the same keys and $n$ markers)
        Languages = @('en', 'fr', 'de', 'it', 'es', 'esmx', 'br', 'pl', 'cz', 'hu', 'ru', 'ua', 'tr', 'jp', 'kr', 'zh', 'cn', 'ar')
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
