"""Chaque marché vu en base a un évaluateur, ou est déclaré non évaluable.

`SLUGS_EN_BASE` est la liste des 39 slugs de la table `cotes` au 2026-09-26
(audit §1). Un slug nouveau vu chez Unibet s'ajoute ici : c'est ce test qui doit
échouer avant qu'on puisse parier sur un marché que le backend ne sait pas juger.
"""

from collections import Counter

import pytest

from app.calcul import points as P
from conftest import AUDIT, charger_gp

EVALUES = (
    "vainqueur",
    "podium",
    "top-6",
    "top-10",
    "ecurie-vainqueur",
    "ecart-du-gagnant",
    "nationalite-du-vainqueur",
    "alpine-les-2-voitures-dans-le-top-10",
    "aston-martin-les-2-voitures-dans-le-top-10",
    "audi-f1-team-les-2-voitures-dans-le-top-10",
    "cadillac-les-2-voitures-dans-le-top-10",
    "ferrari-les-2-voitures-dans-le-top-10",
    "haas-les-2-voitures-dans-le-top-10",
    "mclaren-les-2-voitures-dans-le-top-10",
    "mercedes-amg-les-2-voitures-dans-le-top-10",
    "racing-bulls-team-les-2-voitures-dans-le-top-10",
    "red-bull-les-2-voitures-dans-le-top-10",
    "williams-les-2-voitures-dans-le-top-10",
)

# C3 : capturés par le préfixe « ecurie » / « equipe » et jugés comme « écurie
# du vainqueur ».
MAL_EVALUES = (
    "ecurie-qui-marque-le-plus-de-points",
    "equipe-qui-marque-le-plus-de-points",
    "ecurie-realisant-le-tour-le-plus-rapide",
)

# C1 : aucun évaluateur.
SANS_EVALUATEUR = (
    "marge-du-vainqueur",
    "vainqueur-course-qualification-et-tour-le-plus-rapide",
    "tour-le-plus-rapide",
    "tour-le-plus-rapide-vainqueur",
    "voiture-realisant-le-tour-le-plus-rapide",
    "les-2-voitures-sur-le-podium",
    "face-a-face-a-albon-c-sainz-jr",
    "face-a-face-a-lindblad-l-lawson",
    "face-a-face-a-lindblad-y-tsunoda",
    "face-a-face-ak-antonelli-g-russell",
    "face-a-face-c-leclerc-l-hamilton",
    "face-a-face-f-alonso-l-stroll",
    "face-a-face-franco-colapinto-p-gasly",
    "face-a-face-g-bortoleto-n-hulkenberg",
    "face-a-face-m-verstappen-l-lawson",
    "face-a-face-o-bearman-e-ocon",
    "face-a-face-o-piastri-l-norris",
    "face-a-face-s-perez-v-bottas",
)

SLUGS_EN_BASE = EVALUES + MAL_EVALUES + SANS_EVALUATEUR

XFAIL_C1 = pytest.mark.xfail(reason=f"{AUDIT} C1 — marché sans évaluateur ni entrée « non évaluable »")
XFAIL_C3 = pytest.mark.xfail(reason=f"{AUDIT} C3 — mauvais évaluateur choisi par préfixe")


def test_inventaire_complet():
    assert len(SLUGS_EN_BASE) == len(set(SLUGS_EN_BASE)) == 39


@pytest.mark.parametrize(
    "slug",
    [pytest.param(s, marks=XFAIL_C1) if s in SANS_EVALUATEUR else s for s in SLUGS_EN_BASE],
)
def test_slug_evaluable_ou_declare_non_evaluable(slug):
    # Le registre explicite des marchés non évaluables n'existe pas encore
    # (audit §5.2) : l'étape 2 l'expose sous ce nom.
    non_evaluables = getattr(P, "NON_EVALUABLES", frozenset())
    assert P.validateur(slug) is not None or slug in non_evaluables


@pytest.mark.parametrize("slug", [pytest.param(s, marks=XFAIL_C3) for s in MAL_EVALUES])
def test_slug_pas_juge_comme_ecurie_du_vainqueur(slug):
    assert P.validateur(slug) is not P._ecurie_gagnante


def test_ecurie_vainqueur_garde_son_evaluateur():
    assert P.validateur("ecurie-vainqueur") is P._ecurie_gagnante


# --------------------------------------------------------------------------- #
#  Égalité de points entre écuries — Pays-Bas (C3)
# --------------------------------------------------------------------------- #


def _points_par_ecurie(course: P.Course) -> Counter:
    points = Counter()
    for numero, ligne in course.lignes.items():
        points[course.pilotes[numero]["equipe"]] += ligne.points_fia
    return points


def test_pays_bas_mclaren_et_mercedes_a_egalite():
    course = P.analyser(charger_gp("pays-bas")["donnees_brutes"])
    points = _points_par_ecurie(course)
    assert points["McLaren"] == points["Mercedes"] == 33
    assert max(points.values()) == 33


def _juger_ecurie_la_plus_marquante(libelle: str):
    gp = charger_gp("pays-bas")
    marche = "ecurie-qui-marque-le-plus-de-points"
    cotes = {
        "o-mclaren": {"marche": marche, "pilote": "McLaren", "valeur": 20},
        "o-mercedes": {"marche": marche, "pilote": "Mercedes", "valeur": 30},
        "o-ferrari": {"marche": marche, "pilote": "Ferrari", "valeur": 50},
    }
    outcome = {"McLaren": "o-mclaren", "Mercedes": "o-mercedes", "Ferrari": "o-ferrari"}[libelle]
    pronostic = {"id": "egalite", "type": "bonus", "id_outcome_unibet": outcome}
    attribution, _ = P.points_du_pronostic(pronostic, cotes, P.analyser(gp["donnees_brutes"]))
    return None if attribution is None else attribution.points


def test_pays_bas_ecurie_hors_egalite_perdue():
    # Ferrari (22 pts) n'est pas en tête, quelle que soit la règle d'égalité.
    assert _juger_ecurie_la_plus_marquante("Ferrari") == 0


@pytest.mark.xfail(reason=f"{AUDIT} C3 — jugé « écurie du vainqueur » : Mercedes, à égalité en tête, déclarée perdue")
def test_pays_bas_egalite_mercedes_non_jugee():
    # Règle d'égalité d'Unibet non décidée : une égalité vaut NULL, jamais 0.
    assert _juger_ecurie_la_plus_marquante("Mercedes") is None


@pytest.mark.xfail(reason=f"{AUDIT} C3 — jugé « écurie du vainqueur » : McLaren gagne sans que l'égalité soit tranchée")
def test_pays_bas_egalite_mclaren_non_jugee():
    assert _juger_ecurie_la_plus_marquante("McLaren") is None
