"""Scraping des cotes Formule 1 chez Unibet.

Le principe reste celui de la section 3.1 du CLAUDE.md : on part du nœud racine
de la Formule 1, on découvre les Grands Prix disponibles, on lit leurs marchés,
et on convertit chaque cote en points (règle 4.1). Rien n'est codé en dur, ni la
liste des GP, ni celle des marchés.

Trois choses ont changé du côté d'Unibet depuis la rédaction du CLAUDE.md, et
elles expliquent l'essentiel du code ci-dessous :

1. **L'API demande un jeton.** `/lvs-api/...` répond désormais
   `401 {"message":"Missing X-LVS-HSToken"}` sans en-tête `X-LVS-HSToken`.
   Le jeton n'a rien d'un secret : il est déposé dans le HTML de n'importe
   quelle page de paris, et `jeton()` va le chercher là. Aucun compte, aucun
   cookie.

2. **`price` est une chaîne à virgule** (« 2,80 »), pas un nombre. Un
   `float(price)` lève, un `price * 10` concatène. C'est `en_points()` qui
   traite le cas, et lui seul.

3. **L'API ne rend qu'un seul marché par événement** — le marché vedette, le
   plus souvent « Vainqueur ». Aucun paramètre ne la fait céder (`includeAllMarkets`,
   `marketTypeDisplayGroupId`… ont tous été essayés, sans effet), et il n'existe
   pas d'endpoint JSON par événement. Les marchés complets ne sont exposés que
   par la page de l'événement, qui est rendue côté serveur : elle embarque ses
   données dans une balise `<script id="serverApp-state">` au format JSON.
   C'est de ce bloc que `marches()` extrait les marchés — pas du HTML rendu.
   On lit donc toujours du JSON, jamais des balises.

Le scraper ne remplace jamais les cotes d'un GP dont le statut est
`cotes_figees` : une fois les qualifications passées, les cotes sont arrêtées et
tout le monde pronostique sur les mêmes (règle 4.3).

**Il adopte aussi les lignes posées à la main.** Les onze Grands Prix de la fin
de saison sont en base avant qu'Unibet n'ouvre leur page, sous un `id_unibet`
inventé (`manuel-<slug>-2026`) : le scraper, qui se rapproche par cet
identifiant, en insérait une seconde. Il reconnaît désormais la ligne à son
**nom** et lui fait porter le vrai identifiant, **sans changer son UUID** — les
pronostics, favoris et résultats qui s'y rattachent restent valides. Voir
`_adopter`.

Depuis l'étape 11, il relève aussi **l'heure des qualifications** au passage.
C'est elle qui permet au job de `app/jobs/scraper.py` de se déclencher tout seul
deux heures plus tard, sans intervention manuelle. Ce module ne décide jamais de
figer quoi que ce soit : il découvre, il écrit, il rend compte. Le figeage est
une décision du job (ou de la route d'administration), prise **après** un
scraping réussi.
"""

import asyncio
import logging
import re
import unicodedata
from dataclasses import dataclass, field
from datetime import datetime
from html import unescape
from json import JSONDecodeError, loads
from zoneinfo import ZoneInfo

import httpx

from app.supabase_client import (
    ErreurSupabase,
    mettre_a_jour,
    selectionner,
    upserter,
)

# Même logger que le reste du backend : sous Railway, `uvicorn.error` est le
# seul à disposer d'un handler. Un logger maison écrirait dans le vide, et le
# résultat du scraping est précisément ce qu'on vient lire dans les logs.
logger = logging.getLogger("uvicorn.error")

# Nœud racine de la Formule 1 chez Unibet, parent de tous les GP (section 3.1).
RACINE_F1 = "p59209509"

BASE = "https://www.unibet.fr"
GABARIT_LVS = (
    "{base}/lvs-api/next/50/{noeud}"
    "?lineId=1&originId=2&breakdownEventsIntoDays=true"
    "&showPromotions=true&pageIndex=0"
)

# Page de la section Formule 1 : elle sert à la fois de source du jeton et de
# racine des URL d'événement. La page d'accueil du site répond 403 aux appels
# non navigateur ; celle-ci répond 200.
PAGE_F1 = f"{BASE}/paris-formule-1"

# Un serveur qui reçoit un User-Agent vide ou exotique est en droit de répondre
# 403, et Unibet le fait. Rien ici ne cherche à se faire passer pour autre chose
# qu'un client HTTP ordinaire : ces en-têtes sont ceux d'un navigateur banal.
ENTETES = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    ),
    "Accept-Language": "fr-FR,fr;q=0.9",
}

# Le jeton vit dans une des deux clés de configuration déposées dans la page.
# La variante « non expirante » est essayée en premier, l'autre sert de repli :
# les deux ont été vérifiées comme acceptées par l'API.
MOTIFS_JETON = (
    re.compile(r'"pselNonExpiringHsToken"\s*:\s*"([^"]+)"'),
    re.compile(r'"hsToken"\s*:\s*"([^"]+)"'),
)

