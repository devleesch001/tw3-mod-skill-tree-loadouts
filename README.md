# Skill Tree Loadouts

Mod pour **The Witcher 3: Wild Hunt Remastered (5.x)** — [Nexus Mods #14755](https://www.nexusmods.com/witcher3/mods/14755).

Sauvegarde **tout l'arbre de compétences** dans un preset (compétences achetées et leurs
niveaux, emplacements équipés, mutagènes, mutation Blood and Wine) et permet de changer de
build en un clic, **avec ses propres points uniquement** : le chargement rembourse l'arbre
puis le rachète en suivant les règles du jeu. Pas de potion, pas de triche.

Dans l'écran des compétences, une barre sous les emplacements équipés :
**clic** = charger, **maintenir** = sauvegarder, **clic droit** = renommer,
**Réinitialiser** / **Annuler**, avec la fenêtre de confirmation du jeu.
Traduit dans les 18 langues du jeu. Aucun fichier de script du jeu n'est remplacé
(annotations `@addMethod` / `@wrapMethod`), pas besoin de Script Merger.

Le guide joueur (installation, utilisation, compatibilité) est dans
[`src/release/README.md`](src/release/README.md), livré avec le mod.

## Organisation

```
src/scripts/   le mod en WitcherScript (.ws, utilisé tel quel par le jeu)
src/strings/   les textes, un CSV par langue (en.csv = référence)
src/ui/        nos modifications de l'écran des compétences (ActionScript 3), en patch
work/ui/       les classes complètes à éditer (générées, non versionnées)
src/release/   README livré aux joueurs
tools/lib/     modules internes du CLI (+ cr2w_swf.py, voir docs/cr2w_swf.md)
dist/          le mod construit, généré, même arborescence que le dossier du jeu
```

## Le CLI

Tout passe par `cli.ps1` (PowerShell 5.1+). Le `Makefile` n'est qu'une façade
(`make build`, `make run`…).

| Commande | Rôle |
|---|---|
| `.\cli.ps1 doctor` | vérifie la chaîne d'outils et l'installation du jeu |
| `.\cli.ps1 build [scripts\|strings\|ui\|all]` | construit `src/` dans `dist/` (`ui` seulement si un `.as` a changé, `-Force` pour forcer) |
| `.\cli.ps1 link` / `unlink` | branche / débranche `dist/` dans le dossier `Mods` du jeu (jonction) |
| `.\cli.ps1 run` | build + link + lance le jeu |
| `.\cli.ps1 package` | crée `release/SkillTreeLoadouts-<version>.zip`, à extraire dans le dossier du jeu |
| `.\cli.ps1 clean [-All]` | supprime `dist/` et les fichiers intermédiaires |

Réglages : [`stl.config.psd1`](stl.config.psd1) (version, langues, outils). Un
`stl.local.psd1` facultatif, non versionné, surcharge les chemins propres à une machine.
Le jeu et REDkit sont détectés automatiquement dans les bibliothèques Steam.

### Modifier l'interface

Le code du jeu n'est jamais versionné : `src/ui/<package>/<Classe>.as.patch` ne contient
que nos changements. Au build, la classe d'origine est extraite du jeu, le patch appliqué,
et le fichier complet est écrit dans `work/ui/<package>/<Classe>.as`. **C'est ce fichier
qu'on édite** : chaque `build` régénère le `.patch` à partir de lui. Une classe écrite
entièrement pour le mod se met directement en `.as` dans `src/ui/`.

### Outils nécessaires

`doctor` indique ce qui manque et comment l'installer :

- **The Witcher 3 REDkit** (Steam) — `wcc_lite` pour extraire et empaqueter les bundles
- **JPEXS FFDec** + Java — compilation de l'ActionScript
- **w3strings Remastered** (Nexus 13094) dans `utils\w3stringsr.exe` — encodage des textes
- **Python 3.8+** — uniquement pendant le build
- **git** — applique et régénère les patchs de `src/ui/`

## Licence

Le code de ce projet est distribué sous **GNU GPL v3.0** : voir [`LICENSE`](LICENSE),
avec deux ajouts dans [`LICENSE-EXCEPTION`](LICENSE-EXCEPTION) :

1. **Combinaison avec le jeu** (section 7 de la GPL v3) : le mod peut être combiné avec
   The Witcher 3 et REDkit et distribué ainsi, sans que les parties de CD PROJEKT RED
   passent sous GPL.
2. **Licence accordée à CD PROJEKT S.A.** : CD PROJEKT RED peut utiliser, modifier et
   intégrer ce mod dans ses produits sans respecter les conditions de la GPL.

Les contributions sont acceptées aux mêmes conditions (GPL v3 + ces deux ajouts).

Sont exclus de cette licence, car ils appartiennent à CD PROJEKT RED : le jeu et ses
fichiers, dont l'écran des compétences d'origine que modifie le mod. Le dépôt n'en contient
que les quelques lignes de contexte nécessaires aux patchs de `src/ui/`.
The Witcher® est une marque de CD PROJEKT S.A.
