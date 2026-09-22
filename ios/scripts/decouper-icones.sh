#!/bin/bash
#
# Découpe les planches SVG de « Greed F1/Ressources/ » en icônes individuelles dans
# « Greed F1/Resources/Assets.xcassets/ », d'après le manifeste « scripts/icones.txt ».
#
#   ./ios/scripts/decouper-icones.sh                 toutes les icônes du manifeste
#   ./ios/scripts/decouper-icones.sh icone-accueil   une seule
#
# Une planche porte plusieurs icônes dans un même tracé. Plutôt que d'en extraire les
# chemins — qui divergeraient de la source au premier ajustement —, on rouvre la planche
# entière derrière une fenêtre : le `viewBox` cadre l'icône voulue, le reste est rogné.
# Même procédé que « logo-bandeau.svg », qui n'est que « logo-05.svg » à viewBox rognée.
#
# Les `width`/`height` posés en points donnent à l'asset sa taille naturelle : sans eux
# une barre d'onglets affiche l'icône à la taille du viewBox, soit 78 pt de haut.
# « template » rend l'icône teintable — sans quoi elle reste noire, actif comme inactif.

set -euo pipefail

# Séparateur décimal : un « 25,67 » en locale française donnerait un SVG invalide.
export LC_ALL=C

RACINE_IOS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$RACINE_IOS/Greed F1/Ressources"
CATALOGUE="$RACINE_IOS/Greed F1/Resources/Assets.xcassets"
MANIFESTE="$RACINE_IOS/scripts/icones.txt"

[ -f "$MANIFESTE" ] || { echo "✗ Manifeste introuvable : $MANIFESTE" >&2; exit 1; }
[ -d "$CATALOGUE" ] || { echo "✗ Catalogue introuvable : $CATALOGUE" >&2; exit 1; }

compte=0

while read -r planche nom x y largeur hauteur hauteurPt _reste; do
    # Lignes vides et commentaires.
    case "${planche:-#}" in ''|'#'*) continue ;; esac

    # Filtre par argument, quand il y en a.
    if [ "$#" -gt 0 ]; then
        garde=0
        for arg in "$@"; do [ "$arg" = "$nom" ] && garde=1; done
        [ "$garde" = 1 ] || continue
    fi

    svg="$SOURCE/$planche.svg"
    [ -f "$svg" ] || { echo "✗ Planche introuvable : $svg" >&2; exit 1; }

    # Largeur en points, déduite du rapport de la fenêtre : l'icône garde ses proportions.
    largeurPt=$(awk -v l="$largeur" -v h="$hauteur" -v p="$hauteurPt" 'BEGIN { printf "%.2f", l * p / h }')

    imageset="$CATALOGUE/$nom.imageset"
    mkdir -p "$imageset"

    # Réécriture de l'en-tête <svg …> : fenêtre + taille naturelle. Le reste est intact.
    sed -E "s|<svg([^>]*)viewBox=\"[^\"]*\"|<svg\1width=\"${largeurPt}\" height=\"${hauteurPt}\" viewBox=\"${x} ${y} ${largeur} ${hauteur}\"|" \
        "$svg" > "$imageset/$nom.svg"

    grep -q "viewBox=\"${x} ${y}" "$imageset/$nom.svg" \
        || { echo "✗ En-tête <svg> non réécrit dans $planche.svg" >&2; exit 1; }

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
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
JSON

    echo "✓ $nom  ←  $planche.svg  (${largeurPt} × ${hauteurPt} pt)  →  Image(\"$nom\")"
    compte=$((compte + 1))
done < "$MANIFESTE"

[ "$compte" -gt 0 ] || { echo "✗ Aucune icône ne correspond" >&2; exit 1; }

echo
echo "$compte icône(s) à jour. Compiler pour vérifier :"
echo "  xcodebuild -project \"ios/Greed F1.xcodeproj\" -scheme \"Greed F1\" \\"
echo "    -destination \"platform=iOS Simulator,name=iPhone 17 Pro\" build"
