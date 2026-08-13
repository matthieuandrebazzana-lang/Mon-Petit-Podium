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
import re
import unicodedata
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

    # Index de rapprochement, construits une fois pour toutes.
    _par_nom: dict[str, int] = field(default_factory=dict)
    _par_equipe: dict[str, str] = field(default_factory=dict)

    def par_position(self, position: int) -> Ligne | None:
        for ligne in self.lignes.values():
            if ligne.position == position:
                return ligne
        return None

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


def _lire_direction_de_course(course: Course, messages: list[dict]) -> None:
    """Safety car, safety car virtuel et drapeau rouge (règle 4.4).

    C'est **le seul endroit du système qui repose sur du parsing de texte**, et
    le CLAUDE.md le signale comme tel : safety car et safety car virtuel
    remontent tous deux avec `category = "SafetyCar"`, seul le contenu de
    `message` les distingue.

    Deux précautions :

    - le test « VIRTUAL » passe **avant** celui du safety car ordinaire, la
      chaîne « SAFETY CAR » étant contenue dans « VIRTUAL SAFETY CAR » ;
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
            if "VIRTUAL SAFETY CAR" in texte:
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
    mixte (jamais lu — aucun marché validé aujourd'hui n'en dépend, et c'est le
    champ le plus instable de l'API).
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

    return course


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


def _position_au_plus(course: Course, libelle: str, rang: int) -> bool | None:
    numero = course.pilote_du_libelle(libelle)
    if numero is None:
        return None
    ligne = course.lignes.get(numero)
    if ligne is None:
        # Le pilote existe chez OpenF1 mais n'a aucune ligne de résultat : il
        # n'a pas pris part à la course. Le pari est perdu, pas indécidable.
        return False
    return ligne.classe and ligne.position <= rang


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


def validateur(marche: str):
    """Rend le validateur d'un marché, ou `None` si le marché n'est pas reconnu.

    `None` n'est pas un échec : c'est la réponse honnête pour un marché que le
    code ne sait pas encore juger. L'appelant laisse alors le pronostic à NULL
    et le journalise.

    La reconnaissance porte sur le **slug** du marché, celui que
    `scraper.unibet.slug()` fabrique à partir du libellé Unibet. L'ordre des
    tests compte : « ecurie-vainqueur » contient « vainqueur », et un marché de
    safety car virtuel contient « safety car ».

    Seuls « vainqueur », « podium » et « ecurie-vainqueur » ont été observés en
    vrai — Unibet n'ouvre les marchés complets qu'à l'approche de la course
    (section 3.1). Les autres reconnaissances sont écrites d'après les libellés
    annoncés en section 4.4 et **restent à confronter aux vrais marchés**. C'est
    exactement pour cela qu'un marché non reconnu laisse le pronostic à NULL au
    lieu de le déclarer perdu.
    """
    slug = (marche or "").strip().lower()
    if not slug:
        return None

    if slug == MARCHE_VAINQUEUR:
        return _vainqueur
    if slug == MARCHE_PODIUM:
        return _podium

    # Un « top N » porte son rang dans son nom : il est traité à part, le rang
    # ne pouvant pas être connu à l'avance.
    top = re.fullmatch(r"(?:dans-le-)?top-?(\d+)", slug)
    if top:
        return _top(int(top.group(1)))

    if "virtual" in slug and "safety" in slug:
        return _safety_car_virtuel
    if "safety" in slug and "car" in slug:
        return _safety_car
    if "drapeau" in slug and "rouge" in slug:
        return _drapeau_rouge
    if "meilleur" in slug and "tour" in slug:
        return _meilleur_tour
    if slug.startswith(("ecurie", "equipe", "constructeur")):
        return _ecurie_gagnante
    # « premier-abandon » demande de savoir QUI a abandonné le premier, pas SI un
    # pilote a abandonné : ce n'est pas le même marché, et il est laissé non
    # reconnu tant que la règle d'égalité de la section 4.4 n'est pas écrite.
    if slug.startswith("abandon") or slug.endswith("abandonne"):
        return _abandon

    return None


# --------------------------------------------------------------------------- #
#  Points d'un pronostic
# --------------------------------------------------------------------------- #


@dataclass
class Attribution:
    """Ce qu'un pronostic rapporte, et pourquoi."""

    pronostic_id: str
    points: int
    reussi: bool
    detail: str


