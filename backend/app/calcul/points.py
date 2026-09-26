"""Validation des pronostics et calcul des points — étape 6.

Le module travaille **uniquement** sur le JSON conservé dans
`resultats_gp.donnees_brutes` : il n'appelle jamais OpenF1. C'est ce qui rend le
calcul rejouable des semaines après la course, pour corriger un validateur ou en
ajouter un.

Trois principes gouvernent tout ce qui suit.

**1. Un marché qu'on ne sait pas valider ne vaut jamais 0.** Il rend `None`, et
le pronostic reste à `points_gagnes = NULL`. Mettre 0 reviendrait à déclarer
perdant un pari qu'on n'a pas su juger, sans que rien ne le signale — le joueur
verrait un échec là où il y a une lacune du code. `None` se voit dans les logs,
s'affiche « en attente » à l'écran, et se rattrape par un second passage une
fois le validateur écrit. Les marchés Unibet varient d'un GP à l'autre
(section 3.1) : ce cas n'est pas une hypothèse d'école, il se produira.

**2. Un pronostic raté vaut 0, jamais NULL.** C'est la contrepartie du point
précédent, et c'est ce qui distingue « perdu » de « pas encore jugé ».

**3. Les cotes viennent de la base, jamais du calcul.** Ce qu'un pronostic
rapporte, c'est la valeur figée au moment du scraping (règle 4.3). Rien ici ne
recalcule une cote.

Le rapprochement entre les noms Unibet (« M.Verstappen ») et les pilotes OpenF1
(`driver_number`) est le point le plus fragile du module : il est isolé dans
`Course.pilote_du_libelle`, et toute ambiguïté y est refusée plutôt que
tranchée au hasard.
"""

import logging
import math
import re
import unicodedata
from collections.abc import Sequence
from dataclasses import dataclass, field

from app.calcul import pilotes as grille

logger = logging.getLogger("uvicorn.error")

# Slugs des marchés obligatoires. Ils doublent les constantes de
# `app/api/routes/pronostics.py` et de `frontend/src/lib/pronostics.js` : si
# Unibet renomme un de ces marchés, les trois doivent bouger ensemble.
MARCHE_VAINQUEUR = "vainqueur"
MARCHE_PODIUM = "podium"

# Réponses des marchés binaires (safety car, drapeau rouge…), tels qu'Unibet les
# libelle côté issue.
OUI = {"oui", "yes"}
NON = {"non", "no"}


def normaliser(texte: object) -> str:
    """Réduit un libellé à ses seules lettres et chiffres, sans accents.

    « M.Verstappen » et « Max VERSTAPPEN » se ramènent respectivement à
    « mverstappen » et « maxverstappen » — deux clés distinctes, toutes deux
    indexées. C'est la seule normalisation du module : tout rapprochement de nom
    passe par ici.
    """
    if not isinstance(texte, str):
        return ""
    sans_accents = "".join(
        caractere
        for caractere in unicodedata.normalize("NFD", texte)
        if unicodedata.category(caractere) != "Mn"
    )
    return re.sub(r"[^a-z0-9]", "", sans_accents.lower())


# --------------------------------------------------------------------------- #
#  Lecture du résultat de course
# --------------------------------------------------------------------------- #


@dataclass
class Ligne:
    """Une ligne de `session_result`, débarrassée de ses pièges de typage."""

    numero: int
    position: int | None
    tours: int
    points_fia: int
    abandon: bool
    non_partant: bool
    disqualifie: bool
    # Écart au leader, en secondes. `None` pour le leader lui-même (OpenF1 y met
    # `null`) et pour tout ce qui n'est pas lisible ; `math.inf` pour un pilote
    # doublé, dont l'écart est plus grand que n'importe quel intervalle proposé.
    # Le champ est de type mixte chez OpenF1 : tout est absorbé par `_secondes`.
    ecart_leader: float | None = None

    @property
    def classe(self) -> bool:
        """Vrai si le pilote a un rang au classement final.

        `abandon` n'est PAS testé ici, et c'est délibéré : un pilote peut
        abandonner et rester classé s'il a couvert assez de distance. Au GP des
        Pays-Bas 2025, Norris abandonne au 64ᵉ tour et finit 18ᵉ. Un « top 10 »
        se juge sur la position, un « abandon » sur `abandon` : les deux
        questions sont indépendantes.
        """
        return self.position is not None


@dataclass
class Course:
    """Tout ce qu'un validateur peut avoir à consulter, déjà mis en forme."""

    lignes: dict[int, Ligne] = field(default_factory=dict)
    pilotes: dict[int, dict] = field(default_factory=dict)
    safety_car: bool = False
    virtual_safety_car: bool = False
    drapeau_rouge: bool = False
    meilleur_tour: int | None = None
    # Le poleman, lu dans le classement des qualifications (`qualification` de
    # `donnees_brutes`). `None` quand la session n'a pas été récupérée : les
    # GP courus avant la `0.77.0` ne l'ont pas, jusqu'au prochain passage du job.
    pole: int | None = None

    # Index de rapprochement, construits une fois pour toutes.
    _par_nom: dict[str, int] = field(default_factory=dict)
    _par_equipe: dict[str, str] = field(default_factory=dict)

    def par_position(self, position: int) -> Ligne | None:
        for ligne in self.lignes.values():
            if ligne.position == position:
                return ligne
        return None

    def voitures_de(self, equipe: str) -> tuple[int, ...]:
        """Les numéros qu'une écurie a engagés à CE Grand Prix.

        **La paire se lit dans les résultats, jamais dans une table statique**,
        et c'est la seule lecture qui ne se trompe pas : les baquets bougent en
        cours de saison. Au GP d'Espagne 2026, OpenF1 place Lawson chez Red Bull
        Racing et Tsunoda chez Racing Bulls — deux affectations que la grille de
        `calcul/pilotes.py` a fini par enregistrer, mais toujours **après** la
        course qui les a révélées. Juger « Red Bull : les 2 voitures
        dans le top 10 » sur la grille aurait répondu « Non » là où la course dit
        « Oui », et un pronostic raté à tort vaut `0`, qui ne se rattrape jamais
        (§4 de `metier.md`).

        Seuls les pilotes **ayant une ligne de classement** sont comptés : c'est
        la liste des voitures qui ont pris part à la course, la seule dont un
        marché « les 2 voitures » parle.
        """
        cle = normaliser(equipe)
        if not cle:
            return ()
        return tuple(
            sorted(
                numero
                for numero in self.lignes
                if normaliser((self.pilotes.get(numero) or {}).get("equipe")) == cle
            )
        )

    def ecart_du_vainqueur(self) -> float | None:
        """L'écart entre le vainqueur et son dauphin, en secondes.

        **Il se lit sur la ligne du DEUXIÈME, pas sur celle du premier.**
        `gap_to_leader` dit « de combien ce pilote est derrière le leader » : sur
        la ligne du leader il vaut `null`, ce qui est correct et n'est pas une
        donnée manquante. C'est le seul champ dont dépend le marché « écart du
        gagnant », et c'est la raison pour laquelle il entre enfin dans `Ligne`.

        `None` quand il n'y a pas de deuxième, ou quand son écart n'est pas
        lisible : le marché reste alors non jugé, jamais perdu.
        """
        second = self.par_position(2)
        if second is None:
            return None
        return second.ecart_leader

    def pilote_du_libelle(self, libelle: str) -> int | None:
        """Retrouve le numéro de voiture derrière un libellé Unibet.

        Rend `None` si le nom ne correspond à personne **ou** s'il correspond à
        plusieurs pilotes. Deux pilotes de même nom de famille (les frères
        Schumacher en leur temps, Verstappen père et fils dans une base
        historique) rendraient « Verstappen » ambigu : la clé est alors retirée
        de l'index, et le pronostic reste non validé plutôt que d'être attribué
        au mauvais pilote.
        """
        return self._par_nom.get(normaliser(libelle))

    def equipe_du_libelle(self, libelle: str) -> str | None:
        """Retrouve une écurie OpenF1 derrière un libellé Unibet.

        Unibet écrit « Red Bull » là où OpenF1 dit « Red Bull Racing », et
        « Racing Bulls » là où OpenF1 a écrit « RB » selon les saisons. Le
        rapprochement exact est tenté d'abord, l'inclusion ensuite — et
        l'inclusion n'est retenue que si elle ne désigne qu'une seule écurie.
        """
        cle = normaliser(libelle)
        if not cle:
            return None
        if cle in self._par_equipe:
            return self._par_equipe[cle]

        proches = {
            nom
            for candidate, nom in self._par_equipe.items()
            if candidate.startswith(cle) or cle.startswith(candidate)
        }
        if len(proches) == 1:
            return proches.pop()
        if len(proches) > 1:
            logger.warning(
                "[points] Écurie « %s » ambiguë : %s. Marché laissé non validé.",
                libelle,
                ", ".join(sorted(proches)),
            )
        return None


