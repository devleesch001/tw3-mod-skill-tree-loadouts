# Skill Tree Loadouts

Save your **whole skill tree** as a loadout and switch builds in one click, using only the
skill points you have earned. No Potion of Clearance, no `addskillpoints`.

Other preset mods only remember the skills in the equipped slots. Skill Tree Loadouts also
remembers every skill bought in the tree (and its level), so a signs build and a sword build
can use completely different trees.

## Requirements

- The Witcher 3: Wild Hunt **Remastered (5.x)**, with the new skill tree (default).
- No Script Merger needed: the scripts only use annotations, no game file is replaced.

## Installation

Extract the archive into the game folder (the one that contains `bin`, `content` and `Mods`),
or install it with Vortex. You should get:

    Mods\modSkillTreeLoadouts\

Works on new games and existing saves.

## How to use

The skills screen gets a bar under the equipped skills:

| Action | Effect |
|---|---|
| **Click** a loadout | load it (after a confirmation) |
| **Hold** a loadout (1 s) | save your current build into it |
| **Right click** a loadout | rename it (Enter to keep, Esc to cancel, empty = default name) |
| **Reset** | refund every skill point of the tree (after a confirmation) |
| **Undo** | go back to the build you had before the last load or reset |

The active loadout has a gold border. Empty loadouts are greyed out.

### What a loadout contains

- every skill bought in the tree, with its level;
- the skills in the equipped slots;
- the skill mutagens;
- the equipped Blood and Wine mutation.

### What happens when you load one

1. Your current build is kept for **Undo**.
2. All skill points spent in the tree are refunded (points spent on mutations are kept).
3. The saved tree is bought back with your own points, following the game's unlock rules.
4. The mutation, the slots and the mutagens are equipped again.

If something cannot be restored (not enough points, a mutagen no longer in your inventory...),
a notification lists it. Loading, saving and resetting are blocked during combat.

### Debug console (optional)

With the debug console enabled, the same actions are available as commands:

    stl_save(1)             save the current build into loadout 1 (1 to 5)
    stl_load(1)             load loadout 1
    stl_reset()             refund the tree
    stl_undo()              go back to the previous build
    stl_info(1)             cost of loadout 1 and points available
    stl_name(1, "Signs")    rename loadout 1

## Compatibility

- **Incompatible** with any mod that replaces the skills screen
  (`gameplay\gui_new\swf\character\panel_character_dupe.redswf`), for example
  *Skill Slots Presets*. Only one of them can be shown; the loadouts still work from the
  debug console.
- The legacy skill tree option does not show the bar yet (console commands work).
- Mouse and keyboard only for the bar: no gamepad support yet.
- Mods that heavily change the skill rules may prevent a loadout from being rebuilt in full;
  the mod never spends points the game would not let you spend.

## Languages

Every language of the game: English, French, German, Italian, Spanish (Spain and Mexico),
Brazilian Portuguese, Polish, Czech, Hungarian, Russian, Ukrainian, Turkish, Japanese,
Korean, Traditional and Simplified Chinese, Arabic. English and French are proofread; the
other translations are first versions, corrections are welcome.

## License

The mod's code is released under the **GNU GPL v3.0** (see `LICENSE`, next to this file),
with an additional permission to combine it with The Witcher 3 and REDkit and convey the
result, and a license that lets CD PROJEKT RED use it without the GPL conditions
(see `LICENSE-EXCEPTION`).
Source code: https://github.com/devleesch001/tw3-mod-skill-tree-loadouts

The game and its files, including the original skills screen this mod modifies, belong to
CD PROJEKT RED and are not covered by this license. The Witcher® is a trademark of
CD PROJEKT S.A.

## Uninstallation

Delete `Mods\modSkillTreeLoadouts`. Your loadouts are stored in your saves; without the mod
the game ignores them. Your current build stays as it is.

---

## Français

Sauvegardez **tout votre arbre de compétences** et changez de build en un clic, avec vos
propres points uniquement. Barre sous les compétences équipées : **clic** = charger,
**maintenir** = sauvegarder, **clic droit** = renommer, **Réinitialiser** et **Annuler**.
Installation : extraire l'archive dans le dossier du jeu. Incompatible avec les mods qui
remplacent l'écran des compétences (par exemple *Skill Slots Presets*).