# Bloc de données déposé par le rendu serveur d'Angular dans chaque page.
MOTIF_ETAT_SSR = re.compile(
    r'<script id="serverApp-state" type="application/json">(.*?)</script>',
    re.DOTALL,
)

# Seul l'événement « Course » nous intéresse. Ce filtre fait d'une pierre deux
# coups : il écarte les épreuves annexes (qualifications, sprint) dont les
# résultats ne sont pas ceux que valide l'étape 6, et il écarte surtout le nœud
# « Championnat du monde », que le nœud racine renvoie au même titre qu'un GP
# alors que ce n'est pas une course — son « événement » est le vainqueur du
# championnat, daté d'un 6 décembre de convenance. L'enregistrer créerait un
# faux Grand Prix, qui deviendrait le « prochain GP » de l'accueil.
#
# Tout événement écarté est journalisé avec son libellé : si Unibet renomme
# « Course » un jour, les logs le diront au lieu de laisser le scraper ne rien
# trouver en silence.
EVENEMENT_COURSE = "course"

# Les qualifications, elles, ne sont pas un événement à parier ici : c'est leur
# **heure** qui nous intéresse, parce que la règle 4.3 y accroche le scraping
# (deux heures après, la grille est définitive et les cotes sont figées).
#
# Le motif est volontairement large et posé sur le libellé brut : Unibet écrit
# « Qualifications », mais rien ne garantit qu'il n'écrira pas « Qualifying »
# demain, ni qu'il ne suffixera pas le libellé. Un motif trop strict ferait
# taire l'heure de tous les Grands Prix sans que rien ne le signale — alors que
# l'absence, elle, est journalisée à chaque fois.
MOTIF_QUALIFICATIONS = re.compile(r"qualif", re.IGNORECASE)

# **Il n'y a plus de repli `date_course - 22h`** (retiré en `0.57.0`).
#
# Il calculait l'heure des qualifications depuis celle de la course, et il
# l'ÉCRASAIT en base : à chaque scraping d'un Grand Prix dont Unibet ne publie
# pas encore le programme — c'est-à-dire le régime normal, constaté sur le
# terrain en août 2026 (`scraper.md` §5) — une heure devinée remplaçait celle
# que la migration 20 a écrite explicitement, relevée sur le calendrier
# officiel. Le symptôme se lisait sur l'écran de détail d'un Grand Prix, qui
# préfère l'heure de la base à celle de la table statique (`seancesDuGp`) : le
# GP d'Italie y aurait annoncé 17h00 pour des qualifications à 16h00.
#
# **Une heure de qualifications se stocke, elle ne se dérive pas.** Quand Unibet
# se tait, la clé n'est simplement pas écrite dans l'upsert, et la valeur déjà
# en base survit — voir `enregistrer_gp`. C'est la règle « on se ferme sur une
# donnée qu'on n'a pas, jamais l'inverse » appliquée à l'écriture plutôt qu'à la
# lecture.

# Rubrique dont dépendent les GP dans l'arborescence d'Unibet, et donc segment
# correspondant dans l'URL d'une page d'événement. Le nœud racine la confirme
# à chaque appel (`path.Category`), mais elle ne change pas d'un GP à l'autre.
CATEGORIE_F1 = "Formule 1"

# Préfixe des identifiants Unibet **inventés**, posés à la main par la migration
# 19 sur les onze Grands Prix de la fin de saison (`manuel-<slug>-2026`). Le vrai
# identifiant n'existe pas tant qu'Unibet n'a pas ouvert la page du Grand Prix,
# c'est-à-dire quelques jours avant la course : il fallait bien donner quelque
# chose à la colonne, qui est `unique` et `not null`.
#
# **C'est le seul endroit du backend qui connaît cette convention**, et elle est
# partagée avec la fonction SQL `adopter_grand_prix` (migration 19), qui fait le
# même geste à la main. Les deux doivent bouger ensemble si le préfixe change.
PREFIXE_MANUEL = "manuel-"

# **Le champ `start` d'Unibet est en UTC**, contrairement à ce que l'étape 4
# avait conclu. Il vaut « 2608231300 » (AAMMJJHHMM) pour le GP des Pays-Bas
# 2026, dont OpenF1 — source autorisée, en UTC — donne le départ à
# `2026-08-23T13:00:00+00:00`, soit 15h00 à Zandvoort. Les quatre séances du
# week-end concordent à la minute près avec OpenF1 :
#
#     Course        start 2608231300   OpenF1 13:00Z
#     Qualification start 2608221400   OpenF1 14:00Z
#     Sprint        start 2608221000   OpenF1 10:00Z
#     Essais 1      start 2608211030   OpenF1 10:30Z
#
# Le lire en heure de Paris le convertissait une seconde fois et **avançait tout
# de deux heures** : la base portait 11:00 UTC, l'accueil affichait 13h pour un
# départ à 15h, et surtout la fermeture des pronostics (départ - 5 min) comme le
# job de résultats (départ + 1h30) tombaient deux heures trop tôt. Ce n'était
# donc pas un défaut d'affichage mais un décalage de toute la programmation.
FUSEAU_UNIBET = ZoneInfo("UTC")

