# `cr2w_swf.py` — remplacer l'interface Flash dans un `.redswf`

Script : [`tools/lib/cr2w_swf.py`](../tools/lib/cr2w_swf.py)

## En une phrase

Le script prend le fichier de l'écran des compétences **tel qu'il est dans le jeu**,
remplace **uniquement l'animation Flash** qu'il contient par la nôtre (celle qui a les
boutons de presets), et remet le fichier en ordre pour que le jeu l'accepte.

Il ne sert **qu'au moment du build**, sur le PC du développeur. Il n'est **jamais livré**
avec le mod : les joueurs reçoivent le fichier final, déjà assemblé.

## Pourquoi on en a besoin

L'écran des compétences du jeu est un seul fichier :
`gameplay\gui_new\swf\character\panel_character_dupe.redswf`.

Pour y ajouter nos boutons, on modifie son code Flash (ActionScript, dans
[`src/ui/`](../src/ui/)). Il faut ensuite remettre ce code modifié **dans** le fichier
`.redswf`, et c'est là qu'intervient le script.

### Et l'outil officiel ?

L'outil officiel de CD Projekt RED, **REDkit**, sait produire un `.redswf`, mais
**uniquement depuis son éditeur graphique**, dans un projet de mod (voir
[Virtual depot](https://cdprojektred.atlassian.net/wiki/spaces/W3REDkit/pages/39190599/Virtual+depot+and+source+control)).
En ligne de commande (`wcc_lite swfimport`), la conversion se fait mais l'enregistrement
échoue sans projet REDkit. Pour garder un build entièrement automatique (`.\stl.ps1 build`),
on passe par ce script à la place.

## Ce qu'il y a dans un `.redswf`

Un `.redswf` est une « boîte » au format **CR2W**, le format de fichier interne du moteur
REDengine. Celle de l'écran des compétences contient :

```
panel_character_dupe.redswf  (≈ 21 Mo)
├── en-tête              identité du fichier, taille totale, somme de contrôle
├── sommaire             liste des objets : où ils commencent, leur taille, leur somme de contrôle
├── objet 0  CSwfResource
│     └── le film Flash compressé (« CFX », ≈ 0,5 Mo)   ← la SEULE chose qu'on remplace
└── objets 1 à 16  CSwfTexture
      └── les images de l'écran (≈ 20 Mo)               ← jamais modifiées
```

Les **sommes de contrôle** (CRC32) sont des nombres calculés à partir du contenu. Elles
permettent au jeu de vérifier que le fichier n'est pas abîmé. Si on change le contenu
sans les recalculer, le jeu peut refuser le fichier.

## Ce que fait le script, étape par étape

1. **Lire le sommaire** pour savoir où se trouve chaque objet dans le fichier.
2. **Trouver le film Flash** dans l'objet 0 : il commence par la signature `CFX`,
   précédée de sa longueur.
3. **Remplacer le film** par le nôtre. Le nôtre est un peu plus gros (il contient le code
   des boutons), donc tout ce qui suit est décalé : le script corrige la taille de l'objet 0
   et la position des 16 objets d'images dans le sommaire.
4. **Recalculer les sommes de contrôle** : une par objet, une par table du sommaire, et
   une pour l'en-tête (calculée sur les 160 premiers octets, avec le champ de la somme
   remplacé par la valeur fixe `0xDEADBEEF`, comme le fait le moteur).
5. **Vérifier le résultat** avant de l'écrire : toutes les tailles et toutes les sommes
   doivent correspondre, sinon le script s'arrête avec une erreur et rien n'est écrit.

Il ne touche à rien d'autre : les images, les noms et les autres données du fichier
restent identiques, octet pour octet.

## Comment il est utilisé

Normalement, **on ne l'appelle jamais à la main** : `.\stl.ps1 build ui` (ou `build`,
`run`) s'en charge.

```
fichier d'origine du jeu (r4gui.bundle)
   │  wcc_lite unbundle            ← outil officiel (REDkit), une seule fois, mis en cache dans work/cache
   ▼
panel_character_dupe.redswf
   │  cr2w_swf.py extract          → movie.gfx (le film Flash d'origine)
   ▼
movie.gfx
   │  FFDec                        ← recompile nos classes de src/ui/ dans le film
   ▼
movie.gfx (modifié)
   │  cr2w_swf.py patch            → .redswf avec notre film, tailles et sommes recalculées
   ▼
panel_character_dupe.redswf (modifié)
   │  wcc_lite pack + metadatastore   ← outils officiels (REDkit)
   ▼
dist/Mods/modSkillTreeLoadouts/content/blob0.bundle + metadata.store
```

### Commandes (pour diagnostiquer)

```
python -I tools/lib/cr2w_swf.py info    <fichier.redswf>                  # affiche le sommaire et dit si le fichier est valide
python -I tools/lib/cr2w_swf.py verify  <fichier.redswf>                  # vérifie toutes les tailles et sommes de contrôle
python -I tools/lib/cr2w_swf.py extract <fichier.redswf> <film.gfx>       # sort le film Flash
python -I tools/lib/cr2w_swf.py patch   <origine.redswf> <film.gfx> <sortie.redswf>
```

`-I` lance Python en mode isolé : il n'importe rien depuis le dossier courant.

## Comment on sait qu'il est fiable

Ces vérifications ont été faites sur le fichier de la version 5.0 du jeu :

- **Lecture** : sur le fichier d'origine, le script recalcule exactement les mêmes sommes
  de contrôle que celles écrites par CD Projekt RED (en-tête, tables et les 17 objets).
- **Aller-retour** : extraire le film d'origine puis le réinjecter redonne un fichier
  **identique à l'octet près** à l'original.
- **En jeu** : l'écran modifié s'affiche et fonctionne (barre de presets, confirmation,
  renommage).
- Une réécriture indépendante en C# a produit exactement le même fichier, octet pour octet.

## Limites

- Il ne remplace **que le film Flash**. Si un jour on veut ajouter de **nouvelles images**
  à l'écran, il ne suffira pas : il faudra passer par REDkit (projet de mod + import).
  Nos boutons sont dessinés en formes vectorielles et en texte, ils n'en ont pas besoin.
- Il suppose que le fichier ne contient **qu'un seul** film (`CFX` ou `GFX`) dans son
  premier objet, ce qui est le cas des écrans de l'interface du jeu.
- Si une **mise à jour du jeu** change le format CR2W, `verify` le signalera : le build
  s'arrête au lieu de produire un fichier corrompu.

## Dépendance

Python 3.8 ou plus récent, uniquement la bibliothèque standard (`struct`, `zlib`).
`.\stl.ps1 doctor` vérifie sa présence ; le chemin se règle dans `stl.config.psd1`
(`Toolchain.Python`, vide = `python` du PATH).