def _cote(cotes: dict[str, dict], outcome: str) -> dict | None:
    return cotes.get(outcome)


def points_du_podium(pronostic: dict, cotes: dict[str, dict], course: Course):
    """Le pronostic de podium : deux pilotes, sans ordre entre eux (règle 4.2).

    Les deux doivent être sur le podium. Un seul des deux ne rapporte rien : ce
    n'est pas un demi-pronostic, c'est un pronostic raté.

    **Ce que rapporte un podium réussi : la somme des deux cotes.** Le schéma de
    l'étape 5 pose qu'il n'y a aucun ordre entre `pilote_1` et `pilote_2` ;
    payer la seule cote de `pilote_1` ferait donc rapporter deux montants
    différents au même pari selon l'ordre de saisie. La somme est
    ordre-indépendante, et c'est la règle retenue.
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

    if all(resultats):
        total = int(cote_1["valeur"]) + int(cote_2["valeur"])
        return (
            Attribution(
                pronostic_id=str(pronostic["id"]),
                points=total,
                reussi=True,
                detail=(
                    f"podium réussi : {cote_1.get('pilote')} + {cote_2.get('pilote')} "
                    f"= {cote_1['valeur']} + {cote_2['valeur']} pts"
                ),
            ),
            "",
        )

    return (
        Attribution(
            pronostic_id=str(pronostic["id"]),
            points=0,
            reussi=False,
            detail=f"podium manqué : {cote_1.get('pilote')} + {cote_2.get('pilote')}",
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
    juger = validateur(marche)
    if juger is None:
        return None, f"marché « {marche} » non reconnu"

    # Un pronostic obligatoire ne peut venir que de son marché — la route de
    # l'étape 5 le garantit à la saisie, ce contrôle-ci le garantit au calcul,
    # y compris pour des pronostics écrits avant que la règle n'existe.
    if pronostic.get("type") == "vainqueur" and marche != MARCHE_VAINQUEUR:
        return None, f"pronostic « vainqueur » sur le marché « {marche} »"

    reussi = juger(course, str(cote.get("pilote") or ""))
    if reussi is None:
        return None, f"issue « {cote.get('pilote')} » non rapprochée ({marche})"

    valeur = int(cote.get("valeur") or 0)
    return (
        Attribution(
            pronostic_id=str(pronostic["id"]),
            points=valeur if reussi else 0,
            reussi=bool(reussi),
            detail=(
                f"{marche} — {cote.get('pilote')} : "
                f"{'réussi, ' + str(valeur) + ' pts' if reussi else 'raté'}"
            ),
        ),
        "",
    )


def calculer(
    pronostics: list[dict], cotes: dict[str, dict], donnees: dict
) -> tuple[list[Attribution], list[str]]:
    """Note tous les pronostics d'un GP.

    Rend les attributions à écrire et la liste des pronostics laissés en
    attente, avec leur raison. La seconde liste est aussi importante que la
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

    reussis = sum(1 for attribution in attributions if attribution.reussi)
    logger.info(
        "[points] %d pronostic(s) noté(s) — %d réussi(s), %d raté(s), %d en attente. "
        "Course : safety car %s, VSC %s, drapeau rouge %s, meilleur tour #%s.",
        len(attributions),
        reussis,
        len(attributions) - reussis,
        len(en_attente),
        course.safety_car,
        course.virtual_safety_car,
        course.drapeau_rouge,
        course.meilleur_tour,
    )
    if en_attente:
        logger.warning(
            "[points] %d pronostic(s) laissé(s) sans points, à rattraper : %s",
            len(en_attente),
            " ; ".join(en_attente),
        )

    return attributions, en_attente
