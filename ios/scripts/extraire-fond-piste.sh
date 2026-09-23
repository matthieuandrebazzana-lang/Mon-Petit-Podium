#!/usr/bin/env bash
#
# extraire-fond-piste.sh — le fond de la vue piste, EXTRAIT de la planche du projet.
#
# Source   : assets/vue_piste.svg (la planche du dépôt, commune aux deux applications)
# Cible    : ios/Greed F1/Resources/Vecteurs/vue_piste.svg (lue au runtime par PlancheSVG)
#
# Trois choses sont retirées, et rien d'autre n'est touché — aucun tracé n'est recopié ni
# redessiné (`ios/CLAUDE.md` §3) :
#
#   1. Les DEUX rectangles du bandeau (`cls-5` puis `cls-3`, y=0, hauteur 140,13). Le
#      bandeau est peint par SwiftUI parce qu'il porte la couleur Pantone du championnat,
#      le damier du projet et le nom du championnat — exactement le même écart que
#      `frontend/src/composants/FondPiste.jsx` assume côté web, et pour les mêmes raisons.
#
#   2. Le `<pattern>` du damier. `PlancheSVG` n'est pas un moteur SVG : il ne connaît pas
#      les motifs, et il peindrait les tuiles blanches du `<pattern>` comme autant de
#      formes posées au milieu de la piste. Le damier est de toute façon un utilitaire de
#      l'app (``Damier``), pas un calque de la planche.
#
#   3. Les deux classes que le motif était seul à employer (`cls-1`, `cls-2`).
#
# Ce qui RESTE garde ses valeurs au centième : le sol beige et ses coins, les quatre
# segments de la ligne médiane, les deux kerbs.
#
# L'opacité de 11 % des segments médians n'est pas dans le fichier de sortie : `PlancheSVG`
# ne lit que `fill`. Elle est rendue par la substitution d'encre de ``VuePisteView``, qui
# est le mécanisme prévu pour ça.

set -euo pipefail

racine="$(cd "$(dirname "$0")/../.." && pwd)"
source_svg="$racine/assets/vue_piste.svg"
cible_svg="$racine/ios/Greed F1/Resources/Vecteurs/vue_piste.svg"

[ -f "$source_svg" ] || { echo "Planche introuvable : $source_svg" >&2; exit 1; }

python3 - "$source_svg" "$cible_svg" <<'PY'
import re, sys

source, cible = sys.argv[1], sys.argv[2]
svg = open(source, encoding="utf-8").read()

avant = len(svg)

# 1. Les deux rectangles du bandeau — repérés sur leur géométrie, pas sur leur rang.
svg, bandeaux = re.subn(
    r'\s*<rect class="cls-(?:5|3)" x="0" y="0" width="589\.5" height="140\.13"[^/]*/>',
    "", svg)

# 2. Le motif du damier.
svg, motifs = re.subn(r'\s*<pattern\b.*?</pattern>', "", svg, flags=re.S)

# 3. Les deux classes que lui seul employait.
svg, classes = re.subn(r'\s*\.cls-(?:1|2) \{\s*fill: [^;]+;\s*\}', "", svg)

assert bandeaux == 2, f"bandeaux retirés : {bandeaux}, attendu 2"
assert motifs == 1, f"motifs retirés : {motifs}, attendu 1"
assert "<path" in svg and "cls-4" in svg and "cls-6" in svg, "la piste a perdu ses formes"

open(cible, "w", encoding="utf-8").write(svg)
print(f"{cible} — {avant - len(svg)} caractères retirés "
      f"({bandeaux} rects de bandeau, {motifs} motif, {classes} classes)")
PY
