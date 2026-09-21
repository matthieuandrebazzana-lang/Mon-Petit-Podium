#!/bin/bash
#
# Ajoute des SVG de « Greed F1/Ressources/ » dans « Greed F1/Resources/Assets.xcassets/ »,
# en ligne de commande — aucune manipulation manuelle dans Xcode.
#
#   ./ios/scripts/ajouter-assets.sh                    tous les SVG de Ressources/
#   ./ios/scripts/ajouter-assets.sh logo-bandeau       un seul (avec ou sans .svg)
#
# Chaque SVG devient un imageset universel avec « Preserve Vector Data » activé :
# sans ce réglage, iOS pixellise le tracé dès qu'il est agrandi.
# Le dossier « Greed F1/ » est un groupe synchronisé (Xcode 16+) : les fichiers écrits
# ici entrent dans la cible sans toucher au .pbxproj.

set -euo pipefail

RACINE_IOS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$RACINE_IOS/Greed F1/Ressources"
CATALOGUE="$RACINE_IOS/Greed F1/Resources/Assets.xcassets"

[ -d "$SOURCE" ]    || { echo "✗ Dossier source introuvable : $SOURCE" >&2; exit 1; }
[ -d "$CATALOGUE" ] || { echo "✗ Catalogue introuvable : $CATALOGUE" >&2; exit 1; }

# Liste des SVG à traiter : les arguments, ou tout le dossier Ressources/ à défaut.
svgs=()
if [ "$#" -gt 0 ]; then
    for arg in "$@"; do
        chemin="$SOURCE/${arg%.svg}.svg"
        [ -f "$chemin" ] || { echo "✗ SVG introuvable : $chemin" >&2; exit 1; }
        svgs+=("$chemin")
    done
else
    while IFS= read -r chemin; do
        svgs+=("$chemin")
    done < <(find "$SOURCE" -maxdepth 1 -name '*.svg' | sort)
fi

[ "${#svgs[@]}" -gt 0 ] || { echo "Aucun SVG à ajouter dans $SOURCE"; exit 0; }

for chemin in "${svgs[@]}"; do
    nom="$(basename "$chemin" .svg)"
    imageset="$CATALOGUE/$nom.imageset"

    mkdir -p "$imageset"
    cp "$chemin" "$imageset/$nom.svg"

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
    "preserves-vector-representation" : true
  }
}
JSON

    echo "✓ $nom  →  Image(\"$nom\")"
done

echo
echo "${#svgs[@]} asset(s) à jour. Compiler pour vérifier :"
echo "  xcodebuild -project \"ios/Greed F1.xcodeproj\" -scheme \"Greed F1\" \\"
echo "    -destination \"platform=iOS Simulator,name=iPhone 17 Pro\" build"
