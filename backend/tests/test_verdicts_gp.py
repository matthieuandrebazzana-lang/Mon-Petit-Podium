"""Non-régression : `calculer()` rejoué sur les quatre Grands Prix 2026 terminés.

Les verdicts attendus sont ceux de la base au 2026-09-26, corrigés à la main au
fil de la saison. Le code actuel les rend tous (audit, méthode) : tout écart ici
est une régression de l'évaluation.
"""

import pytest

from app.calcul.points import calculer
from conftest import AUDIT, GPS, charger_gp

# Les deux pronostics de Bakou que la base laisse en attente (audit §4.1).
TRIPLE = "80cc59ee-ef2a-466c-ae18-fcb1b013f04d"
MARGE = "8cd836f1-c80e-4eb1-9f98-38f302274305"


def _rejouer(nom: str):
    gp = charger_gp(nom)
    attributions, en_attente = calculer(gp["pronostics"], gp["cotes"], gp["donnees_brutes"])
    obtenus = {attribution.pronostic_id: attribution.points for attribution in attributions}
    # `en_attente` est une liste de lignes « {id} ({type}) : {raison} ».
    attente = {ligne.split(" ", 1)[0] for ligne in en_attente}
    return gp, obtenus, attente


@pytest.mark.parametrize("nom", GPS)
def test_verdicts_du_gp(nom):
    gp, obtenus, attente = _rejouer(nom)

    juges = {pid: points for pid, points in gp["attendus"].items() if points is not None}
    assert {pid: obtenus.get(pid) for pid in juges} == juges

    # Rien de ce que la base a jugé ne doit repasser en attente. Les pronostics
    # encore à NULL en base ont leurs propres tests, plus bas.
    en_attente_en_base = {pid for pid, points in gp["attendus"].items() if points is None}
    assert attente <= en_attente_en_base


def test_chaque_pronostic_a_un_verdict_attendu():
    for nom in GPS:
        gp = charger_gp(nom)
        assert {p["id"] for p in gp["pronostics"]} == set(gp["attendus"])


@pytest.mark.xfail(reason=f"{AUDIT} C1 — aucun évaluateur pour le triplé course + pole + meilleur tour")
def test_bakou_triple_oui_gagne():
    # Russell : pole (qualifications, session 11373), victoire et meilleur tour.
    _, obtenus, _ = _rejouer("azerbaidjan")
    assert obtenus.get(TRIPLE) == 50


@pytest.mark.xfail(reason=f"{AUDIT} C1 — « marge-du-vainqueur » non reconnu (le code exige « marge » + « victoire »)")
def test_bakou_marge_plus_de_10_secondes_perdue():
    # Verstappen finit à 0,196 s de Russell.
    _, obtenus, _ = _rejouer("azerbaidjan")
    assert obtenus.get(MARGE) == 0
