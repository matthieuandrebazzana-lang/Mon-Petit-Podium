#!/bin/bash
#
# Écrit « Greed F1/Ressources/flags-pilotes/drapeau-<code>.svg » — les drapeaux de
# NATIONALITÉ des pilotes, DEPUIS LA VERSION WEB, jamais dessinés ici.
#
#   ./ios/scripts/extraire-drapeaux-pilotes.sh
#   ./ios/scripts/ajouter-assets.sh          puis, pour les installer
#
# La source est « frontend/node_modules/country-flag-icons/3x2/ », la même bibliothèque
# qu'importe « frontend/src/composants/DrapeauxPilotes.jsx ». Les codes sont lus dans
# « frontend/src/lib/nationalites.js » (CODES_PAYS), qui reste le seul propriétaire de la
# question « de quel pays est ce pilote » : ajouter un pilote se fait CÔTÉ WEB, puis on
# rejoue ce script.
#
# **Pourquoi pas la planche « assets/flags.svg ».** Elle porte les pays HÔTES des douze
# Grands Prix — cinq d'entre eux seulement sont des nationalités de la grille 2026
# (Brésil, Espagne, Italie, Mexique, Pays-Bas). Les onze autres — Royaume-Uni, France,
# Monaco, Canada, Japon, Thaïlande, Allemagne, Nouvelle-Zélande, Argentine, Finlande,
# Australie — n'y sont pas, et la règle du projet interdit d'approximer un drapeau : une
# croix du Sud ou une croix nordique n'a pas de description qu'un dégradé sache poser.
# Seize dessins exacts, c'est exactement l'arbitrage déjà rendu côté web.
#
# **Ces fichiers sont hors du bundle** : « Ressources/ » (deux s) est de la matière de
# travail, retirée par EXCLUDED_SOURCE_FILE_NAMES, dont le motif « */Ressources/*/* »
# couvre déjà ce sous-dossier.

set -euo pipefail

RACINE_IOS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RACINE="$(cd "$RACINE_IOS/.." && pwd)"

SOURCE="$RACINE/frontend/node_modules/country-flag-icons/3x2"
TABLE="$RACINE/frontend/src/lib/nationalites.js"
CIBLE="$RACINE_IOS/Greed F1/Ressources/flags-pilotes"

[ -d "$SOURCE" ] || {
    echo "✗ Bibliothèque introuvable : $SOURCE" >&2
    echo "  Installer les dépendances du frontend : npm --prefix frontend install" >&2
    exit 1
}
[ -f "$TABLE" ] || { echo "✗ Table des nationalités introuvable : $TABLE" >&2; exit 1; }

# Les codes ISO employés par la grille, relevés sur les lignes « code: "XX" » de la table.
codes="$(grep -o 'code: "[A-Z][A-Z]"' "$TABLE" | grep -o '"[A-Z][A-Z]"' | tr -d '"' | sort -u)"
[ -n "$codes" ] || { echo "✗ Aucun code ISO relevé dans $TABLE" >&2; exit 1; }

mkdir -p "$CIBLE"

n=0
for code in $codes; do
    fichier="$SOURCE/$code.svg"
    [ -f "$fichier" ] || { echo "✗ Drapeau absent de la bibliothèque : $code" >&2; exit 1; }

    minuscule="$(echo "$code" | tr '[:upper:]' '[:lower:]')"
    cp "$fichier" "$CIBLE/drapeau-$minuscule.svg"
    echo "✓ $code  →  Image(\"drapeau-$minuscule\")"
    n=$((n + 1))
done

echo
echo "$n drapeau(x) de nationalité écrits dans Ressources/flags-pilotes/."
echo "Les installer dans le catalogue :"
echo "  ./ios/scripts/ajouter-assets.sh"