def _entier(valeur: object) -> int | None:
    """Lit un entier là où OpenF1 rend parfois un flottant (`points: 25.0`)."""
    if isinstance(valeur, bool) or valeur is None:
        return None
    if isinstance(valeur, (int, float)):
        return int(valeur)
    if isinstance(valeur, str):
        try:
            return int(float(valeur.strip()))
        except ValueError:
            return None
    return None


def _secondes(valeur: object) -> float | None:
    """Lit un `gap_to_leader` OpenF1, dont le type change d'une ligne à l'autre.

    Quatre formes, toutes rencontrées :

    | Forme | Exemple | Lecture |
    |---|---|---|
    | nombre | `11.536` | l'écart en secondes |
    | chaîne « tour » | `"+1 LAP"` | `math.inf` — doublé, donc au-delà de tout intervalle |
    | chaîne numérique | `"+11.536"` | l'écart en secondes |
    | `null` / liste | `null`, `[0.0, 0.0, 0.0]` | `None` |

    **`math.inf` plutôt que `None` pour un pilote doublé**, et c'est la seule
    décision de cette fonction : un dauphin à un tour n'est pas un écart
    illisible, c'est un écart plus grand que la borne haute de n'importe quel
    intervalle proposé. Rendre `None` laisserait le pari non jugé alors qu'il est
    parfaitement décidable. Le cas est théorique sur un P2 — il ne l'est pas sur
    le reste du classement, et ce champ resservira.

    La liste (`[0.0, 0.0, 0.0]`, un temps par segment de qualification) ne peut
    apparaître que si le classement vient d'une session qui n'est pas la course :
    `session_de_course()` l'écarte en amont, mais le calcul rejoue des données
    conservées et ne suppose jamais leur provenance.
    """
    if isinstance(valeur, bool) or valeur is None:
        return None
    if isinstance(valeur, (int, float)):
        return float(valeur)
    if not isinstance(valeur, str):
        return None

    texte = valeur.strip()
    if not texte:
        return None
    if "LAP" in texte.upper():
        return math.inf
    try:
        return float(texte.replace(",", ".").lstrip("+"))
    except ValueError:
        return None


def _indexer_pilotes(course: Course) -> None:
    """Construit les index de rapprochement nom → numéro et écurie → écurie.

    Une clé revendiquée par deux pilotes est **retirée** au lieu d'être attribuée
    au premier venu : mieux vaut ne pas valider un pronostic que le valider sur
    le mauvais pilote.

    Aux cinq clés dérivées s'ajoutent les **alias de `calcul/pilotes.py`**, pour
    les libellés qu'aucune règle ne peut produire : Unibet écrit
    « AK.Antonelli » là où OpenF1 dit « Kimi Antonelli », et « C.Sainz Jr » là où
    il dit « Carlos Sainz ». Ces alias passent par la même mise en concurrence
    que les autres clés : un alias qui entrerait en collision avec un pilote
    existant serait retiré comme n'importe quelle autre ambiguïté, jamais imposé.
    """
    revendications: dict[str, set[int]] = {}

    for numero, pilote in course.pilotes.items():
        prenom = pilote.get("prenom") or ""
        famille = pilote.get("nom_famille") or ""
        candidats = [
            pilote.get("nom"),  # « Max VERSTAPPEN »
            famille,  # « Verstappen »
            pilote.get("acronyme"),  # « VER »
            f"{prenom[:1]}{famille}" if prenom and famille else "",  # « M.Verstappen »
            f"{prenom} {famille}" if prenom and famille else "",
            *grille.alias_unibet(numero, famille),
        ]
        for candidat in candidats:
            cle = normaliser(candidat)
            if cle:
                revendications.setdefault(cle, set()).add(numero)

    for cle, numeros in revendications.items():
        if len(numeros) == 1:
            course._par_nom[cle] = next(iter(numeros))
        else:
            logger.warning(
                "[points] Le libellé « %s » désigne %d pilotes (%s) : clé ignorée.",
                cle,
                len(numeros),
                ", ".join(str(numero) for numero in sorted(numeros)),
            )

    for pilote in course.pilotes.values():
        equipe = (pilote.get("equipe") or "").strip()
        if equipe:
            course._par_equipe[normaliser(equipe)] = equipe


# « VSC DEPLOYED », « VSC ENDING » : l'abréviation seule, en mot entier.
_VSC = re.compile(r"\bVSC\b")


