"""Récupération des résultats de course chez OpenF1.

API gratuite, sans clé, documentée en section 3.2 du CLAUDE.md :
`https://api.openf1.org/v1/`.

Trois écarts entre la section 3.2 et ce que l'API rend réellement. Ils ont été
constatés en l'interrogeant, ils expliquent l'essentiel du code ci-dessous, et
la section 3.2 n'a pas été réécrite : elle reste le cahier des charges, ce qui
suit dit ce que la réalité y oppose.

1. **On interroge par `session_key`, jamais par `meeting_key` seul.** Un
   *meeting* est un week-end entier : essais libres, qualifications, sprint,
   course. `/session_result?meeting_key=1264` rend les cinq sessions mélangées,
   donc plusieurs lignes par pilote et un classement qui n'a aucun sens. Pire,
   la ligne de qualification porte un `gap_to_leader` de type **liste**
   (`[0.0, 0.0, 0.0]`, un temps par segment Q1/Q2/Q3) — un quatrième type que la
   section 3.2 ne mentionne pas, et qui disparaît dès qu'on filtre sur la
   session de course. C'est `session_de_course()` qui fait cette résolution.

2. **`dnf: true` n'implique pas `position: null`.** La section 3.2 dit que les
   pilotes abandonnés ont une position nulle ; c'est vrai des abandons précoces,
   pas de ceux qui restent classés. Au GP des Pays-Bas 2025, Norris abandonne au
   64ᵉ des 72 tours et reste **classé 18ᵉ** avec `dnf: true`. Les deux champs
   sont donc lus indépendamment : `dnf` dit l'abandon, `position` dit le
   classement, et l'un n'annule pas l'autre.

3. **`points` est un flottant** (`25.0`), pas un entier. Ce sont les points du
   championnat du monde FIA, jamais ceux de l'application (règle 4.1).

Le module ne fait que **récupérer et conserver**. Il ne juge aucun pronostic :
c'est le rôle de `app/calcul/points.py`, qui travaille à partir du JSON
enregistré ici et peut donc être rejoué sans rappeler l'API.
"""

import asyncio
import logging
from datetime import UTC, datetime, timedelta
from typing import Any

import httpx

# Même logger que le reste du backend : sous Railway, `uvicorn.error` est le
# seul à disposer d'un handler. Un logger maison écrirait dans le vide.
logger = logging.getLogger("uvicorn.error")

BASE = "https://api.openf1.org/v1"

DELAI = httpx.Timeout(30.0, connect=10.0)

# OpenF1 refuse au-delà de 3 requêtes par seconde (`429 Rate limit exceeded`).
# Une récupération complète en enchaîne huit : sans cette pause, les trois
# dernières sont refusées. 0,4 s tient large sous la limite, et une récupération
# ne se produit qu'une fois par Grand Prix.
PAUSE_ENTRE_APPELS = 0.4
TENTATIVES = 4

# Écart maximal toléré entre l'heure de départ annoncée par Unibet et celle de
# la session OpenF1 retenue. Large à dessein : un GP peut être décalé de
# plusieurs heures (pluie), et Unibet peut annoncer l'heure locale de la
# cérémonie plutôt que celle du feu vert. Au-delà, on refuse de deviner —
# rapprocher le mauvais week-end noterait toute une journée de pronostics sur
# les résultats d'une autre course.
ECART_MAXIMAL = timedelta(hours=36)

# `/laps` rend une ligne par pilote et par tour : 654 Ko pour un Grand Prix, à
# transporter à chaque lecture de `donnees_brutes`. Seul le meilleur tour de
# chaque pilote sert (règle 4.4, marché « meilleur tour »), et c'est lui seul
# qui est conservé. La réduction est faite ici, jamais au moment du calcul :
# `donnees_brutes` doit contenir tout ce dont le calcul a besoin.
CHAMPS_TOUR = ("driver_number", "lap_number", "lap_duration", "date_start")


class ErreurOpenF1(Exception):
    """La récupération n'a pas abouti. Le message dit à quelle étape."""


