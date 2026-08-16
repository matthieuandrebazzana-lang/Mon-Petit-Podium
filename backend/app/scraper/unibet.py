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
   `float(price)` lève, un `price * 100` concatène. C'est `en_points()` qui
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
from datetime import datetime, timedelta
from html import unescape
from json import JSONDecodeError, loads
from zoneinfo import ZoneInfo

import httpx

from app.supabase_client import ErreurSupabase, selectionner, upserter

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
# retomber tous les Grands Prix sur le repli sans que rien ne le signale — alors
# que le repli, lui, est journalisé à chaque fois.
MOTIF_QUALIFICATIONS = re.compile(r"qualif", re.IGNORECASE)

# Repli quand Unibet n'annonce pas ses qualifications : elles se courent le
# samedi après-midi pour une course le dimanche après-midi, soit 22 heures avant
# le départ. Ce n'est pas une devinette élégante, c'est un plancher raisonnable —
# et le scraping se déclenchera deux heures après, donc le samedi en fin de
# journée. Le cas est journalisé pour qu'il ne passe jamais inaperçu.
REPLI_QUALIFICATIONS = timedelta(hours=22)

# Rubrique dont dépendent les GP dans l'arborescence d'Unibet, et donc segment
# correspondant dans l'URL d'une page d'événement. Le nœud racine la confirme
# à chaque appel (`path.Category`), mais elle ne change pas d'un GP à l'autre.
CATEGORIE_F1 = "Formule 1"

# Unibet écrit ses horaires en heure de Paris, sans jamais le dire : le champ
# `start` vaut « 2608231500 » pour un départ annoncé à 15h00. Les stocker tels
# quels en UTC décalerait toute la programmation des jobs de l'étape 6 (fermeture
# des pronostics 5 min avant le départ, résultats 1h30 après) d'une ou deux
# heures selon la saison.
FUSEAU_UNIBET = ZoneInfo("Europe/Paris")

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
    """Convertit une cote Unibet en points : 2,80 → 280 (règle 4.1).

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

    points = round(cote * 100)
    # Une cote nulle ou négative n'existe pas : c'est une donnée abîmée, pas une
    # cote à 0 point. La contrainte `check` de la table dit la même chose.
    return points if points > 0 else None


def date_de_depart(brut: object) -> datetime | None:
    """Lit le champ `start` d'Unibet (« 2608231500 ») et le rend en UTC.

    Le format est AAMMJJHHMM, en heure de Paris. Le siècle est implicite : ces
    cotes portent sur des courses à venir, « 26 » ne peut être que 2026.
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
    - `"repli"`  — aucun, l'heure est déduite de `date_course - 22h` ;
    - `"inconnue"` — ni l'un ni l'autre : le GP n'a même pas d'heure de course.

    **La dernière qualification l'emporte, jamais la première.** Un week-end
    sprint en compte deux : la qualification du sprint le vendredi, et la vraie
    qualification le samedi. C'est la seconde qui arrête la grille de départ, et
    donc la seule après laquelle les cotes ont un sens (règle 4.3). Retenir la
    première ferait figer les cotes un jour trop tôt, sur une grille qui n'existe
    pas encore.

    Celles qui tomberaient après le départ sont écartées : ce serait un horaire
    abîmé, et il déclencherait un scraping après la course.
    """
    candidates = sorted(gp.qualifications)
    if gp.date_course:
        candidates = [date for date in candidates if date < gp.date_course]

    if candidates:
        return candidates[-1], "unibet"

    if gp.date_course:
        return gp.date_course - REPLI_QUALIFICATIONS, "repli"

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


async def _enregistrer(gp: GrandPrix) -> dict:
    """Écrit un GP et ses cotes en base, sans jamais écraser des cotes figées.

    Deux garde-fous, dans cet ordre :

    - le GP est enregistré **avant** ses cotes. L'inverse est impossible, les
      cotes référencent le GP ;
    - un GP au statut `cotes_figees` garde ses cotes. Après les qualifications,
      elles sont arrêtées et tout le monde pronostique sur les mêmes (règle 4.3) ;
      un scraping tardif ne doit pas les faire bouger sous les pronostics déjà
      saisis.

    Le statut n'est pas transmis à l'upsert : le préciser remettrait à
    « a_venir » un GP déjà figé ou terminé, à chaque passage du scraper.
    """
    existants = await selectionner(
        "grands_prix",
        {"id_unibet": f"eq.{gp.id_unibet}", "select": "id,statut", "limit": "1"},
    )
    fige = bool(existants) and existants[0].get("statut") in ("cotes_figees", "termine")

    ligne = {"id_unibet": gp.id_unibet, "nom": gp.nom}
    if gp.date_course:
        ligne["date_course"] = gp.date_course.isoformat()

    # L'heure des qualifications est écrite même pour un GP figé : c'est une
    # donnée de programme, pas une cote. La refuser à un GP déjà figé priverait
    # l'interface d'un horaire exact qu'Unibet vient d'annoncer.
    qualifs, origine = resoudre_qualifications(gp)
    if qualifs:
        ligne["date_qualifications"] = qualifs.isoformat()
        if origine == "unibet":
            logger.info(
                "[scraper] %s : qualifications annoncées par Unibet à %s "
                "(scraping automatique prévu 2h après).",
                gp.nom,
                qualifs.isoformat(),
            )
        else:
            logger.warning(
                "[scraper] %s : aucune épreuve de qualification trouvée chez Unibet. "
                "Repli sur date_course - %s, soit %s.",
                gp.nom,
                REPLI_QUALIFICATIONS,
                qualifs.isoformat(),
            )
    else:
        logger.warning(
            "[scraper] %s : ni qualifications ni heure de course connues. "
            "Le déclenchement automatique du scraping restera impossible pour ce "
            "Grand Prix tant qu'Unibet n'aura pas publié son programme.",
            gp.nom,
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