def _lire_direction_de_course(course: Course, messages: list[dict]) -> None:
    """Safety car, safety car virtuel et drapeau rouge (règle 4.4).

    C'est **le seul endroit du système qui repose sur du parsing de texte**, et
    le CLAUDE.md le signale comme tel : safety car et safety car virtuel
    remontent tous deux avec `category = "SafetyCar"`, seul le contenu de
    `message` les distingue.

    Deux précautions :

    - le test du VSC passe **avant** celui du safety car ordinaire, la
      chaîne « SAFETY CAR » étant contenue dans « VIRTUAL SAFETY CAR » ;
    - **OpenF1 écrit le VSC en abrégé** — « VSC DEPLOYED », « VSC ENDING » — et
      jamais « VIRTUAL SAFETY CAR » sur les quatre GP 2026 rejoués. Les deux
      formes sont reconnues ; seule la longue l'était jusqu'à la `0.77.0`, si
      bien que le VSC n'était jamais détecté (audit, cause C6) ;
    - seuls les messages de déploiement comptent. La séquence complète d'une
      neutralisation est « … DEPLOYED », « … IN THIS LAP », « … ENDING » :
      compter les trois ferait croire à trois interventions, et surtout un
      « ENDING » sans « DEPLOYED » correspondant n'existe pas.

    Tout message de catégorie `SafetyCar` que ces règles ne reconnaissent pas
    est journalisé — c'est là qu'on verra la FIA changer son vocabulaire.
    """
    inconnus: list[str] = []

    for message in messages:
        categorie = str(message.get("category") or "")
        texte = str(message.get("message") or "").upper()

        if categorie == "SafetyCar":
            if "VIRTUAL SAFETY CAR" in texte or _VSC.search(texte):
                if "DEPLOYED" in texte:
                    course.virtual_safety_car = True
            elif "SAFETY CAR" in texte:
                if "DEPLOYED" in texte:
                    course.safety_car = True
            else:
                inconnus.append(texte)
            continue

        if str(message.get("flag") or "").upper() == "RED":
            course.drapeau_rouge = True

    if inconnus:
        logger.warning(
            "[points] %d message(s) « SafetyCar » non reconnu(s) : %s",
            len(inconnus),
            " ; ".join(sorted(set(inconnus))),
        )


def analyser(donnees: dict) -> Course:
    """Transforme le JSON brut d'OpenF1 en un objet interrogeable.

    Tous les pièges de typage de la section 3.2 sont absorbés ici, et nulle part
    ailleurs : `position` nulle, `points` flottant, `gap_to_leader` de type
    mixte.

    > **`gap_to_leader` était le seul champ du classement à n'être jamais lu**,
    > et le commentaire de cette docstring le disait — c'est ce qui a fait passer
    > l'oubli pour une intention pendant six versions. Il est lu depuis la
    > version `0.54.0` : le marché « écart du gagnant » ne dépend que de lui.
    """
    course = Course()

    for brut in donnees.get("session_result") or []:
        numero = _entier(brut.get("driver_number"))
        if numero is None:
            continue
        course.lignes[numero] = Ligne(
            numero=numero,
            position=_entier(brut.get("position")),
            tours=_entier(brut.get("number_of_laps")) or 0,
            points_fia=_entier(brut.get("points")) or 0,
            abandon=bool(brut.get("dnf")),
            non_partant=bool(brut.get("dns")),
            disqualifie=bool(brut.get("dsq")),
            ecart_leader=_secondes(brut.get("gap_to_leader")),
        )

    for cle, pilote in (donnees.get("pilotes") or {}).items():
        numero = _entier(cle)
        if numero is not None and isinstance(pilote, dict):
            course.pilotes[numero] = pilote

    _indexer_pilotes(course)
    _lire_direction_de_course(course, donnees.get("race_control") or [])

    # `laps` est déjà réduit au meilleur tour de chaque pilote et trié du plus
    # rapide au plus lent par `scraper/openf1.py`. Le tri est refait ici plutôt
    # que supposé : le module doit rester juste sur des données rejouées.
    tours = [
        tour
        for tour in (donnees.get("laps") or [])
        if isinstance(tour.get("lap_duration"), (int, float))
    ]
    if tours:
        course.meilleur_tour = _entier(
            min(tours, key=lambda tour: tour["lap_duration"]).get("driver_number")
        )

    course.pole = _poleman(donnees.get("qualification") or [])

    return course


def _poleman(classement: list[dict]) -> int | None:
    """Le numéro du premier des qualifications, ou `None`.

    `qualification` est le `session_result` de la session « Qualifying » du
    même week-end (`scraper/openf1.py`). C'est le classement des qualifications,
    pas la grille de départ : une pénalité de grille ne retire pas la pole.
    """
    for ligne in classement:
        if isinstance(ligne, dict) and _entier(ligne.get("position")) == 1:
            return _entier(ligne.get("driver_number"))
    return None


# --------------------------------------------------------------------------- #
#  Validation d'un marché
# --------------------------------------------------------------------------- #


def _reponse_binaire(libelle: str) -> bool | None:
    """Lit l'issue d'un marché en oui / non."""
    cle = normaliser(libelle)
    if cle in OUI:
        return True
    if cle in NON:
        return False
    return None


def _numero_au_plus(course: Course, numero: int, rang: int) -> bool:
    """Ce numéro de voiture finit-il au rang demandé, ou mieux ?

    Le test se fait sur un **numéro** et non sur un libellé : les marchés
    d'écurie désignent leurs voitures par l'engagement, pas par le nom que le
    bookmaker en écrit. `_position_au_plus` n'est plus que l'entrée par nom.
    """
    ligne = course.lignes.get(numero)
    if ligne is None:
        # Le pilote existe chez OpenF1 mais n'a aucune ligne de résultat : il
        # n'a pas pris part à la course. Le pari est perdu, pas indécidable.
        return False
    return ligne.classe and ligne.position <= rang


def _position_au_plus(course: Course, libelle: str, rang: int) -> bool | None:
    numero = course.pilote_du_libelle(libelle)
    if numero is None:
        return None
    return _numero_au_plus(course, numero, rang)


def _vainqueur(course: Course, libelle: str) -> bool | None:
    return _position_au_plus(course, libelle, 1)


def _podium(course: Course, libelle: str) -> bool | None:
    return _position_au_plus(course, libelle, 3)


def _abandon(course: Course, libelle: str) -> bool | None:
    numero = course.pilote_du_libelle(libelle)
    if numero is None:
        return None
    ligne = course.lignes.get(numero)
    if ligne is None:
        return False
    # `dns` n'est pas un abandon : un pilote qui ne prend pas le départ n'a pas
    # abandonné la course. Les bookmakers annulent ce cas ; faute de pouvoir
    # rembourser une mise inexistante, le pari est simplement perdu.
    return ligne.abandon and not ligne.non_partant


def _ecurie_gagnante(course: Course, libelle: str) -> bool | None:
    equipe = course.equipe_du_libelle(libelle)
    if equipe is None:
        return None
    tete = course.par_position(1)
    if tete is None:
        return None
    gagnante = (course.pilotes.get(tete.numero) or {}).get("equipe")
    if not gagnante:
        return None
    return normaliser(gagnante) == normaliser(equipe)


def _meilleur_tour(course: Course, libelle: str) -> bool | None:
    if course.meilleur_tour is None:
        return None
    numero = course.pilote_du_libelle(libelle)
    if numero is None:
        return None
    return numero == course.meilleur_tour


# Un nombre à la française ou à l'anglaise : « 5 », « 5,50 », « 5.50 ».
_NOMBRE = r"(\d+(?:[.,]\d+)?)"