class ResultatsIndisponibles(ErreurOpenF1):
    """La course n'a pas encore de résultats publiés.

    Distinguée d'une panne : ce n'est pas une erreur, c'est l'état normal dans
    l'heure et demie qui suit un départ. Le job réessaie, là où il abandonnerait
    sur une `ErreurOpenF1` ordinaire.
    """


async def _appeler(
    client: httpx.AsyncClient, ressource: str, parametres: dict[str, Any]
) -> list[dict]:
    """Interroge un endpoint OpenF1 et rend sa liste d'objets.

    **OpenF1 limite à 3 requêtes par seconde** et répond `429` au-delà — ce
    n'est pas documenté en section 3.2, c'est constaté : une récupération
    enchaîne six appels, et les trois derniers étaient refusés. La cadence est
    donc espacée, et un `429` est réessayé avec une attente croissante plutôt
    que remonté comme une panne. Sans cela, chaque récupération échouerait à
    mi-parcours et le job repasserait toutes les cinq minutes sur le même mur.
    """
    url = f"{BASE}/{ressource}"

    for tentative in range(TENTATIVES):
        # Cadence : jamais deux appels dans la même fraction de seconde.
        await asyncio.sleep(PAUSE_ENTRE_APPELS)

        try:
            reponse = await client.get(url, params=parametres)
        except httpx.HTTPError as erreur:
            raise ErreurOpenF1(f"{ressource} injoignable ({erreur!r}).") from erreur

        if reponse.status_code == 429 and tentative < TENTATIVES - 1:
            attente = PAUSE_ENTRE_APPELS * (2 ** (tentative + 1))
            logger.warning(
                "[openf1] %s : quota dépassé (429), nouvel essai dans %.1fs.",
                ressource,
                attente,
            )
            await asyncio.sleep(attente)
            continue

        if reponse.status_code != 200:
            raise ErreurOpenF1(
                f"{ressource} : statut {reponse.status_code}. "
                f"Réponse : {reponse.text[:200]}"
            )

        try:
            donnees = reponse.json()
        except ValueError as erreur:
            raise ErreurOpenF1(f"{ressource} : réponse illisible en JSON.") from erreur

        if not isinstance(donnees, list):
            raise ErreurOpenF1(
                f"{ressource} : liste attendue, reçu {type(donnees).__name__}."
            )

        return donnees

    raise ErreurOpenF1(f"{ressource} : quota OpenF1 toujours dépassé après {TENTATIVES} essais.")


