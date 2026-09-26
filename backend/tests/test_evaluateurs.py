"""Registre, marchés ajoutés en 0.77.0, filtrage au scraping et bonus en double.

Sauf mention contraire, les courses sont celles de Bakou 2026 : 1. Russell,
2. Verstappen, 3. Hadjar ; meilleur tour et pole Russell ; Mercedes 35 points,
Red Bull 33, Ferrari 20.
"""

import pytest
from fastapi import HTTPException

from app.api.routes.pronostics import exiger_bonus_distincts_des_obligatoires
from app.calcul import points as P
from app.scraper.unibet import Cote, filtrer_evaluables
from conftest import charger_gp

TRIPLE = "80cc59ee-ef2a-466c-ae18-fcb1b013f04d"
MARGE = "8cd836f1-c80e-4eb1-9f98-38f302274305"


def _bakou(sans_qualification: bool = False) -> P.Course:
    donnees = dict(charger_gp("azerbaidjan")["donnees_brutes"])
    if sans_qualification:
        donnees.pop("qualification")
    return P.analyser(donnees)


def _juger(marche: str, libelle: str, options=(), course: P.Course | None = None):
    juger = P.validateur(marche, options)
    assert juger is not None, marche
    return juger(course or _bakou(), libelle)


# --------------------------------------------------------------------------- #
#  Registre
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    "slug",
    [
        "ecurie-ferrari",  # capturé par le préfixe « ecurie » jusqu'à la 0.77.0
        "equipe-du-vainqueur",
        "meilleur-tour",
        "ecart-du-vainqueur-en-secondes",
        "safety-car-oui-non",
        "premier-abandon",
        "",
    ],
)
def test_slug_inconnu_non_evaluable(slug):
    assert P.validateur(slug) is None
    assert not P.evaluable(slug)


def test_premier_abandon_declare_non_evaluable():
    assert "premier-abandon" in P.NON_EVALUABLES


@pytest.mark.parametrize(
    "slug",
    ["top-3", "dans-le-top-6", "haas-les-2-voitures-dans-le-top-6", "face-a-face-x-y"],
)
def test_familles_en_fullmatch(slug):
    assert P.evaluable(slug)


def test_famille_top_n_sans_suffixe():
    assert not P.evaluable("top-10-pilotes")


def test_marche_sans_evaluateur_devient_non_evaluable():
    cotes = {"o1": {"marche": "premier-abandon", "pilote": "L.Norris", "valeur": 40}}
    pronostic = {"id": "p1", "type": "bonus", "id_outcome_unibet": "o1"}
    attribution, raison = P.points_du_pronostic(pronostic, cotes, _bakou())
    assert raison == ""
    assert attribution.statut == P.NON_EVALUABLE
    assert attribution.points is None


# --------------------------------------------------------------------------- #
#  Bakou — les deux pronostics en attente
# --------------------------------------------------------------------------- #


def test_bakou_plus_aucun_pronostic_en_attente():
    gp = charger_gp("azerbaidjan")
    attributions, en_attente = P.calculer(gp["pronostics"], gp["cotes"], gp["donnees_brutes"])
    statuts = {a.pronostic_id: (a.statut, a.points) for a in attributions}
    assert en_attente == []
    assert statuts[TRIPLE] == (P.GAGNE, 50)
    assert statuts[MARGE] == (P.PERDU, 0)


def test_triple_sans_qualifications_reste_en_attente():
    assert _juger("vainqueur-course-qualification-et-tour-le-plus-rapide", "Oui",
                  course=_bakou(sans_qualification=True)) is None


def test_triple_non_perd():
    assert _juger("vainqueur-course-qualification-et-tour-le-plus-rapide", "Non") is False


def test_pole_lue_dans_les_qualifications():
    assert _bakou().pole == 63


@pytest.mark.parametrize(
    ("issue", "gagne"),
    [("Moins de 5 secondes", True), ("Entre 5 et 10 secondes", False), ("Plus de 10 secondes", False)],
)
def test_marge_du_vainqueur(issue, gagne):
    assert _juger("marge-du-vainqueur", issue) is gagne


# --------------------------------------------------------------------------- #
#  Tour le plus rapide
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    ("marche", "issue", "gagne"),
    [
        ("tour-le-plus-rapide", "G.Russell", True),
        ("tour-le-plus-rapide", "M.Verstappen", False),
        ("tour-le-plus-rapide-vainqueur", "G.Russell", True),
        ("ecurie-realisant-le-tour-le-plus-rapide", "Mercedes", True),
        ("ecurie-realisant-le-tour-le-plus-rapide", "Ferrari", False),
        ("voiture-realisant-le-tour-le-plus-rapide", "Mercedes", True),
        ("voiture-realisant-le-tour-le-plus-rapide", "G.Russell", True),
        ("voiture-realisant-le-tour-le-plus-rapide", "Red Bull", False),
    ],
)
def test_tour_le_plus_rapide(marche, issue, gagne):
    assert _juger(marche, issue) is gagne


def test_tour_le_plus_rapide_issue_illisible_en_attente():
    assert _juger("tour-le-plus-rapide-vainqueur", "Oui") is None


# --------------------------------------------------------------------------- #
#  Les 2 voitures sur le podium
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(("issue", "gagne"), [("Red Bull", True), ("Mercedes", False)])
def test_les_deux_voitures_sur_le_podium(issue, gagne):
    assert _juger("les-2-voitures-sur-le-podium", issue) is gagne


