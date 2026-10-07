#!/bin/bash
#
# Ajoute des SVG de « Greed F1/Ressources/ » dans « Greed F1/Resources/Assets.xcassets/ »,
# en ligne de commande — aucune manipulation manuelle dans Xcode.
#
#   ./ios/scripts/ajouter-assets.sh                    tous les SVG de Ressources/
#   ./ios/scripts/ajouter-assets.sh logo-bandeau       un seul (avec ou sans .svg)
#
# Le parcours est RÉCURSIF : « Ressources/flags/ » et « Ressources/traces/ » portent un
# fichier par Grand Prix, écrits par « extraire-gp.mjs ». Le nom de l'asset est celui du
# fichier, sans son dossier — « flags/flag-italie.svg » devient Image("flag-italie").
#
# Chaque SVG devient un imageset universel avec « Preserve Vector Data » activé :
# sans ce réglage, iOS pixellise le tracé dès qu'il est agrandi.
#
# **Les tracés de circuits et les icônes `icon-*` reçoivent en plus le rendu `template`**,
# et eux seuls : ce sont des traits monochromes, qui doivent prendre l'encre de l'écran qui
# les monte. Un drapeau
# traité de même perdrait ses couleurs — il ne serait plus qu'une silhouette teintée.
# Le dossier « Greed F1/ » est un groupe synchronisé (Xcode 16+) : les fichiers écrits
# ici entrent dans la cible sans toucher au .pbxproj.

set -euo pipefail

RACINE_IOS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$RACINE_IOS/Greed F1/Ressources"
CATALOGUE="$RACINE_IOS/Greed F1/Resources/Assets.xcassets"

[ -d "$SOURCE" ]    || { echo "✗ Dossier source introuvable : $SOURCE" >&2; exit 1; }
[ -d "$CATALOGUE" ] || { echo "✗ Catalogue introuvable : $CATALOGUE" >&2; exit 1; }

# **Les planches sont exclues du parcours par défaut.** `logo.svg`, `logo-02.svg` et
# `logoV2.svg` portent plusieurs icônes dans un seul tracé : installées telles quelles,
# elles n'affichent rien d'utilisable et pèsent pour rien dans le bundle. Elles se
# découpent par « decouper-icones.sh », d'après le manifeste. Les nommer en argument reste
# possible — c'est alors un choix explicite.
PLANCHES='logo logo-02 logoV2'

# Liste des SVG à traiter : les arguments, ou tout le dossier Ressources/ à défaut.
svgs=()
if [ "$#" -gt 0 ]; then
    for arg in "$@"; do
        chemin="$(find "$SOURCE" -name "${arg%.svg}.svg" | head -1)"
        [ -n "$chemin" ] || { echo "✗ SVG introuvable : ${arg%.svg}.svg" >&2; exit 1; }
        svgs+=("$chemin")
    done
else
    while IFS= read -r chemin; do
        nom="$(basename "$chemin" .svg)"
        case " $PLANCHES " in *" $nom "*) continue ;; esac
        svgs+=("$chemin")
    done < <(find "$SOURCE" -name '*.svg' | sort)
fi

[ "${#svgs[@]}" -gt 0 ] || { echo "Aucun SVG à ajouter dans $SOURCE"; exit 0; }

for chemin in "${svgs[@]}"; do
    nom="$(basename "$chemin" .svg)"
    imageset="$CATALOGUE/$nom.imageset"

    mkdir -p "$imageset"
    cp "$chemin" "$imageset/$nom.svg"

    # Un tracé de circuit ou une icône se teinte ; un drapeau garde ses couleurs.
    rendu=""
    case "$chemin" in
        */traces/*|*/icon-*) rendu=',
    "template-rendering-intent" : "template"' ;;
    esac

    cat > "$imageset/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "$nom.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true$rendu
  }
}
JSON

    echo "✓ $nom  →  Image(\"$nom\")"
done

echo
echo "${#svgs[@]} asset(s) à jour. Compiler pour vérifier :"
echo "  xcodebuild -project \"ios/Greed F1.xcodeproj\" -scheme \"Greed F1\" \\"
echo "    -destination \"platform=iOS Simulator,name=iPhone 17 Pro\" build"