DELAI = httpx.Timeout(20.0, connect=10.0)

# Les pages d'événement sont demandées les unes après les autres, pas en
# parallèle : Unibet n'expose que le GP suivant, la boucle compte donc un ou
# deux tours. Rien à gagner à paralléliser, et une rafale de requêtes est le
# meilleur moyen de se faire refuser.


class ErreurScraper(Exception):
    """Le scraping n'a pas pu aboutir. Le message dit précisément à quelle étape."""


@dataclass
class Cote:
    """Une issue d'un marché, déjà convertie en points."""

    marche: str
    libelle_marche: str
    pilote: str
    valeur: int
    id_outcome_unibet: str


@dataclass
class GrandPrix:
    """Un GP découvert chez Unibet, avec son événement « Course »."""

    id_unibet: str
    nom: str
    id_evenement: str
    date_course: datetime | None

    # Horaires des épreuves de qualification trouvés chez Unibet, en UTC. Une
    # liste et non une valeur : un week-end sprint en compte deux (la
    # qualification du sprint le vendredi, la vraie le samedi), et c'est
    # `resoudre_qualifications` qui tranche laquelle compte.
    qualifications: list[datetime] = field(default_factory=list)

    cotes: list[Cote] = field(default_factory=list)


def slug(texte: str) -> str:
    """Réduit un libellé à sa forme utilisable en identifiant ou en URL.

    Reproduit la fonction du site : minuscules, accents ramenés à la lettre de
    base, tout ce qui n'est ni lettre ni chiffre devient un tiret, les tirets
    consécutifs sont fondus, ceux des extrémités retirés.

    C'est cette fonction qui fabrique les URL des pages d'événement, où le
    moindre écart donne un 404 : « GP Pays Bas » doit donner exactement
    « gp-pays-bas ». Elle sert aussi à nommer les marchés en base.
    """
    sans_accents = "".join(
        caractere
        for caractere in unicodedata.normalize("NFD", texte)
        if unicodedata.category(caractere) != "Mn"
    )
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]", "-", sans_accents.lower())).strip("-")


def en_points(prix: object) -> int | None:
    """Convertit une cote Unibet en points : 2,80 → 28 (règle 4.1).

    Le champ `price` arrive en chaîne à la française (« 2,80 »), parfois avec
    une espace d'affichage. Une valeur illisible renvoie `None` plutôt que de
    faire échouer tout le marché : une issue perdue vaut mieux qu'un GP entier
    non enregistré, et l'appelant la journalise.
    """
    if isinstance(prix, (int, float)) and not isinstance(prix, bool):
        cote = float(prix)
    elif isinstance(prix, str):
        try:
            cote = float(prix.replace(",", ".").replace(" ", "").strip())
        except ValueError:
            return None
    else:
        return None

    # Diviseur 10 depuis la v0.45.0 : une cote de 2,80 vaut 28 points, pas 280.
    # `round` rend un `int` pour un `float` — la règle « les points sont des
    # entiers » ne dépend donc pas du multiplicateur.
    points = round(cote * 10)
    # Une cote nulle ou négative n'existe pas : c'est une donnée abîmée, pas une
    # cote à 0 point. La contrainte `check` de la table dit la même chose.
    return points if points > 0 else None


def date_de_depart(brut: object) -> datetime | None:
    """Lit le champ `start` d'Unibet (« 2608231300 ») et le rend en UTC.

    Le format est AAMMJJHHMM, **déjà en UTC** (voir `FUSEAU_UNIBET`). Le siècle
    est implicite : ces cotes portent sur des courses à venir, « 26 » ne peut
    être que 2026.
    """
    if not isinstance(brut, str) or not re.fullmatch(r"\d{10}", brut):
        return None
    try:
        locale = datetime.strptime(brut, "%y%m%d%H%M").replace(tzinfo=FUSEAU_UNIBET)
    except ValueError:
        return None
    return locale.astimezone(ZoneInfo("UTC"))


def resoudre_qualifications(gp: GrandPrix) -> tuple[datetime | None, str]:
    """Arrête l'heure des qualifications d'un GP, et dit d'où elle vient.

    Renvoie `(date, origine)` avec `origine` valant :

    - `"unibet"` — un événement de qualification a été trouvé chez le bookmaker ;
    - `"inconnue"` — aucun. **On ne devine pas**, et l'appelant n'écrit alors
      rien : la valeur déjà en base survit.

    **La dernière qualification l'emporte, jamais la première.** Un week-end
    sprint en compte deux : la qualification du sprint le vendredi, et la vraie
    qualification le samedi. C'est la seconde qui arrête la grille de départ, et
    donc la seule après laquelle les cotes ont un sens (règle 4.3). Retenir la
    première ferait figer les cotes un jour trop tôt, sur une grille qui n'existe
    pas encore.

    Celles qui tomberaient après le départ sont écartées : ce serait un horaire
    abîmé, et il déclencherait un scraping après la course.

    **Le troisième cas a disparu en `0.57.0`** : `date_course - 22h` était une
    heure DÉRIVÉE de la course, et elle écrasait en base l'heure explicite du
    calendrier officiel à chaque passage. Voir le commentaire de
    `MOTIF_QUALIFICATIONS` ci-dessus. `gp.date_course` n'est donc plus lu ici
    que pour écarter les qualifications postérieures au départ.
    """
    candidates = sorted(gp.qualifications)
    if gp.date_course:
        candidates = [date for date in candidates if date < gp.date_course]

    if candidates:
        return candidates[-1], "unibet"

    return None, "inconnue"


