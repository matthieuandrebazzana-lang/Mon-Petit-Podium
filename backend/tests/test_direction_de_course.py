"""Safety car, VSC, drapeau rouge et meilleur tour, sur les vrais messages OpenF1.

OpenF1 écrit « VSC DEPLOYED » / « VSC ENDING », jamais « VIRTUAL SAFETY CAR » :
c'est la cause C6 de l'audit, corrigée en 0.77.0.
"""

import pytest

from app.calcul import points as P
from conftest import GPS, charger_gp

# Constaté dans race_control et dans `laps` (audit §4.2 et §4.4).
ATTENDU = {
    #               safety car, VSC,  drapeau rouge, meilleur tour
    "pays-bas": (False, True, False, 16),
    "italie": (True, True, False, 12),
    "espagne": (False, True, False, 63),
    "azerbaidjan": (True, False, False, 63),
}


def _course(nom: str) -> P.Course:
    return P.analyser(charger_gp(nom)["donnees_brutes"])


def _messages_safety_car(nom: str) -> list[str]:
    return [
        message["message"]
        for message in charger_gp(nom)["donnees_brutes"]["race_control"]
        if message.get("category") == "SafetyCar"
    ]


@pytest.mark.parametrize("nom", GPS)
def test_vsc_ecrit_en_abrege_chez_openf1(nom):
    messages = _messages_safety_car(nom)
    assert not any("VIRTUAL" in message.upper() for message in messages)
    assert ("VSC DEPLOYED" in messages) == ATTENDU[nom][1]


@pytest.mark.parametrize("nom", GPS)
def test_safety_car(nom):
    assert _course(nom).safety_car is ATTENDU[nom][0]


@pytest.mark.parametrize("nom", GPS)
def test_safety_car_virtuel(nom):
    assert _course(nom).virtual_safety_car is ATTENDU[nom][1]


@pytest.mark.parametrize("nom", GPS)
def test_drapeau_rouge(nom):
    assert _course(nom).drapeau_rouge is ATTENDU[nom][2]


@pytest.mark.parametrize("nom", GPS)
def test_meilleur_tour(nom):
    assert _course(nom).meilleur_tour == ATTENDU[nom][3]


@pytest.mark.parametrize(("issue", "gagne"), [("Oui", True), ("Non", False)])
def test_pari_vsc_pays_bas(issue, gagne):
    # Deux VSC aux Pays-Bas : « Oui » gagne, « Non » perd.
    assert P._safety_car_virtuel(_course("pays-bas"), issue) is gagne


def test_vsc_forme_longue_toujours_reconnue():
    course = P.analyser(
        {"race_control": [{"category": "SafetyCar", "message": "VIRTUAL SAFETY CAR DEPLOYED"}]}
    )
    assert course.virtual_safety_car and not course.safety_car


def test_vsc_ending_seul_ne_compte_pas():
    course = P.analyser({"race_control": [{"category": "SafetyCar", "message": "VSC ENDING"}]})
    assert not course.virtual_safety_car