# Une plage — « 5 - 10 », « 5 à 10 », « entre 5 et 10 », « 5/10 ». Testée EN
# PREMIER : le tiret d'un intervalle est aussi le signe de « - de 5 secondes »,
# et l'ordre est ce qui les départage.
_PLAGE = re.compile(_NOMBRE + r"\s*(?:-|a|et|/)\s*" + _NOMBRE)
# Une borne basse — « plus de 10 », « + de 10 », « au-delà de 10 », « > 10 ».
_BORNE_BASSE = re.compile(r"(?:plus|au ?dela|superieur|>|\+)\D{0,12}?" + _NOMBRE)
# Une borne haute — « moins de 5 », « - de 5 », « jusqu'à 5 », « < 5 ».
_BORNE_HAUTE = re.compile(r"(?:moins|jusqu|inferieur|<|-)\D{0,12}?" + _NOMBRE)


def _intervalle_secondes(libelle: str) -> tuple[float, float] | None:
    """Lit l'intervalle de secondes que désigne une issue « écart du gagnant ».

    Rend `[bas, haut[` — **borne basse incluse, borne haute exclue**. Ce n'est
    pas une coquetterie : les issues d'Unibet forment une partition (« moins de
    5 », « 5 - 10 », « plus de 10 »), et deux bornes inclusives feraient gagner
    *deux* paris à un écart de très exactement 5,000 s, deux exclusives n'en
    feraient gagner aucun. Un écart se mesure au millième, donc le cas ne se
    produira jamais — raison de plus pour que la règle soit décidée ici une fois,
    plutôt que découverte le jour où il se produit.

    `None` dès que le libellé ne décrit pas un intervalle. C'est la porte de
    sortie qui protège tout le reste : le marché « écart du gagnant » n'a jamais
    été confronté à de vrais libellés Unibet (`scraper.md` §10), et une issue que
    ces formes ne reconnaissent pas laisse le pronostic à `NULL` — donc
    rattrapable — au lieu d'être notée sur un intervalle inventé.
    """
    texte = "".join(
        caractere
        for caractere in unicodedata.normalize("NFD", (libelle or "").lower())
        if unicodedata.category(caractere) != "Mn"
    ).strip()
    if not texte:
        return None

    def nombre(brut: str) -> float:
        return float(brut.replace(",", "."))

    plage = _PLAGE.search(texte)
    if plage:
        bornes = sorted((nombre(plage.group(1)), nombre(plage.group(2))))
        return (bornes[0], bornes[1])

    basse = _BORNE_BASSE.search(texte)
    if basse:
        return (nombre(basse.group(1)), math.inf)

    haute = _BORNE_HAUTE.search(texte)
    if haute:
        return (0.0, nombre(haute.group(1)))

    return None


def _ecart_du_gagnant(course: Course, libelle: str) -> bool | None:
    """L'écart entre le vainqueur et son dauphin tombe-t-il dans l'intervalle ?

    Deux inconnues, et **chacune rend `None` pour son propre compte** : l'écart
    peut manquer (pas de deuxième, champ illisible) et le libellé peut ne pas
    décrire un intervalle. Les distinguer dans les logs est ce qui dira, au
    premier vrai Grand Prix, s'il faut corriger la lecture de la donnée ou
    l'écriture des formes reconnues.
    """
    ecart = course.ecart_du_vainqueur()
    if ecart is None:
        return None
    intervalle = _intervalle_secondes(libelle)
    if intervalle is None:
        logger.warning(
            "[points] Écart du gagnant : l'issue « %s » ne décrit aucun "
            "intervalle reconnu. Pronostic laissé non jugé.",
            libelle,
        )
        return None
    bas, haut = intervalle
    return bas <= ecart < haut


def _nationalite_du_vainqueur(options: Sequence[str] = ()):
    """Rend le validateur du marché « nationalité du vainqueur ».

    **La nationalité ne se lit pas dans les données de course.** `country_code`
    de `/drivers` est déprécié et disparaît fin 2026 (`scraper.md` §9) : elle
    vient donc de la table statique de `calcul/pilotes.py`, sous le même
    garde-fou de saison que les alias — numéro **et** nom de famille doivent
    concorder, sans quoi rien n'est rendu.

    Comme « écart du gagnant », c'est un marché dont l'issue n'est pas un
    pilote, et **chacune des inconnues rend `None` pour son propre compte** : la
    nationalité du vainqueur peut manquer (table périmée, pilote hors grille) et
    le libellé peut n'être aucune nationalité connue. Les distinguer dans les
    logs est ce qui dira, au premier vrai marché, s'il faut mettre la grille à
    jour ou ajouter une forme à `NATIONALITES`.

    > ### « Autres » ne se juge pas sans ses issues sœurs (version `0.56.0`)
    >
    > Toutes les autres issues du système se jugent seules : « Néerlandais » est
    > vrai ou faux sans qu'on ait besoin de savoir ce que le marché proposait à
    > côté. **« Autres » est la première qui n'est pas une valeur mais un
    > complémentaire** — elle veut dire « une nationalité qu'Unibet n'a pas
    > listée ce jour-là », et cette liste change d'un Grand Prix à l'autre.
    >
    > D'où le paramètre `options` : les libellés des **autres issues du même
    > marché et du même Grand Prix**, lus dans les cotes déjà chargées. « Autres »
    > est réussi si la nationalité du vainqueur n'est **dans aucune** d'elles, raté
    > si elle est dans l'une. C'est vrai de tout Grand Prix futur : rien ici ne
    > connaît un pays en particulier.
    >
    > **Une option sœur illisible ne fait pas gagner « Autres ».** Elle pourrait
    > être précisément la nationalité du vainqueur : conclure « pas listée » à
    > partir d'une liste qu'on ne sait pas lire en entier inventerait un gain.
    > Elle ne l'empêche pas de perdre pour autant — si la nationalité du vainqueur
    > figure déjà parmi les options **lues**, « Autres » est faux et aucun libellé
    > restant ne peut le rendre vrai.
    """
    # Les issues sœurs, débarrassées des formes « Autres » : une issue ne se
    # compare pas à elle-même, et un marché peut en porter plusieurs variantes.
    listees = tuple(
        libelle
        for libelle in options
        if libelle and not grille.est_autres(libelle)
    )

    def valider(course: Course, libelle: str) -> bool | None:
        tete = course.par_position(1)
        if tete is None:
            return None

        identite = course.pilotes.get(tete.numero) or {}
        du_vainqueur = grille.nationalite_du_pilote(
            tete.numero, str(identite.get("nom_famille") or "")
        )
        if du_vainqueur is None:
            logger.warning(
                "[points] Nationalité du vainqueur : le numéro %s (%s) n'est pas "
                "dans la grille %s, ou son nom n'y concorde pas. Pronostic laissé "
                "non jugé.",
                tete.numero,
                identite.get("nom") or "?",
                grille.SAISON,
            )
            return None

        if grille.est_autres(libelle):
            return _autres_nationalites(du_vainqueur, listees)

        proposee = grille.code_nationalite(libelle)
        if proposee is None:
            logger.warning(
                "[points] Nationalité du vainqueur : l'issue « %s » ne correspond à "
                "aucune nationalité connue. Pronostic laissé non jugé.",
                libelle,
            )
            return None

        return du_vainqueur == proposee

    return valider


