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
    bin\config\r4game\user_config_matrix\pc\modSkillTreeLoadouts.xml   (the mod's option)

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

### Skill slot pages (option)

The **Skill slot pages** option, in the game's Options menu, goes from 1 (default: the game's
slots only) to 5. From 2, **pages of skill slots** are added, with buttons above the equipped
skills to switch the page shown. **Every page is active at once**: a skill works whichever
page it is on. The option applies when the skills screen opens.

- Pages 2 to 5 have 12 skill slots each. They unlock **one per skill point** once page 1 is
  full: page 2 slot 1 one point after the last slot of page 1, then slot 2, and so on up to
  page 5. They are **not linked to the mutagens**: only page 1 gives mutagen bonuses.
- The 4 Blood and Wine mutation slots are not paged: every page shows the game's own 4,
  with the game's rules.
- A loadout saves and restores every page.
- Lowering the option removes the last pages and unequips their skills.
- The legacy skill tree option shows page 1 only (the other pages stay active).

### Debug console (optional)

With the debug console enabled, the same actions are available as commands:

    stl_save(1)             save the current build into loadout 1 (1 to 5)
    stl_load(1)             load loadout 1
    stl_reset()             refund the tree
    stl_undo()              go back to the previous build
    stl_info(1)             cost of loadout 1 and points available
    stl_name(1, "Signs")    rename loadout 1
    stl_pages_remove()      empty and remove pages 2 to 5 (before uninstalling)

## Compatibility

- **Incompatible** with any mod that replaces the skills screen
  (`gameplay\gui_new\swf\character\panel_character_dupe.redswf`), for example
  *Skill Slots Presets*. Only one of them can be shown; the loadouts still work from the
  debug console.
- The legacy skill tree option does not show the bar yet (console commands work).
- Mouse and keyboard only for the bar: no gamepad support yet.
- Slot pages: **incompatible** with other mods that add skill slots (for example
  *More Skill Slots*, *Extra Skill Slots*); the pages then stay off.
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

Delete `Mods\modSkillTreeLoadouts` and
`bin\config\r4game\user_config_matrix\pc\modSkillTreeLoadouts.xml`. Your loadouts are stored
in your saves; without the mod the game ignores them. Your current build stays as it is.

**If you used slot pages**: the extra slots are kept in your save, and a skill left in them
would stay active without being shown. First set the option back to 1 and open the skills
screen (or run `stl_pages_remove()` in the debug console), save the game, then delete the
files. If the mod was removed without that, the skills left on pages 2 to 5 still show as
equipped in the tree: drag each one onto a slot of the normal grid, then remove it.

---

## Français

Sauvegardez **tout votre arbre de compétences** et changez de build en un clic, avec vos
propres points uniquement. Barre sous les compétences équipées : **clic** = charger,
**maintenir** = sauvegarder, **clic droit** = renommer, **Réinitialiser** et **Annuler**.
Installation : extraire l'archive dans le dossier du jeu. Incompatible avec les mods qui
remplacent l'écran des compétences (par exemple *Skill Slots Presets*).

Option **Pages d'emplacements** (menu Options, 1 à 5) : jusqu'à 5 pages d'emplacements,
toutes actives, boutons au-dessus des compétences équipées ; seule la page 1 est liée aux
mutagènes. Avant de désinstaller, remettez l'option à 1 et ouvrez l'écran des compétences
(ou tapez `stl_pages_remove()` dans la console), sauvegardez, puis supprimez les fichiers.