async def jeton(client: httpx.AsyncClient) -> str:
    """Récupère le jeton `X-LVS-HSToken` exigé par l'API, depuis une page publique.

    Le jeton est déposé en clair dans la configuration de la page : aucun
    compte, aucun cookie, aucune reconstitution de signature. Il change à chaque
    déploiement d'Unibet, il est donc relu à chaque scraping plutôt que stocké.
    """
    try:
        reponse = await client.get(PAGE_F1, headers=ENTETES, follow_redirects=True)
    except httpx.HTTPError as erreur:
        raise ErreurScraper(f"Page Formule 1 injoignable ({erreur!r}).") from erreur

    if reponse.status_code != 200:
        raise ErreurScraper(
            f"Page Formule 1 : statut {reponse.status_code} au lieu de 200."
        )

    for motif in MOTIFS_JETON:
        trouve = motif.search(reponse.text)
        if trouve:
            return trouve.group(1)

    raise ErreurScraper(
        "Aucun jeton X-LVS-HSToken dans la page Formule 1. "
        "Unibet a probablement changé le nom de la clé de configuration."
    )


async def _json_lvs(client: httpx.AsyncClient, noeud: str, cle: str) -> dict:
    """Interroge un nœud de l'API Unibet et renvoie sa réponse JSON."""
    url = GABARIT_LVS.format(base=BASE, noeud=noeud)
    try:
        reponse = await client.get(url, headers={**ENTETES, "X-LVS-HSToken": cle})
    except httpx.HTTPError as erreur:
        raise ErreurScraper(f"Nœud {noeud} injoignable ({erreur!r}).") from erreur

    if reponse.status_code != 200:
        raise ErreurScraper(
            f"Nœud {noeud} : statut {reponse.status_code}. "
            f"Réponse : {reponse.text[:200]}"
        )

    try:
        return reponse.json()
    except (JSONDecodeError, ValueError) as erreur:
        raise ErreurScraper(f"Nœud {noeud} : réponse illisible en JSON.") from erreur


async def decouvrir(client: httpx.AsyncClient, cle: str) -> list[GrandPrix]:
    """Découvre les Grands Prix actuellement proposés par Unibet.

    Le nœud racine ne rend que ce qui est ouvert aux paris — le plus souvent un
    seul GP, jamais la saison entière. La hiérarchie se reconstruit par le champ
    `parent` : un événement pointe vers son GP, qui pointe vers la racine.
    """
    donnees = await _json_lvs(client, RACINE_F1, cle)
    items = donnees.get("items")
    if not isinstance(items, dict) or not items:
        raise ErreurScraper(
            "Le nœud racine ne contient aucun `items` exploitable. "
            "La structure de l'API a probablement changé."
        )

    # Les nœuds `p` enfants de la racine sont les GP (et, hélas, le championnat).
    noeuds = {
        identifiant: item
        for identifiant, item in items.items()
        if identifiant.startswith("p") and item.get("parent") == RACINE_F1
    }

    grands_prix: list[GrandPrix] = []
    ecartes: list[str] = []
    # Horaires de qualification relevés au passage, rangés par GP. Ils sont
    # collectés dans la même boucle que les courses, puis rattachés ensuite :
    # rien ne garantit que l'événement « Qualifications » arrive avant l'événement
    # « Course » dans `items`, et un dictionnaire n'a pas d'ordre à respecter.
    qualifications: dict[str, list[datetime]] = {}

    for identifiant, item in items.items():
        if not identifiant.startswith("e"):
            continue

        parent = item.get("parent")
        if parent not in noeuds:
            continue

        libelle = str(item.get("desc") or "")

        if slug(libelle) != EVENEMENT_COURSE:
            if MOTIF_QUALIFICATIONS.search(libelle):
                depart_qualifs = date_de_depart(item.get("start"))
                if depart_qualifs:
                    qualifications.setdefault(parent, []).append(depart_qualifs)
                    continue
                # Un événement de qualification sans horaire lisible n'apporte
                # rien : il est écarté comme les autres, mais nommé dans les logs.
            ecartes.append(f"{libelle!r} (sous {noeuds[parent].get('desc')!r})")
            continue

        nom = str(noeuds[parent].get("desc") or "").strip()
        if not nom:
            ecartes.append(f"{identifiant} : GP sans nom")
            continue

        grands_prix.append(
            GrandPrix(
                id_unibet=parent,
                nom=nom,
                id_evenement=identifiant,
                date_course=date_de_depart(item.get("start")),
            )
        )

    for gp in grands_prix:
        gp.qualifications = sorted(qualifications.get(gp.id_unibet, []))

    if ecartes:
        # Jamais en silence : c'est ici qu'on verrait Unibet renommer « Course ».
        logger.info(
            "[scraper] %d événement(s) écarté(s), non reconnus comme une course : %s",
            len(ecartes),
            " ; ".join(ecartes),
        )

    if not grands_prix:
        raise ErreurScraper(
            f"Aucune course trouvée sous le nœud racine. "
            f"{len(noeuds)} nœud(s) examiné(s), {len(ecartes)} événement(s) écarté(s)."
        )

    return grands_prix