def _autres_nationalites(du_vainqueur: str, listees: Sequence[str]) -> bool | None:
    """« Autres » : la nationalité du vainqueur échappe-t-elle aux options listées ?

    Trois issues possibles, et l'ordre des tests porte tout le raisonnement :

    1. la nationalité du vainqueur est parmi les options **lues** → **raté**, et
       c'est définitif, même si d'autres options restent illisibles ;
    2. une option n'a pas été comprise → **non jugé**, elle pouvait être celle du
       vainqueur ;
    3. sinon → **réussi**.

    Un marché qui ne proposerait **que** « Autres » n'est pas un marché : sans
    aucune option à quoi s'opposer, l'issue n'a pas de sens et rien n'est jugé.
    """
    if not listees:
        logger.warning(
            "[points] Nationalité du vainqueur : l'issue « Autres » est la seule "
            "du marché, il n'y a aucune option à laquelle l'opposer. Pronostic "
            "laissé non jugé.",
        )
        return None

    codes = {libelle: grille.code_nationalite(libelle) for libelle in listees}

    if du_vainqueur in set(codes.values()):
        return False

    illisibles = [libelle for libelle, code in codes.items() if code is None]
    if illisibles:
        logger.warning(
            "[points] Nationalité du vainqueur : l'issue « Autres » ne peut pas "
            "être jugée, %d option(s) du marché ne correspondent à aucune "
            "nationalité connue : %s. Pronostic laissé non jugé.",
            len(illisibles),
            " ; ".join(illisibles),
        )
        return None

    return True


def _safety_car(course: Course, libelle: str) -> bool | None:
    reponse = _reponse_binaire(libelle)
    if reponse is None:
        return None
    return course.safety_car == reponse


def _safety_car_virtuel(course: Course, libelle: str) -> bool | None:
    reponse = _reponse_binaire(libelle)
    if reponse is None:
        return None
    return course.virtual_safety_car == reponse


def _drapeau_rouge(course: Course, libelle: str) -> bool | None:
    reponse = _reponse_binaire(libelle)
    if reponse is None:
        return None
    return course.drapeau_rouge == reponse


def _top(rang: int):
    def valider(course: Course, libelle: str) -> bool | None:
        return _position_au_plus(course, libelle, rang)

    return valider


# « Ferrari / Les 2 voitures dans le top 10 » — une FAMILLE de marchés, un par
# écurie, dont le slug porte à la fois le nom de l'écurie et le rang. C'est le
# seul de ce genre : partout ailleurs le slug nomme le marché et l'issue nomme
# le sujet. Les deux sont donc lus ici, et rien n'est écrit en dur —
# « mercedes-amg-… » et « audi-f1-team-… » se rapprochent de « Mercedes » et
# « Audi » par la même inclusion que le marché « écurie vainqueur », qui couvre
# les onze variantes relevées sur les vrais marchés des GP Italie et Espagne
# 2026 (alpine, aston-martin, audi-f1-team, cadillac, ferrari, haas, mclaren,
# mercedes-amg, racing-bulls-team, red-bull, williams).
#
# **Le préfixe d'écurie est obligatoire** : « les-2-voitures-sur-le-podium » est
# un autre marché, dont les issues sont des noms d'écurie et non un oui/non.
_DEUX_VOITURES = re.compile(
    r"(?P<ecurie>.+?)-les-(?:2|deux)-voitures-dans-le-top-?(?P<rang>\d+)"
)


def _les_deux_voitures_dans_le_top(ecurie: str, rang: int):
    """Rend le validateur d'un « {écurie} / les 2 voitures dans le top N ».

    L'issue est un oui/non, mais la question porte sur **deux pilotes à la
    fois** : les deux voitures de l'écurie sont-elles classées au rang demandé
    ou mieux ? « Oui » gagne si les deux y sont, « Non » gagne dans tous les
    autres cas — les deux issues sont exactement complémentaires, et c'est ce
    qui permet de les juger d'une seule comparaison.

    **Les deux voitures viennent des résultats, pas de la grille statique**
    (`Course.voitures_de`) : c'est la seule source qui suive les changements de
    baquet en cours de saison, et se tromper ici écrirait un `0` irréversible.

    Trois inconnues, chacune rendant `None` pour son propre compte et
    journalisée séparément — l'issue illisible, l'écurie non rapprochée, et le
    nombre de voitures classées différent de deux. Les distinguer est ce qui
    dira, en relisant les logs, s'il faut corriger la lecture du slug ou
    constater qu'une écurie n'a engagé qu'une voiture.
    """

    def valider(course: Course, libelle: str) -> bool | None:
        reponse = _reponse_binaire(libelle)
        if reponse is None:
            logger.warning(
                "[points] Les 2 voitures dans le top %d (%s) : l'issue « %s » "
                "n'est ni « Oui » ni « Non ». Pronostic laissé non jugé.",
                rang,
                ecurie,
                libelle,
            )
            return None

        equipe = course.equipe_du_libelle(ecurie)
        if equipe is None:
            logger.warning(
                "[points] Les 2 voitures dans le top %d : « %s » n'a été rapprochée "
                "d'aucune écurie de la course. Pronostic laissé non jugé.",
                rang,
                ecurie,
            )
            return None

        numeros = course.voitures_de(equipe)
        if len(numeros) != 2:
            logger.warning(
                "[points] Les 2 voitures dans le top %d : « %s » compte %d voiture(s) "
                "au classement, pas deux. Pronostic laissé non jugé.",
                rang,
                equipe,
                len(numeros),
            )
            return None

        les_deux = all(_numero_au_plus(course, numero, rang) for numero in numeros)
        return les_deux == reponse

    return valider


# --------------------------------------------------------------------------- #
#  Marchés ajoutés en 0.77.0 (audit, causes C1 et C3)
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class Partage:
    """Issue gagnante à égalité avec d'autres : la cote est divisée entre elles.

    Règle des bookmakers (*dead heat*) : quand `diviseur` issues finissent à
    égalité en tête, chacune rapporte sa cote divisée par `diviseur`, arrondie à
    l'entier. Seule « l'écurie qui marque le plus de points » la produit.
    """

    diviseur: int


def points_partages(valeur: int, diviseur: int) -> int:
    """`valeur / diviseur`, arrondi à l'entier le plus proche (demi vers le haut).

    En arithmétique entière : `round()` de Python arrondit un demi au pair
    (`round(12.5) == 12`), ce qu'aucun joueur ne comprendrait.
    """
    return (2 * valeur + diviseur) // (2 * diviseur)