# --------------------------------------------------------------------------- #
#  Face-à-face
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    ("duel", "issue", "gagne"),
    [
        # Les deux classés : Russell 1er, Antonelli 5e.
        (("AK.Antonelli", "G.Russell"), "G.Russell", True),
        (("AK.Antonelli", "G.Russell"), "AK.Antonelli", False),
        # Bottas classé 16e malgré son abandon, Pérez 14e.
        (("S.Perez", "V.Bottas"), "S.Perez", True),
        # Un seul classé : Hamilton 6e, Norris non classé.
        (("L.Hamilton", "L.Norris"), "L.Hamilton", True),
        # Aucun classé : Colapinto 36 tours, Gasly 35.
        (("Franco Colapinto", "P.Gasly"), "Franco Colapinto", True),
        (("Franco Colapinto", "P.Gasly"), "P.Gasly", False),
    ],
)
def test_face_a_face(duel, issue, gagne):
    assert _juger("face-a-face-duel", issue, options=duel) is gagne


def test_face_a_face_aucun_classe_tours_egaux_en_attente():
    # Norris et Gasly abandonnent tous deux au 35e tour.
    assert _juger("face-a-face-duel", "L.Norris", options=("L.Norris", "P.Gasly")) is None


def test_face_a_face_sans_issues_soeurs_en_attente():
    assert _juger("face-a-face-duel", "G.Russell") is None


# --------------------------------------------------------------------------- #
#  Écurie qui marque le plus de points
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(("issue", "gagne"), [("Mercedes", True), ("Red Bull", False)])
def test_ecurie_la_plus_marquante_bakou(issue, gagne):
    assert _juger("ecurie-qui-marque-le-plus-de-points", issue) is gagne


@pytest.mark.parametrize(
    ("valeur", "diviseur", "attendu"),
    [(30, 2, 15), (25, 2, 13), (10, 3, 3), (20, 3, 7), (45, 1, 45)],
)
def test_points_partages_arrondis_a_l_entier(valeur, diviseur, attendu):
    assert P.points_partages(valeur, diviseur) == attendu


# --------------------------------------------------------------------------- #
#  Filtrage au scraping
# --------------------------------------------------------------------------- #


def _cote(marche: str, pilote: str = "X", identifiant: str = "o1") -> Cote:
    return Cote(marche=marche, libelle_marche=marche, pilote=pilote, valeur=20,
                id_outcome_unibet=identifiant)


def test_scraper_ecarte_les_marches_non_evaluables(caplog):
    cotes = [
        _cote("vainqueur", "G.Russell", "o1"),
        _cote("face-a-face-g-russell-ak-antonelli", "G.Russell", "o2"),
        _cote("premier-abandon", "L.Norris", "o3"),
        _cote("marche-jamais-vu", "Oui", "o4"),
        _cote("marche-jamais-vu", "Non", "o5"),
    ]
    import logging

    journal = logging.getLogger("uvicorn.error")
    journal.disabled = False
    with caplog.at_level(logging.WARNING, logger="uvicorn.error"):
        gardees = filtrer_evaluables("GP test", cotes)

    assert [c.id_outcome_unibet for c in gardees] == ["o1", "o2"]
    assert "2 marché(s) écarté(s)" in caplog.text
    assert "marche-jamais-vu" in caplog.text and "premier-abandon" in caplog.text


# --------------------------------------------------------------------------- #
#  Bonus identique à un pronostic obligatoire (C4)
# --------------------------------------------------------------------------- #

COTES_SAISIE = {
    "v-rus": {"marche": "vainqueur", "pilote": "G.Russell"},
    "v-ant": {"marche": "vainqueur", "pilote": "AK.Antonelli"},
    "v-lec": {"marche": "vainqueur", "pilote": "C.Leclerc"},
    "p-rus": {"marche": "podium", "pilote": "G.Russell"},
    "p-ant": {"marche": "podium", "pilote": "AK.Antonelli"},
    "p-ver": {"marche": "podium", "pilote": "M.Verstappen"},
    "p-lec": {"marche": "podium", "pilote": "C.Leclerc"},
    "t6-ant": {"marche": "top-6", "pilote": "AK.Antonelli"},
}
OBLIGATOIRES = ("v-rus", "p-ant", "p-ver")


@pytest.mark.parametrize(
    "bonus",
    [
        "p-ant",  # Pays-Bas 48f08402 : même issue que le podium
        "v-rus",  # Espagne 76b78d5c : même issue que le vainqueur
        "v-ant",  # Bakou 32b03d07 : pilote du podium repris en vainqueur
        "p-rus",  # vainqueur repris en podium
    ],
)
def test_bonus_reprenant_un_obligatoire_refuse(bonus):
    with pytest.raises(HTTPException) as refus:
        exiger_bonus_distincts_des_obligatoires(COTES_SAISIE, [bonus], OBLIGATOIRES)
    assert refus.value.status_code == 422
    assert "reprend un pilote déjà choisi" in refus.value.detail


@pytest.mark.parametrize("bonus", ["v-lec", "p-lec", "t6-ant"])
def test_bonus_distinct_accepte(bonus):
    exiger_bonus_distincts_des_obligatoires(COTES_SAISIE, [bonus], OBLIGATOIRES)