def _etat_ssr(page: str) -> dict:
    """Extrait le bloc de données déposé par le rendu serveur de la page.

    Angular sérialise dans cette balise l'état exact ayant servi au rendu. La
    lire revient à lire une réponse d'API : ce sont les mêmes objets, avec les
    mêmes champs. Aucune balise HTML n'est interprétée.
    """
    trouve = MOTIF_ETAT_SSR.search(page)
    if not trouve:
        raise ErreurScraper("Page d'événement sans bloc `serverApp-state`.")
    try:
        etat = loads(unescape(trouve.group(1)))
    except (JSONDecodeError, ValueError) as erreur:
        raise ErreurScraper("Bloc `serverApp-state` illisible en JSON.") from erreur
    if not isinstance(etat, dict):
        raise ErreurScraper("Bloc `serverApp-state` inattendu.")
    return etat


def url_evenement(gp: GrandPrix, categorie: str) -> str:
    """Reconstruit l'URL de la page d'un événement.

    Unibet exige le libellé exact dans l'URL : le seul identifiant numérique
    renvoie 404, et un mauvais slug aussi. L'identifiant de l'événement y figure
    sans son préfixe `e`.
    """
    # `removeprefix` et non `lstrip('e')` : `lstrip` retire *tous* les « e » de
    # tête, et transformerait un jour un identifiant en un autre, silencieusement.
    return (
        f"{PAGE_F1}/{slug(categorie)}/{slug(gp.nom)}"
        f"/{gp.id_evenement.removeprefix('e')}/{EVENEMENT_COURSE}"
    )


async def marches(client: httpx.AsyncClient, gp: GrandPrix) -> list[Cote]:
    """Récupère tous les marchés d'un GP, et leurs issues converties en points.

    Les marchés sont découverts, jamais supposés : ce qui est renvoyé est ce qui
    est enregistré. Le noyau (vainqueur, podium, écurie gagnante) est presque
    toujours là, les marchés spéciaux vont et viennent selon le circuit.
    """
    url = url_evenement(gp, CATEGORIE_F1)
    try:
        reponse = await client.get(url, headers=ENTETES, follow_redirects=True)
    except httpx.HTTPError as erreur:
        raise ErreurScraper(f"Page de {gp.nom} injoignable ({erreur!r}).") from erreur

    if reponse.status_code != 200:
        # L'URL est journalisée en entier : c'est la première chose à rejouer
        # dans un navigateur quand Unibet change sa façon de nommer ses pages.
        raise ErreurScraper(
            f"Page d'événement introuvable pour {gp.nom} : "
            f"{url} a répondu {reponse.status_code}."
        )

    evenements = _etat_ssr(reponse.text).get("EventsDetail", {}).get("events") or []
    if not evenements:
        raise ErreurScraper(f"Aucun événement dans la page de {gp.nom}.")

    cotes: list[Cote] = []
    illisibles = 0

    for evenement in evenements:
        # La date de la page est plus précise que celle du nœud racine : elle
        # tient compte des reprogrammations annoncées depuis.
        depart = date_de_depart(evenement.get("start"))
        if depart:
            gp.date_course = depart

        for groupe in evenement.get("groupedMarkets") or []:
            for marche in groupe.get("markets") or []:
                libelle = str(marche.get("description") or "").strip()
                nom_marche = slug(libelle)
                if not nom_marche:
                    continue

                for issue in marche.get("outcomes") or []:
                    identifiant = issue.get("id")
                    pilote = str(issue.get("description") or "").strip()
                    points = en_points(issue.get("price"))

                    if identifiant is None or not pilote or points is None:
                        illisibles += 1
                        continue

                    cotes.append(
                        Cote(
                            marche=nom_marche,
                            libelle_marche=libelle,
                            pilote=pilote,
                            valeur=points,
                            # Le préfixe `o` est ajouté pour rester dans la
                            # convention de la section 3.1, où une issue s'écrit
                            # « o701093319 ».
                            id_outcome_unibet=f"o{identifiant}",
                        )
                    )

    if illisibles:
        logger.warning(
            "[scraper] %s : %d issue(s) ignorée(s), cote ou libellé illisible.",
            gp.nom,
            illisibles,
        )

    if not cotes:
        raise ErreurScraper(f"Aucune cote exploitable pour {gp.nom}.")

    return cotes


