"""Nom d'un Grand Prix dans une phrase, en français et en anglais.

Le nom en base est un libellé d'Unibet (« GP du Mexique », « GP São Paulo »,
« GP Pays Bas ») : il change d'une semaine à l'autre et n'est écrit qu'en
français. **On n'en dérive jamais le nom anglais** — « GP du Mexique » donnait
« du Mexique GP ». Le libellé ne sert qu'à retrouver le **slug** du Grand Prix,
et c'est le slug qui donne le nom, dans chaque langue, depuis `NOMS`.

Les slugs sont ceux de `slugCircuit` (`frontend/src/composants/TracesCircuits.jsx`)
et de `SlugCircuit` (iOS) ; les noms anglais sont ceux du calendrier de l'app iOS
(`TraductionsEN.swift`, clés `gp.<slug>.nom`), pour que l'app et les
notifications disent la même chose — `tests/test_noms_gp.py` le vérifie.

Le français porte l'article du pays, élidé au besoin (« GP d'Italie », « GP des
Pays-Bas », « GP du Mexique ») : les phrases n'ont plus qu'à écrire « pour le »
ou « du » devant.
"""

from __future__ import annotations

import logging
import re
import unicodedata

logger = logging.getLogger("uvicorn.error")

# slug → (français, anglais). Saison 2026, plus Bahreïn et l'Arabie saoudite,
# qu'Unibet peut encore nommer (« GP Bahrein » a remplacé Sepang le 1er octobre).
NOMS: dict[str, tuple[str, str]] = {
    "australie": ("GP d'Australie", "Australian GP"),
    "chine": ("GP de Chine", "Chinese GP"),
    "japon": ("GP du Japon", "Japanese GP"),
    "bahrein": ("GP de Bahreïn", "Bahrain GP"),
    "arabie-saoudite": ("GP d'Arabie saoudite", "Saudi Arabian GP"),
    "miami": ("GP de Miami", "Miami GP"),
    "canada": ("GP du Canada", "Canadian GP"),
    "monaco": ("GP de Monaco", "Monaco GP"),
    "barcelone": ("GP de Barcelone", "Barcelona GP"),
    "autriche": ("GP d'Autriche", "Austrian GP"),
    "grande-bretagne": ("GP de Grande-Bretagne", "British GP"),
    "belgique": ("GP de Belgique", "Belgian GP"),
    "hongrie": ("GP de Hongrie", "Hungarian GP"),
    "pays-bas": ("GP des Pays-Bas", "Dutch GP"),
    "italie": ("GP d'Italie", "Italian GP"),
    "espagne": ("GP d'Espagne", "Spanish GP"),
    "azerbaidjan": ("GP d'Azerbaïdjan", "Azerbaijan GP"),
    "malaisie": ("GP de Malaisie", "Malaysian GP"),
    "singapour": ("GP de Singapour", "Singapore GP"),
    "etats-unis": ("GP des États-Unis", "United States GP"),
    "mexique": ("GP du Mexique", "Mexican GP"),
    "bresil": ("GP du Brésil", "Brazilian GP"),
    "las-vegas": ("GP de Las Vegas", "Las Vegas GP"),
    "qatar": ("GP du Qatar", "Qatar GP"),
    "abu-dhabi": ("GP d'Abu Dhabi", "Abu Dhabi GP"),
}

# Les alias de `slugCircuit`, dans le même ordre, plus les trois qu'il n'a pas
# (Mexique écrit à l'anglaise, Bahreïn, Arabie saoudite). Le premier qui répond
# l'emporte.
ALIAS: tuple[tuple[re.Pattern[str], str], ...] = tuple(
    (re.compile(motif), cle)
    for motif, cle in (
        (r"melbourne|albert.?park|australi", "australie"),
        (r"shanghai|chine|china", "chine"),
        (r"suzuka|japon|japan", "japon"),
        (r"bahrein|bahrain|sakhir", "bahrein"),
        (r"saoudi|saudi|djeddah|jeddah", "arabie-saoudite"),
        # Avant `etats-unis` : « amerique » ou « usa » dans un libellé de Miami l'y enverrait.
        (r"miami", "miami"),
        (r"montreal|canad", "canada"),
        (r"monte.?carlo|monaco", "monaco"),
        (r"barcelon|catalun|catalogne|montmelo", "barcelone"),
        (r"spielberg|red.?bull.?ring|autriche|austria", "autriche"),
        (r"silverstone|bretagne|britain|british|royaume.?uni|angleterre", "grande-bretagne"),
        # Pas « spa » seul : il est dans « espagne ».
        (r"francorchamps|belgi", "belgique"),
        (r"hungaroring|hongri|hungar", "hongrie"),
        (r"zandvoort|hollande|neerland|dutch", "pays-bas"),
        (r"monza", "italie"),
        (r"madrid|madring", "espagne"),
        (r"bakou|baku", "azerbaidjan"),
        (r"sepang|malaisi|malaysi|kuala.?lumpur", "malaisie"),
        (r"singapore|marina.?bay", "singapour"),
        (r"austin|texas|amerique|\busa\b|cota", "etats-unis"),
        (r"mexi", "mexique"),
        (r"sao.?paulo|interlagos|bresi|brazil", "bresil"),
        (r"vegas", "las-vegas"),
        (r"lusail|losail|doha", "qatar"),
        (r"abou.?dab|abu.?dhab|yas.?marina|emirats", "abu-dhabi"),
    )
)

LANGUES = ("fr", "en")

# Préfixe retiré en tête seulement, comme `slugCircuit` : un « GP » au milieu
# d'un libellé n'est pas un préfixe.
_PREFIXE = re.compile(r"^\s*(grand\s+prix|gp)\b", re.IGNORECASE)
# Article français en tête du reste : « du Mexique », « des Pays-Bas », « d'Italie ».
# Un mot entier suivi d'une espace, ou une élision : « Las Vegas » garde son « Las ».
_ARTICLE = re.compile(r"^\s*(?:(?:de\s+la|du|des|de|la|le|les)\s+|(?:de\s+l|d|l)['’]\s*)", re.IGNORECASE)


def _sans_accents(texte: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", texte) if unicodedata.category(c) != "Mn")


def _sans_prefixe(nom: str) -> str:
    """« GP du Mexique » → « Mexique » : préfixe puis article retirés."""
    reste = _PREFIXE.sub("", nom or "", count=1)
    return _ARTICLE.sub("", reste, count=1).strip()


def slug_du_gp(nom: str) -> str:
    """Le slug d'un libellé de GP : `mexique`, `bresil`… ou le libellé réduit s'il est inconnu."""
    texte = _sans_accents(_sans_prefixe(nom)).lower()
    texte = re.sub(r"[^a-z0-9]+", "-", texte).strip("-")
    if texte in NOMS:
        return texte
    for motif, cle in ALIAS:
        if motif.search(texte):
            return cle
    return texte


def nom_du_gp(nom: str, langue: str) -> str:
    """Le nom du GP à glisser dans une phrase de cette langue.

    Inconnu de `NOMS` : « Grand Prix » + le libellé sans préfixe ni article, le
    même dans les deux langues — un nom de lieu, jamais un mélange — et
    l'absence est journalisée pour que la table soit complétée.
    """
    langue = langue if langue in LANGUES else "fr"
    cle = slug_du_gp(nom)
    if cle in NOMS:
        return NOMS[cle][LANGUES.index(langue)]
    logger.warning("[noms_gp] GP sans nom traduit : %r (slug %r).", nom, cle)
    reste = _sans_prefixe(nom)
    return f"Grand Prix {reste}" if reste else "Grand Prix"