def _en_datetime(brut: object) -> datetime | None:
    """Lit une date ISO d'OpenF1 ou de PostgREST, toujours rendue en UTC."""
    if not isinstance(brut, str) or not brut.strip():
        return None
    try:
        lue = datetime.fromisoformat(brut.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return lue.replace(tzinfo=UTC) if lue.tzinfo is None else lue.astimezone(UTC)


async def session_de_course(
    client: httpx.AsyncClient, nom_gp: str, depart: datetime
) -> dict:
    """Retrouve la session « Course » d'OpenF1 correspondant à un GP en base.

    Le rapprochement se fait sur la **date**, pas sur le nom. Unibet écrit « GP
    Pays Bas », OpenF1 « Dutch Grand Prix » : aucune correspondance textuelle ne
    tiendrait sur une saison entière, et une table de correspondance codée en
    dur reviendrait à figer le calendrier — exactement ce que la section 3.1
    interdit au scraper de faire. Deux Grands Prix ne partagent jamais la même
    date : la course est le seul événement de son week-end à ce créneau.

    Rien n'est deviné au-delà de `ECART_MAXIMAL` : mieux vaut ne pas noter un GP
    que le noter sur les résultats d'un autre.
    """
    sessions = await _appeler(
        client,
        "sessions",
        {"year": depart.year, "session_type": "Race"},
    )

    # Un GP peut se courir le 1er janvier d'une année et avoir été annoncé la
    # précédente : la saison voisine est balayée aussi, à peu de frais.
    if depart.month == 1:
        sessions += await _appeler(
            client, "sessions", {"year": depart.year - 1, "session_type": "Race"}
        )

    candidates: list[tuple[timedelta, dict]] = []
    for session in sessions:
        debut = _en_datetime(session.get("date_start"))
        if debut is None:
            continue
        candidates.append((abs(debut - depart), session))

    if not candidates:
        raise ErreurOpenF1(
            f"Aucune session de course OpenF1 pour l'année {depart.year}."
        )

    ecart, session = min(candidates, key=lambda couple: couple[0])

    if ecart > ECART_MAXIMAL:
        raise ErreurOpenF1(
            f"Aucune course OpenF1 proche de {nom_gp} ({depart.isoformat()}). "
            f"La plus proche est « {session.get('meeting_key')} / "
            f"{session.get('country_name')} » à {ecart} d'écart, au-delà des "
            f"{ECART_MAXIMAL} tolérées."
        )

    # `is_cancelled` est renseigné par OpenF1 et vaudra `true` pour un GP annulé.
    # Il n'est pas exploité ici — la règle 4.7 (effacement des pronostics)
    # n'est pas encore implémentée — mais il est journalisé pour que le cas se
    # voie dans les logs plutôt que de passer pour une course sans résultat.
    if session.get("is_cancelled"):
        logger.warning(
            "[openf1] %s : la session OpenF1 %s est marquée annulée.",
            nom_gp,
            session.get("session_key"),
        )

    logger.info(
        "[openf1] %s → session %s (%s, %s), écart %s.",
        nom_gp,
        session.get("session_key"),
        session.get("country_name"),
        session.get("date_start"),
        ecart,
    )
    return session


# Nom de la session de qualification chez OpenF1. `session_type=Qualifying`
# couvre aussi « Sprint Qualifying » : c'est le NOM qui désigne celle du samedi,
# la seule qui attribue la pole du Grand Prix.
SESSION_QUALIFICATION = "Qualifying"


def _meeting_de(donnees: dict) -> object:
    """Le `meeting_key` du week-end, lu dans la session ou dans le classement."""
    session = donnees.get("session") or {}
    if session.get("meeting_key") is not None:
        return session["meeting_key"]
    for ligne in donnees.get("session_result") or []:
        if isinstance(ligne, dict) and ligne.get("meeting_key") is not None:
            return ligne["meeting_key"]
    return None


async def _qualification(client: httpx.AsyncClient, nom_gp: str, meeting: object) -> list[dict]:
    """Le `session_result` des qualifications du même week-end.

    Lève `ErreurOpenF1` si la session est introuvable ou sans classement :
    l'appelant décide si c'est bloquant (ça ne l'est jamais — seul le marché
    « triplé » en dépend, et il reste en attente sans elle).
    """
    if meeting is None:
        raise ErreurOpenF1(f"{nom_gp} : aucun `meeting_key` pour retrouver les qualifications.")

    sessions = await _appeler(
        client, "sessions", {"meeting_key": meeting, "session_name": SESSION_QUALIFICATION}
    )
    if len(sessions) != 1 or sessions[0].get("session_key") is None:
        raise ErreurOpenF1(
            f"{nom_gp} : {len(sessions)} session(s) « {SESSION_QUALIFICATION} » pour "
            f"le meeting {meeting}, une seule attendue."
        )

    classement = await _appeler(
        client, "session_result", {"session_key": sessions[0]["session_key"]}
    )
    if not any(ligne.get("position") == 1 for ligne in classement):
        raise ErreurOpenF1(
            f"{nom_gp} : qualifications {sessions[0]['session_key']} sans premier classé."
        )
    return classement


async def completer_qualification(nom_gp: str, donnees: dict) -> bool:
    """Ajoute les qualifications à des `donnees_brutes` qui ne les ont pas.

    Rend `True` si `donnees` a été complété — à l'appelant de le réécrire en
    base. Sert aux GP récupérés avant la `0.77.0` (Bakou compris), et à ceux
    dont la première lecture des qualifications a échoué. Un échec est
    journalisé et rend `False` : les pronostics qui en dépendent restent en
    attente, rien d'autre n'est bloqué.
    """
    if donnees.get("qualification"):
        return False
    try:
        async with httpx.AsyncClient(timeout=DELAI) as client:
            donnees["qualification"] = await _qualification(
                client, nom_gp, _meeting_de(donnees)
            )
    except ErreurOpenF1 as erreur:
        logger.warning("[openf1] %s : qualifications indisponibles (%s).", nom_gp, erreur)
        return False
    logger.info(
        "[openf1] %s : qualifications ajoutées (%d ligne(s)).",
        nom_gp,
        len(donnees["qualification"]),
    )
    return True


def _index_pilotes(pilotes: list[dict]) -> dict[str, dict]:
    """Construit l'index { numéro de voiture → nom, écurie } du classement.

    Les clés sont des **chaînes** : c'est ce que `donnees_brutes->'pilotes'->…`
    attend côté SQL, un objet JSON n'ayant pas de clé numérique.
    """
    index: dict[str, dict] = {}
    for pilote in pilotes:
        numero = pilote.get("driver_number")
        if numero is None:
            continue
        index[str(numero)] = {
            "nom": (pilote.get("full_name") or pilote.get("broadcast_name") or "").strip(),
            "prenom": (pilote.get("first_name") or "").strip(),
            "nom_famille": (pilote.get("last_name") or "").strip(),
            "acronyme": (pilote.get("name_acronym") or "").strip(),
            "equipe": (pilote.get("team_name") or "").strip(),
        }
    return index


async def engages(nom_gp: str, reference: datetime) -> dict[str, dict]:
    """Les pilotes engagés au GP, lus dans `/drivers` de ses qualifications.

    Appelé au figeage des cotes, deux heures après les qualifications : la course
    n'a pas encore de `/drivers`, la qualification si. C'est la liste des engagés
    **de ce week-end**, baquets du jour compris — jamais la grille statique.

    La session est retrouvée par sa date, comme la course (`session_de_course`) :
    la qualification (`session_name = "Qualifying"`, pas celle du sprint) la plus
    proche de `reference` — l'heure des qualifications en base, à défaut celle
    du départ —, refusée au-delà de `ECART_MAXIMAL`.

    Rend l'index `{numéro: identité}` de `_index_pilotes`, celui que
    `calcul.points.correspondance` consomme.
    """
    async with httpx.AsyncClient(timeout=DELAI) as client:
        sessions = await _appeler(
            client,
            "sessions",
            {"year": reference.year, "session_name": SESSION_QUALIFICATION},
        )
        candidates = [
            (abs(debut - reference), session)
            for session in sessions
            if (debut := _en_datetime(session.get("date_start"))) is not None
            and session.get("session_key") is not None
        ]
        if not candidates:
            raise ErreurOpenF1(f"{nom_gp} : aucune qualification OpenF1 en {reference.year}.")

        ecart, session = min(candidates, key=lambda couple: couple[0])
        if ecart > ECART_MAXIMAL:
            raise ErreurOpenF1(
                f"{nom_gp} : la qualification OpenF1 la plus proche "
                f"({session.get('country_name')}, {session.get('date_start')}) est à "
                f"{ecart}, au-delà des {ECART_MAXIMAL} tolérées."
            )

        pilotes = await _appeler(client, "drivers", {"session_key": session["session_key"]})

    index = _index_pilotes(pilotes)
    if not index:
        raise ErreurOpenF1(
            f"{nom_gp} : `/drivers` vide pour la qualification {session['session_key']}."
        )
    logger.info(
        "[openf1] %s : %d engagé(s), qualification %s (%s).",
        nom_gp,
        len(index),
        session["session_key"],
        session.get("date_start"),
    )
    return index


def _meilleurs_tours(tours: list[dict]) -> list[dict]:
    """Réduit `/laps` au meilleur tour de chaque pilote.

    Un tour sans `lap_duration` (tour de sortie des stands, tour interrompu)
    n'est pas un tour chronométré : il est écarté plutôt que compté comme un
    temps nul, ce qui donnerait le meilleur tour au premier pilote entré aux
    stands.
    """
    meilleurs: dict[int, dict] = {}
    for tour in tours:
        numero = tour.get("driver_number")
        duree = tour.get("lap_duration")
        if numero is None or not isinstance(duree, (int, float)) or duree <= 0:
            continue
        actuel = meilleurs.get(numero)
        if actuel is None or duree < actuel["lap_duration"]:
            meilleurs[numero] = {champ: tour.get(champ) for champ in CHAMPS_TOUR}
    return sorted(meilleurs.values(), key=lambda tour: tour["lap_duration"])


async def recuperer(nom_gp: str, depart: datetime) -> dict:
    """Récupère tout ce qu'il faut pour noter un GP, et le rend d'un bloc.

    L'objet renvoyé est celui qui part dans `resultats_gp.donnees_brutes`. Il
    contient **tout ce dont le calcul a besoin** : un validateur ajouté plus tard
    doit pouvoir être rejoué sur cet objet, sans rappeler OpenF1.

    Lève `ResultatsIndisponibles` tant que la course n'a pas de classement — ce
    n'est pas une panne, c'est l'état normal pendant la course, et c'est le
    signal que le job attend pour réessayer cinq minutes plus tard.
    """
    async with httpx.AsyncClient(timeout=DELAI) as client:
        session = await session_de_course(client, nom_gp, depart)
        cle = session.get("session_key")
        if cle is None:
            raise ErreurOpenF1(f"Session OpenF1 sans `session_key` pour {nom_gp}.")

        filtre = {"session_key": cle}

        classement = await _appeler(client, "session_result", filtre)
        if not classement:
            raise ResultatsIndisponibles(
                f"{nom_gp} : `session_result` est encore vide pour la session {cle}."
            )

        # Un classement où personne n'a de position n'est pas un classement :
        # OpenF1 publie parfois les lignes avant de les remplir. Attendre est
        # préférable à noter tout le monde perdant.
        if not any(ligne.get("position") is not None for ligne in classement):
            raise ResultatsIndisponibles(
                f"{nom_gp} : {len(classement)} ligne(s) de résultat, aucune position "
                f"renseignée. Les résultats ne sont pas encore consolidés."
            )

        pilotes = await _appeler(client, "drivers", filtre)
        controle = await _appeler(client, "race_control", filtre)
        tours = await _appeler(client, "laps", filtre)

        # `/starting_grid` rend une liste vide sur les saisons antérieures. Son
        # échec ne doit pas emporter la récupération : aucun marché validé
        # aujourd'hui n'en dépend, et le conserver prépare la pole position.
        try:
            grille = await _appeler(client, "starting_grid", filtre)
        except ErreurOpenF1 as erreur:
            logger.warning("[openf1] %s : grille de départ indisponible (%s).", nom_gp, erreur)
            grille = []

        # Les qualifications du même week-end : la pole du marché « triplé ».
        # Comme la grille, leur échec n'emporte pas la récupération —
        # `completer_qualification` réessaiera au prochain passage.
        try:
            qualification = await _qualification(client, nom_gp, session.get("meeting_key"))
        except ErreurOpenF1 as erreur:
            logger.warning("[openf1] %s : qualifications indisponibles (%s).", nom_gp, erreur)
            qualification = []

    donnees = {
        "source": "openf1",
        "recupere_le": datetime.now(UTC).isoformat(),
        "session": session,
        "session_result": classement,
        "drivers": pilotes,
        "race_control": controle,
        "starting_grid": grille,
        "qualification": qualification,
        # Réduit au meilleur tour par pilote : voir CHAMPS_TOUR ci-dessus.
        "laps": _meilleurs_tours(tours),
        "pilotes": _index_pilotes(pilotes),
    }

    logger.info(
        "[openf1] %s : %d ligne(s) de classement, %d pilote(s), %d message(s) de "
        "direction de course, %d meilleur(s) tour(s).",
        nom_gp,
        len(classement),
        len(pilotes),
        len(controle),
        len(donnees["laps"]),
    )
    return donnees