async def _adopter(gp: GrandPrix, existe_deja: bool) -> dict | None:
    """Fait porter son vrai `id_unibet` à une ligne posée à la main.

    ## Le défaut refermé

    Les onze Grands Prix de la fin de saison sont en base **avant** qu'Unibet
    n'ouvre leur page : la migration 19 les y a posés pour que le calendrier, les
    fiches et les horaires existent toute l'année. Leur `id_unibet` est donc
    inventé (`manuel-<slug>-2026`), et le scraper se rapproche sur `id_unibet` et
    sur rien d'autre — **il ne reconnaissait pas la ligne et en insérait une
    seconde.**

    Le doublon n'est pas cosmétique. La ligne du scraper porte les cotes et un
    **nouvel UUID** ; la ligne manuelle garde l'ancien, donc tout ce qui y pend —
    pronostics, favoris, résultats. L'accueil et les calendriers se rapprochent,
    eux, par le nom du circuit : ils pouvaient tomber sur celle des deux qui n'a
    pas de cotes et annoncer « à venir » un Grand Prix pronosticable. Le geste
    manuel `adopter_grand_prix` existait pour l'éviter, **à condition d'y penser
    le vendredi**, chaque semaine de course. C'est le genre de rendez-vous qu'on
    manque une fois sur douze.

    ## Ce que fait l'adoption

    Un seul `update` : la ligne manuelle prend le vrai `id_unibet`. **Son UUID ne
    bouge pas** — c'est tout l'intérêt, et c'est ce qui garde valides les
    pronostics, les favoris et les adhésions qui s'y rattachent. L'appelant
    continue ensuite son chemin normalement : l'upsert retrouve la ligne par son
    identifiant tout neuf, y écrit `date_course`, `date_qualifications` et les
    cotes, et le job peut la figer.

    **Le rapprochement se fait sur le nom, insensible à la casse et aux
    accents** — `slug()`, qui fond aussi les séparateurs, parce qu'Unibet écrit
    « GP Pays Bas » une semaine et « GP Pays-Bas » la suivante. C'est le seul
    critère disponible : si on avait un identifiant commun, il n'y aurait rien à
    adopter.

    **Deux lignes manuelles de même nom n'en font adopter aucune.** Le cas ne
    devrait pas exister, mais choisir la première venue attacherait les
    pronostics d'un Grand Prix à un autre — mieux vaut le doublon, qui se voit,
    qu'une adoption fausse, qui ne se voit pas. C'est la règle du rapprochement
    des pilotes (`calcul/points.py`), appliquée ici.

    `existe_deja` dit qu'une ligne porte **déjà** le vrai identifiant : le
    scraper est passé avant l'adoption, et le doublon est constitué. Il n'y a
    plus rien à adopter — fusionner deux lignes emporterait en cascade ce qui
    pend à l'une d'elles — mais il y a tout à signaler, et `adopter_grand_prix`
    sait le résorber quand la ligne manuelle est vide.

    Renvoie la ligne adoptée (`id`, `statut`), ou `None` s'il n'y avait rien à
    adopter — le cas de toutes les semaines une fois la saison entamée.
    """
    manuels = await selectionner(
        "grands_prix",
        {
            "id_unibet": f"like.{PREFIXE_MANUEL}*",
            "select": "id,nom,id_unibet,statut",
        },
    )
    if not manuels:
        return None

    cible = slug(gp.nom)
    candidats = [
        ligne for ligne in manuels if slug(str(ligne.get("nom") or "")) == cible
    ]

    if not candidats:
        return None

    if len(candidats) > 1:
        logger.warning(
            "[scraper] %s : %d lignes manuelles portent ce nom (%s). Aucune n'est "
            "adoptée — en choisir une au hasard attacherait les pronostics au "
            "mauvais Grand Prix. À reprendre à la main.",
            gp.nom,
            len(candidats),
            ", ".join(str(ligne.get("id_unibet")) for ligne in candidats),
        )
        return None

    ligne = candidats[0]
    placeholder = str(ligne.get("id_unibet"))

    if existe_deja:
        # Le scraper est arrivé avant l'adoption : les deux lignes coexistent.
        # On ne touche à rien — la ligne manuelle peut porter des pronostics, et
        # `adopter_grand_prix` est la seule à savoir compter ce qui y pend avant
        # de supprimer quoi que ce soit.
        logger.warning(
            "[scraper] %s : une ligne manuelle (« %s ») porte le même nom que la "
            "ligne scrapée (« %s »). Doublon en base — à résorber avec "
            "select public.adopter_grand_prix('%s', '%s'); dans le SQL Editor.",
            gp.nom,
            placeholder,
            gp.id_unibet,
            placeholder,
            gp.id_unibet,
        )
        return None

    # Le filtre porte sur le placeholder autant que sur l'identifiant, pour la
    # raison exacte du `PATCH` de figeage (`jobs/scraper.py`) : si quelqu'un a
    # adopté la ligne entre la lecture et l'écriture, zéro ligne touchée est
    # l'état voulu, pas une panne.
    adoptees = await mettre_a_jour(
        "grands_prix",
        {"id": f"eq.{ligne['id']}", "id_unibet": f"eq.{placeholder}"},
        {"id_unibet": gp.id_unibet},
    )

    if not adoptees:
        logger.info(
            "[scraper] %s : la ligne manuelle « %s » n'était plus là à l'écriture "
            "— adoptée entre-temps par quelqu'un d'autre.",
            gp.nom,
            placeholder,
        )
        return None

    logger.info(
        "[scraper] %s : ligne manuelle adoptée — « %s » devient « %s ». L'UUID %s "
        "ne change pas, les pronostics et favoris déjà rattachés restent valides.",
        gp.nom,
        placeholder,
        gp.id_unibet,
        ligne["id"],
    )
    return adoptees[0]


