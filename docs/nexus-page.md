# Nexus Mods page — draft

Fields to fill when creating the mod page, then the description to paste (BBCode).

| Field | Value |
|---|---|
| Name | Skill Tree Loadouts |
| Version | 1.1.1 (1.0.0: English and French only) |
| Category | Gameplay / Skills (or Utilities) |
| Summary (short) | Save your whole skill tree, slots, mutagens and mutation as a loadout and switch builds in one click, with your own skill points only. |
| Tags | Remastered Compatible, Skills, Gameplay, User Interface |
| Requirements | none (game version 5.x Remastered) |
| File | `release/SkillTreeLoadouts-<version>.zip` (built by `.\cli.ps1 package`) |
| Changelog 1.1.0 | All 18 game languages; button labels shrink to fit long texts and names. |
| Changelog 1.1.1 | The loadout bar sits under the slot grid in use, so it no longer overlaps the mutation slots. |

Nexus mod id: **14755** (page https://www.nexusmods.com/witcher3/mods/14755). It is also the
text id space (`Strings.IdSpace` in `stl.config.psd1`), so the mod's string ids
(2114755000-2114755999) cannot collide with another mod's.

Images to add: the skills screen with the bar, the confirmation popup, a renamed loadout,
the "loaded" notification.

---

```
[size=5][b]Skill Tree Loadouts[/b][/size]

Save your [b]whole skill tree[/b] as a loadout and switch builds in one click, using only the skill points you have earned. No Potion of Clearance, no console cheats.

Other preset mods only remember the skills in the equipped slots. Skill Tree Loadouts also remembers [b]every skill bought in the tree and its level[/b], so a signs build and a sword build can use completely different trees.

[size=4][b]Features[/b][/size]
[list]
[*]5 loadouts per save, stored in your save file
[*]A loadout keeps the full tree (skills + levels), the equipped slots, the skill mutagens and the Blood and Wine mutation
[*]Loading refunds the tree and buys it back with [b]your own points[/b], following the game's unlock rules
[*][b]Undo[/b] brings back the build you had before the last load or reset
[*][b]Reset[/b] refunds the whole tree without a Potion of Clearance
[*]Rename your loadouts directly in the skills screen
[*]The game's own confirmation popup before anything changes your tree
[*]Translated into every language of the game (English and French proofread, corrections welcome for the others)
[*]No Script Merger needed: annotations only, no game script is replaced
[/list]

[size=4][b]How to use[/b][/size]
A bar appears under the equipped skills in the skills screen:
[list]
[*][b]Click[/b] a loadout: load it (after a confirmation)
[*][b]Hold[/b] a loadout for one second: save your current build into it
[*][b]Right click[/b] a loadout: rename it (Enter to keep, Esc to cancel)
[*][b]Reset[/b] / [b]Undo[/b]: refund the tree / go back to the previous build
[/list]
If something cannot be restored (not enough points, a missing mutagen...), a notification tells you what. Loading is blocked during combat.

Console commands are also available with the debug console: [font=Courier New]stl_save(1)[/font], [font=Courier New]stl_load(1)[/font], [font=Courier New]stl_reset()[/font], [font=Courier New]stl_undo()[/font], [font=Courier New]stl_info(1)[/font], [font=Courier New]stl_name(1, "Signs")[/font].

[size=4][b]Requirements[/b][/size]
The Witcher 3: Wild Hunt [b]Remastered (5.x)[/b], new skill tree (default option).

[size=4][b]Installation[/b][/size]
Install with Vortex, or extract the archive into the game folder (the one with [i]bin[/i], [i]content[/i] and [i]Mods[/i]). Works on new games and existing saves.

[size=4][b]Compatibility[/b][/size]
[list]
[*][b]Incompatible[/b] with mods that replace the skills screen ([i]panel_character_dupe.redswf[/i]), such as [i]Skill Slots Presets[/i]: only one of them can be shown. Loadouts still work from the console.
[*]The legacy skill tree option does not show the bar yet.
[*]Mouse and keyboard only for the bar (no gamepad yet).
[*]Mods that heavily change the skill rules may prevent a loadout from being rebuilt in full. The mod never spends points the game would not let you spend.
[/list]

[size=4][b]Uninstallation[/b][/size]
Delete [i]Mods\modSkillTreeLoadouts[/i]. Loadouts are stored in your saves and ignored without the mod; your current build stays as it is.

[size=4][b]Credits[/b][/size]
The Witcher 3 belongs to CD PROJEKT RED. Built with the official REDkit tools, JPEXS FFDec and the "w3strings Remastered" encoder.
```