def _ecurie_la_plus_marquante(course: Course, libelle: str) -> bool | Partage | None:
    """L'écurie désignée est-elle celle qui marque le plus de points FIA ?

    Somme des `points` de `session_result` par écurie, l'écurie de chaque pilote
    lue dans `/drivers` du Grand Prix (jamais dans la grille statique). En cas
    d'égalité en tête, l'issue gagne **à partage** (`Partage`) : aux Pays-Bas
    2026, McLaren et Mercedes finissent à 33 points chacune.

    Un pilote qui marque sans écurie connue laisse le marché non jugé : une
    somme incomplète pourrait désigner la mauvaise écurie.
    """
    equipe = course.equipe_du_libelle(libelle)
    if equipe is None:
        return None

    totaux: dict[str, int] = {}
    for numero, ligne in course.lignes.items():
        if ligne.points_fia <= 0:
            continue
        ecurie = (course.pilotes.get(numero) or {}).get("equipe")
        if not ecurie:
            return None
        cle = normaliser(ecurie)
        totaux[cle] = totaux.get(cle, 0) + ligne.points_fia

    if not totaux:
        return None

    meilleur = max(totaux.values())
    en_tete = [cle for cle, total in totaux.items() if total == meilleur]
    if normaliser(equipe) not in en_tete:
        return False
    if len(en_tete) == 1:
        return True
    return Partage(len(en_tete))


def _ecurie_du_meilleur_tour(course: Course, libelle: str) -> bool | None:
    """L'écurie désignée est-elle celle du pilote qui signe le meilleur tour ?"""
    if course.meilleur_tour is None:
        return None
    equipe = course.equipe_du_libelle(libelle)
    if equipe is None:
        return None
    auteur = (course.pilotes.get(course.meilleur_tour) or {}).get("equipe")
    if not auteur:
        return None
    return normaliser(auteur) == normaliser(equipe)


def _voiture_du_meilleur_tour(course: Course, libelle: str) -> bool | None:
    """« Voiture réalisant le tour le plus rapide » : un pilote ou une écurie.

    Aucune issue de ce marché n'a été relevée en base : Unibet peut y nommer la
    voiture par son pilote ou par son écurie. Les deux lectures sont tentées,
    pilote d'abord ; un libellé qui n'est ni l'un ni l'autre reste non jugé.
    """
    if course.pilote_du_libelle(libelle) is not None:
        return _meilleur_tour(course, libelle)
    return _ecurie_du_meilleur_tour(course, libelle)


def _triple(course: Course, libelle: str) -> bool | None:
    """« Vainqueur course, qualification et tour le plus rapide » — oui / non.

    « Oui » gagne si un même pilote signe la pole, la victoire et le meilleur
    tour. La pole se lit dans les qualifications (`Course.pole`) : sans elles,
    le marché reste en attente, jamais perdu.
    """
    reponse = _reponse_binaire(libelle)
    if reponse is None:
        return None
    tete = course.par_position(1)
    if tete is None or course.pole is None or course.meilleur_tour is None:
        return None
    return (tete.numero == course.pole == course.meilleur_tour) == reponse


def _les_deux_voitures_sur_le_podium(course: Course, libelle: str) -> bool | None:
    """L'écurie désignée place-t-elle ses deux voitures sur le podium ?

    L'issue nomme une écurie (le marché n'est pas un oui/non). La paire se lit
    dans les résultats, comme pour « les 2 voitures dans le top N ».
    """
    equipe = course.equipe_du_libelle(libelle)
    if equipe is None:
        return None
    numeros = course.voitures_de(equipe)
    if len(numeros) != 2:
        return None
    return all(_numero_au_plus(course, numero, 3) for numero in numeros)


def _vainqueur_du_duel(course: Course, a: int, b: int) -> int | None:
    """Le gagnant d'un face-à-face, ou `None` si rien ne les départage.

    1. Les deux classés : le mieux classé gagne.
    2. Un seul classé : il gagne.
    3. Aucun classé : celui qui a bouclé le plus de tours gagne. Un pilote sans
       ligne de résultat compte zéro tour. À tours égaux, rien n'est décidé.
    """
    ligne_a, ligne_b = course.lignes.get(a), course.lignes.get(b)
    classe_a = ligne_a is not None and ligne_a.classe
    classe_b = ligne_b is not None and ligne_b.classe

    if classe_a and classe_b:
        return a if ligne_a.position < ligne_b.position else b
    if classe_a:
        return a
    if classe_b:
        return b

    tours_a = ligne_a.tours if ligne_a else 0
    tours_b = ligne_b.tours if ligne_b else 0
    if tours_a == tours_b:
        return None
    return a if tours_a > tours_b else b


def _face_a_face(options: Sequence[str] = ()):
    """Rend le validateur d'un marché « face-à-face ».

    Le slug nomme le duel (`face-a-face-o-piastri-l-norris`) sous une forme
    qu'aucune règle ne découpe sûrement en deux pilotes. Les deux adversaires se
    lisent donc dans les **issues du marché**, comme « Autres » pour la
    nationalité : exactement deux libellés, chacun rapproché d'un pilote
    différent, sans quoi rien n'est jugé.
    """
    libelles = tuple(dict.fromkeys(libelle for libelle in options if libelle))

    def valider(course: Course, libelle: str) -> bool | None:
        numeros = {course.pilote_du_libelle(option) for option in libelles}
        if len(libelles) != 2 or len(numeros) != 2 or None in numeros:
            logger.warning(
                "[points] Face-à-face : issues %s non rapprochées de deux pilotes "
                "distincts. Pronostic laissé non jugé.",
                " / ".join(libelles) or "absentes",
            )
            return None

        choisi = course.pilote_du_libelle(libelle)
        if choisi not in numeros:
            return None

        a, b = sorted(numeros)
        gagnant = _vainqueur_du_duel(course, a, b)
        if gagnant is None:
            logger.warning(
                "[points] Face-à-face #%s / #%s : aucun classé, tours égaux. "
                "Pronostic laissé non jugé.",
                a,
                b,
            )
            return None
        return gagnant == choisi

    return valider


# --------------------------------------------------------------------------- #
#  Registre des évaluateurs
# --------------------------------------------------------------------------- #

# Chaque marché est désigné par son slug EXACT (`scraper.unibet.slug()` du
# libellé Unibet), ou par une famille déclarée en `fullmatch`. **Aucune
# reconnaissance par préfixe ni par sous-chaîne** : c'est elle qui laissait
# passer les marchés renommés (C1) et capturait les marchés voisins — trois
# marchés différents jugés « écurie du vainqueur » parce que leur slug commençait
# par « ecurie » ou « equipe » (C3).
#
# Un slug absent d'ici n'est pas évaluable : le scraper ne l'enregistre pas, et
# un pronostic qui le porterait déjà passe `non_evaluable`. Ajouter un marché,
# c'est ajouter une ligne ici, et son slug à `tests/test_marches.py`.
#
# Chaque entrée reçoit les issues sœurs du marché (`options`) ; seules la
# nationalité et le face-à-face s'en servent.
_EXACTS = {
    MARCHE_VAINQUEUR: lambda options: _vainqueur,
    MARCHE_PODIUM: lambda options: _podium,
    "ecurie-vainqueur": lambda options: _ecurie_gagnante,
    # Même marché sous deux noms : Unibet a renommé le premier en second.
    "ecart-du-gagnant": lambda options: _ecart_du_gagnant,
    "marge-du-vainqueur": lambda options: _ecart_du_gagnant,
    "nationalite-du-vainqueur": _nationalite_du_vainqueur,
    # Même marché sous deux noms, jugé sur la somme des points FIA.
    "ecurie-qui-marque-le-plus-de-points": lambda options: _ecurie_la_plus_marquante,
    "equipe-qui-marque-le-plus-de-points": lambda options: _ecurie_la_plus_marquante,
    "tour-le-plus-rapide": lambda options: _meilleur_tour,
    "tour-le-plus-rapide-vainqueur": lambda options: _meilleur_tour,
    "ecurie-realisant-le-tour-le-plus-rapide": lambda options: _ecurie_du_meilleur_tour,
    "voiture-realisant-le-tour-le-plus-rapide": lambda options: _voiture_du_meilleur_tour,
    "vainqueur-course-qualification-et-tour-le-plus-rapide": lambda options: _triple,
    "les-2-voitures-sur-le-podium": lambda options: _les_deux_voitures_sur_le_podium,
}