async def _enregistrer(gp: GrandPrix) -> dict:
    """Écrit un GP et ses cotes en base, sans jamais écraser des cotes figées.

    Trois garde-fous, dans cet ordre :

    - **une ligne manuelle de même nom est adoptée avant tout le reste**
      (`_adopter`), pour que l'écriture qui suit tombe sur elle plutôt que d'en
      créer une seconde. C'est la première chose faite, parce que tout ce qui
      vient après se rapproche par `id_unibet` ;
    - le GP est enregistré **avant** ses cotes. L'inverse est impossible, les
      cotes référencent le GP ;
    - un GP au statut `cotes_figees` garde ses cotes. Après les qualifications,
      elles sont arrêtées et tout le monde pronostique sur les mêmes (règle 4.3) ;
      un scraping tardif ne doit pas les faire bouger sous les pronostics déjà
      saisis.

    Le statut n'est pas transmis à l'upsert : le préciser remettrait à
    « a_venir » un GP déjà figé ou terminé, à chaque passage du scraper.

    **Le statut de la ligne adoptée est lu comme celui de n'importe quelle
    autre** : une ligne manuelle déjà figée à la main garde ses cotes, l'adoption
    ne rouvre rien.
    """
    existants = await selectionner(
        "grands_prix",
        {"id_unibet": f"eq.{gp.id_unibet}", "select": "id,statut", "limit": "1"},
    )

    # L'adoption ne s'interpose que lorsqu'il y a une ligne manuelle de même nom.
    # Elle est tentée à chaque passage et non une fois pour toutes : le scraper
    # ne sait pas quel Grand Prix Unibet lui servira, et une saison entière de
    # lignes manuelles attend d'être adoptée, une par week-end.
    adoptee = await _adopter(gp, existe_deja=bool(existants))
    if adoptee is not None:
        existants = [adoptee]

    fige = bool(existants) and existants[0].get("statut") in ("cotes_figees", "termine")

    ligne = {"id_unibet": gp.id_unibet, "nom": gp.nom}
    if gp.date_course:
        ligne["date_course"] = gp.date_course.isoformat()

    # L'heure des qualifications est écrite même pour un GP figé : c'est une
    # donnée de programme, pas une cote. La refuser à un GP déjà figé priverait
    # l'interface d'un horaire exact qu'Unibet vient d'annoncer.
    #
    # **Et elle n'est écrite QUE si Unibet l'annonce.** Depuis la `0.57.0` il n'y
    # a plus de repli dérivé de `date_course` : quand le bookmaker se tait, la
    # clé est absente de `ligne`, donc l'upsert ne la touche pas et l'heure
    # explicite posée par la migration 20 reste en place. Écrire une heure
    # devinée par-dessus une heure relevée sur le calendrier officiel était le
    # défaut corrigé en `0.61.0` côté écran.
    qualifs, origine = resoudre_qualifications(gp)
    if qualifs:
        ligne["date_qualifications"] = qualifs.isoformat()
        logger.info(
            "[scraper] %s : qualifications annoncées par Unibet à %s "
            "(scraping automatique prévu 2h après).",
            gp.nom,
            qualifs.isoformat(),
        )
    else:
        # WARNING et non INFO, et il faut le lire dans les deux sens : soit
        # l'heure explicite est déjà en base et tout va bien — c'est le cas des
        # onze lignes de la migration 20, et l'adoption automatique fait
        # maintenant tomber le scraping dessus plutôt qu'à côté —, soit la ligne
        # est neuve, un Grand Prix qu'aucune migration n'a posé, et elle restera
        # sans heure, donc sans figeage automatique. C'est le prix assumé du
        # retrait du repli : une heure manquante se voit dans les logs, une
        # heure fausse ne se voyait pas.
        #
        # **Le bouton de pronostics, lui, n'en dépend plus** (v`0.65.0`) :
        # `cotesArretees` ne lit que le statut et l'heure de départ.
        logger.warning(
            "[scraper] %s : aucune épreuve de qualification trouvée chez Unibet "
            "(origine « %s »). Aucune heure n'est écrite — celle déjà en base est "
            "conservée. Si la ligne est neuve, le déclenchement automatique du "
            "scraping restera impossible tant qu'Unibet n'aura pas publié son "
            "programme.",
            gp.nom,
            origine,
        )

    enregistres = await upserter("grands_prix", [ligne], "id_unibet")
    if not enregistres:
        raise ErreurScraper(f"Le GP {gp.nom} n'a pas pu être enregistré.")
    gp_id = enregistres[0]["id"]

    if fige:
        refus = (
            f"{gp.nom} : les cotes sont figées (statut « "
            f"{existants[0].get('statut')} »), elles ne doivent plus bouger "
            f"(règle 4.3). {len(gp.cotes)} cote(s) lue(s) chez Unibet ont été "
            f"ignorées."
        )
        # WARNING et non INFO : le scraping a bien été refusé pour ce GP, et
        # c'est exactement ce qu'on vient chercher dans les logs quand on se
        # demande pourquoi une cote n'a pas bougé.
        logger.warning("[scraper] %s", refus)
        return {
            "nom": gp.nom,
            "gp_id": gp_id,
            "id_unibet": gp.id_unibet,
            "cotes": 0,
            "fige": True,
            "refus": refus,
        }

    lignes = [
        {
            "gp_id": gp_id,
            "marche": cote.marche,
            "libelle_marche": cote.libelle_marche,
            "pilote": cote.pilote,
            "valeur": cote.valeur,
            "id_outcome_unibet": cote.id_outcome_unibet,
        }
        for cote in gp.cotes
    ]

    # L'upsert porte sur (gp_id, id_outcome_unibet) : rejouer le scraping met à
    # jour les cotes existantes au lieu d'en créer de nouvelles. C'est toute
    # l'idempotence demandée par la section 9.
    await upserter("cotes", lignes, "gp_id,id_outcome_unibet")

    # `gp_id` est l'identifiant interne, et il n'est pas décoratif : c'est par
    # lui que le job automatique retrouve, dans ce compte rendu, le Grand Prix
    # qu'il voulait figer. Se fier au nom ne tiendrait pas — Unibet en change
    # l'orthographe d'une semaine à l'autre (« GP Pays Bas », « GP Pays-Bas »),
    # ce qui est déjà la raison d'être de `id_unibet` en base.
    return {
        "nom": gp.nom,
        "gp_id": gp_id,
        "id_unibet": gp.id_unibet,
        "cotes": len(lignes),
        "fige": False,
    }


async def scraper() -> dict:
    """Exécute un scraping complet et renvoie son compte rendu.

    L'échec d'un GP n'interrompt pas les autres : chacun est traité pour
    lui-même, et le compte rendu porte la liste des réussites comme celle des
    échecs. Une panne franche (jeton introuvable, nœud racine muet) lève, parce
    qu'il n'y a alors rien à sauver.
    """
    debut = asyncio.get_event_loop().time()
    logger.info("[scraper] Démarrage.")

    async with httpx.AsyncClient(timeout=DELAI) as client:
        cle = await jeton(client)
        logger.info("[scraper] Jeton obtenu (%d caractères).", len(cle))

        grands_prix = await decouvrir(client, cle)
        logger.info(
            "[scraper] %d Grand(s) Prix découvert(s) : %s",
            len(grands_prix),
            ", ".join(f"{gp.nom} ({gp.id_unibet})" for gp in grands_prix),
        )

        traites: list[dict] = []
        echecs: list[str] = []

        for gp in grands_prix:
            try:
                gp.cotes = await marches(client, gp)
            except ErreurScraper as erreur:
                # Un GP qui échoue est journalisé et abandonné, les suivants
                # continuent. Surtout : rien n'est écrit pour lui, donc ses
                # cotes déjà en base restent intactes.
                logger.error("[scraper] %s : %s", gp.nom, erreur)
                echecs.append(f"{gp.nom} : {erreur}")
                continue

            marches_vus = sorted({cote.libelle_marche for cote in gp.cotes})
            logger.info(
                "[scraper] %s — %d marché(s), %d cote(s) : %s",
                gp.nom,
                len(marches_vus),
                len(gp.cotes),
                ", ".join(marches_vus),
            )

            try:
                traites.append(await _enregistrer(gp))
            except (ErreurSupabase, ErreurScraper) as erreur:
                logger.exception("[scraper] Enregistrement de %s impossible.", gp.nom)
                echecs.append(f"{gp.nom} (enregistrement) : {erreur}")

    duree = round(asyncio.get_event_loop().time() - debut, 1)
    rapport = {
        "grands_prix": traites,
        "echecs": echecs,
        "cotes_enregistrees": sum(gp["cotes"] for gp in traites),
        "duree_secondes": duree,
    }
    logger.info(
        "[scraper] Terminé en %ss — %d GP traité(s), %d cote(s) enregistrée(s), %d échec(s).",
        duree,
        len(traites),
        rapport["cotes_enregistrees"],
        len(echecs),
    )
    return rapport