# Familles : le slug porte un paramètre (rang, écurie, duel).
_FAMILLES = (
    (
        re.compile(r"(?:dans-le-)?top-?(?P<rang>\d+)"),
        lambda m, options: _top(int(m.group("rang"))),
    ),
    (
        _DEUX_VOITURES,
        lambda m, options: _les_deux_voitures_dans_le_top(
            m.group("ecurie"), int(m.group("rang"))
        ),
    ),
    (
        re.compile(r"face-a-face-[a-z0-9-]+"),
        lambda m, options: _face_a_face(options),
    ),
)

# Marchés connus et volontairement NON évalués, parce que leur règle n'est pas
# écrite. Ils ne s'en distinguent pas à l'usage d'un slug inconnu — ni l'un ni
# l'autre n'est enregistré par le scraper — mais leur présence ici dit que
# l'absence d'évaluateur est une décision, pas un oubli.
#
# - `premier-abandon` : la règle d'égalité (deux abandons au même tour) n'est
#   pas écrite (`metier.md` §4).
#
# `_safety_car`, `_safety_car_virtuel`, `_drapeau_rouge` et `_abandon` existent
# mais n'ont aucun slug : aucun marché de ce genre n'a encore été vu chez
# Unibet. Le jour où le scraper en écarte un, son slug exact s'ajoute à
# `_EXACTS`.
NON_EVALUABLES = frozenset({"premier-abandon"})


def validateur(marche: str, options: Sequence[str] = ()):
    """Rend le validateur d'un marché, ou `None` s'il n'est pas évaluable.

    La recherche se fait dans le registre ci-dessus, par slug exact puis par
    famille en `fullmatch`. Un slug que rien ne reconnaît rend `None` : le
    pronostic est `non_evaluable`, jamais jugé par un évaluateur voisin.

    `options` porte les libellés de toutes les issues du marché pour ce Grand
    Prix (`issues_du_marche`). Facultatif : sans lui, « Autres » et les
    face-à-face restent non jugés plutôt que mal jugés.
    """
    slug = (marche or "").strip().lower()
    if not slug or slug in NON_EVALUABLES:
        return None

    fabrique = _EXACTS.get(slug)
    if fabrique is not None:
        return fabrique(options)

    for motif, fabrique_famille in _FAMILLES:
        correspondance = motif.fullmatch(slug)
        if correspondance:
            return fabrique_famille(correspondance, options)

    return None


def evaluable(marche: str) -> bool:
    """Le backend sait-il juger ce marché ? Consulté par le scraper."""
    return validateur(marche) is not None


# --------------------------------------------------------------------------- #
#  Points d'un pronostic
# --------------------------------------------------------------------------- #


# Statuts d'évaluation d'un pronostic (`pronostics.statut_evaluation`, migration
# `20260926120000`). `en_attente` n'est jamais écrit par le calcul : c'est l'état
# par défaut, celui d'un pronostic que rien n'a encore pu juger.
EN_ATTENTE = "en_attente"
NON_EVALUABLE = "non_evaluable"
GAGNE = "gagne"
PERDU = "perdu"


@dataclass
class Attribution:
    """Ce qu'un pronostic rapporte, et pourquoi.

    `points` est `None` pour un pronostic `non_evaluable` : aucun évaluateur ne
    porte son marché, il n'y a rien à payer ni à refuser. La base en tient le
    statut, sans toucher à `points_gagnes`.
    """

    pronostic_id: str
    points: int | None
    reussi: bool
    detail: str
    statut: str = ""

    def __post_init__(self) -> None:
        if not self.statut:
            self.statut = GAGNE if self.reussi else PERDU


def issues_du_marche(cotes: dict[str, dict], marche: str) -> tuple[str, ...]:
    """Les libellés de toutes les issues d'un marché, pour ce Grand Prix.

    Rien n'est relu en base : `cotes` **est** déjà la table `cotes` du Grand
    Prix, indexée par issue (`cotes_du_gp`). Le marché proposé un jour donné se
    déduit donc de ce que le scraper a enregistré ce jour-là, et jamais d'une
    liste écrite en dur — c'est ce qui fait tenir la règle pour tous les Grands
    Prix à venir, dont les options changeront.

    Un seul validateur en a besoin : celui de la nationalité, pour son issue
    « Autres » (§4 de `metier.md`).
    """
    return tuple(
        str(cote.get("pilote") or "")
        for cote in cotes.values()
        if str(cote.get("marche") or "") == marche
    )


def _cote(cotes: dict[str, dict], outcome: str) -> dict | None:
    return cotes.get(outcome)


def points_du_podium(pronostic: dict, cotes: dict[str, dict], course: Course):
    """Le pronostic de podium : deux pilotes, sans ordre entre eux (règle 4.2).

    > ### Chaque pilote est jugé pour son propre compte (version `0.54.0`)
    >
    > Le podium n'est pas un pari en deux jambes solidaires : ce sont **deux
    > paris** saisis dans le même bloc. Un pilote qui monte sur le podium rapporte
    > sa cote, que l'autre y monte ou non. Les deux, un seul, ou aucun.
    >
    > Jusqu'ici une seule sélection fausse invalidait les deux, et la conséquence
    > était sévère : le podium est **le pari le mieux doté de la grille** — c'est
    > le seul qui puisse rapporter la somme de deux cotes — et il était aussi le
    > seul à ne jamais rien rapporter à moitié. Un joueur qui plaçait le bon
    > pilote finissait à égalité avec celui qui s'était trompé sur les deux.
    >
    > **Ce que la règle NE change pas** : le total potentiel affiché avant la
    > course reste la somme des deux cotes (§9 de `metier.md`), parce que c'est
    > toujours le maximum atteignable ; et la somme reste ordre-indépendante,
    > puisque chaque cote est payée à son propre pilote et non au rang de saisie.

    **Une jambe non jugeable laisse le pronostic ENTIER à `NULL`**, même si
    l'autre est décidée. La ligne ne porte qu'un seul `points_gagnes`, et
    `attribuer_points` n'écrit que les `NULL` (`scraper.md` §11) : payer la seule
    jambe connue figerait un total partiel que le rattrapage ne corrigerait
    **plus jamais**. Attendre est réversible, écrire ne l'est pas.
    """
    detail = pronostic.get("pronostic_podium") or {}
    # PostgREST rend une relation « un vers un » tantôt en objet, tantôt en
    # tableau d'un élément selon la version : les deux formes sont acceptées.
    if isinstance(detail, list):
        detail = detail[0] if detail else {}

    premier = str(detail.get("pilote_1") or pronostic.get("id_outcome_unibet") or "")
    second = str(detail.get("pilote_2") or "")

    if not premier or not second:
        return None, "podium incomplet en base"

    cote_1 = _cote(cotes, premier)
    cote_2 = _cote(cotes, second)
    if cote_1 is None or cote_2 is None:
        # Une des deux cotes a disparu du GP : le pronostic reste affiché sans
        # points plutôt que d'être noté sur une valeur inventée.
        return None, "cote absente pour l'un des deux pilotes du podium"

    for cote in (cote_1, cote_2):
        if cote.get("marche") != MARCHE_PODIUM:
            return None, f"marché inattendu pour un podium : {cote.get('marche')!r}"

    resultats = [
        _podium(course, str(cote.get("pilote") or "")) for cote in (cote_1, cote_2)
    ]
    if any(resultat is None for resultat in resultats):
        return None, "pilote du podium non rapproché d'OpenF1"

    # Chaque pilote paie sa propre cote, ou zéro. La somme suit — elle n'est plus
    # une règle à part, seulement le cas où les deux termes sont non nuls.
    gains = [
        int(cote["valeur"] or 0) if reussi else 0
        for cote, reussi in zip((cote_1, cote_2), resultats)
    ]
    total = sum(gains)

    # Le détail nomme les deux pilotes et ce que chacun a rapporté : c'est la
    # seule trace qui dira, en relisant les logs, si un demi-podium vient d'un
    # pilote absent du top 3 ou d'un rapprochement de nom qui a mal tourné.
    detail = " · ".join(
        f"{cote.get('pilote')} {'✓ ' + str(gain) + ' pts' if reussi else '✗'}"
        for cote, reussi, gain in zip((cote_1, cote_2), resultats, gains)
    )

    return (
        Attribution(
            pronostic_id=str(pronostic["id"]),
            points=total,
            # `reussi` suit les points, comme partout ailleurs : un demi-podium
            # a rapporté, donc il compte dans `paris_gagnes_pct` et peut être un
            # `meilleur_coup` (§9 de `metier.md`). C'est aussi ce que la pastille
            # de verdict lit à l'écran — `points_gagnes > 0`.
            reussi=total > 0,
            detail=f"podium — {detail}",
        ),
        "",
    )


def points_du_pronostic(pronostic: dict, cotes: dict[str, dict], course: Course):
    """Note un pronostic. Rend `(Attribution, "")` ou `(None, raison)`.

    Une raison non vide veut dire « on ne sait pas juger » : le pronostic reste
    à NULL, l'appelant journalise, et un passage ultérieur pourra le rattraper.
    """
    if pronostic.get("type") == MARCHE_PODIUM:
        return points_du_podium(pronostic, cotes, course)

    outcome = str(pronostic.get("id_outcome_unibet") or "")
    cote = _cote(cotes, outcome)
    if cote is None:
        return None, "cote absente du Grand Prix"

    marche = str(cote.get("marche") or "")
    juger = validateur(marche, issues_du_marche(cotes, marche))
    if juger is None:
        # Aucun évaluateur : ce n'est pas une donnée qui manque, c'est le code.
        # Le statut le dit, et `points_gagnes` reste NULL — un évaluateur livré
        # plus tard le rattrapera au prochain passage.
        return (
            Attribution(
                pronostic_id=str(pronostic["id"]),
                points=None,
                reussi=False,
                detail=f"{marche} — aucun évaluateur",
                statut=NON_EVALUABLE,
            ),
            "",
        )

    # Un pronostic obligatoire ne peut venir que de son marché — la route de
    # l'étape 5 le garantit à la saisie, ce contrôle-ci le garantit au calcul,
    # y compris pour des pronostics écrits avant que la règle n'existe.
    if pronostic.get("type") == "vainqueur" and marche != MARCHE_VAINQUEUR:
        return None, f"pronostic « vainqueur » sur le marché « {marche} »"

    reussi = juger(course, str(cote.get("pilote") or ""))
    if reussi is None:
        return None, f"issue « {cote.get('pilote')} » non rapprochée ({marche})"

    valeur = int(cote.get("valeur") or 0)
    if isinstance(reussi, Partage):
        # Gagné à égalité : la cote est divisée entre les issues ex æquo.
        points = points_partages(valeur, reussi.diviseur)
        verdict = f"réussi à égalité (÷{reussi.diviseur}), {points} pts"
    else:
        points = valeur if reussi else 0
        verdict = f"réussi, {points} pts" if reussi else "raté"

    return (
        Attribution(
            pronostic_id=str(pronostic["id"]),
            points=points,
            reussi=points > 0,
            detail=f"{marche} — {cote.get('pilote')} : {verdict}",
        ),
        "",
    )


def calculer(
    pronostics: list[dict], cotes: dict[str, dict], donnees: dict
) -> tuple[list[Attribution], list[str]]:
    """Note tous les pronostics d'un GP.

    Rend les attributions à écrire — `gagne`, `perdu` ou `non_evaluable` — et
    la liste des pronostics laissés en attente, avec leur raison. La seconde liste est aussi importante que la
    première : c'est elle qui dit ce que le code n'a pas su juger, et c'est elle
    qu'on relit pour décider d'écrire un validateur de plus.
    """
    course = analyser(donnees)

    attributions: list[Attribution] = []
    en_attente: list[str] = []

    for pronostic in pronostics:
        attribution, raison = points_du_pronostic(pronostic, cotes, course)
        if attribution is None:
            en_attente.append(f"{pronostic.get('id')} ({pronostic.get('type')}) : {raison}")
        else:
            attributions.append(attribution)

    reussis = sum(1 for attribution in attributions if attribution.statut == GAGNE)
    rates = sum(1 for attribution in attributions if attribution.statut == PERDU)
    non_evaluables = [a for a in attributions if a.statut == NON_EVALUABLE]
    logger.info(
        "[points] %d pronostic(s) noté(s) — %d réussi(s), %d raté(s), %d non "
        "évaluable(s), %d en attente. Course : safety car %s, VSC %s, drapeau "
        "rouge %s, meilleur tour #%s, pole #%s.",
        reussis + rates,
        reussis,
        rates,
        len(non_evaluables),
        len(en_attente),
        course.safety_car,
        course.virtual_safety_car,
        course.drapeau_rouge,
        course.meilleur_tour,
        course.pole,
    )
    if non_evaluables:
        logger.warning(
            "[points] %d pronostic(s) sur un marché sans évaluateur : %s",
            len(non_evaluables),
            " ; ".join(f"{a.pronostic_id} ({a.detail})" for a in non_evaluables),
        )
    if en_attente:
        logger.warning(
            "[points] %d pronostic(s) laissé(s) sans points, à rattraper : %s",
            len(en_attente),
            " ; ".join(en_attente),
        )

    return attributions, en_attente
