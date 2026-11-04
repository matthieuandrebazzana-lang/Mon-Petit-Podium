"""Un pronostic sur un pilote non engagé est perdu (`metier.md` §4, `decisions.md` §32).

Au GP du Mexique 2026, Esteban Ocon (n°31) n'est pas engagé : Ryo Hirakawa
(n°50) le remplace. Unibet liste pourtant « E.Ocon ». Les engagés sont connus
avant la fermeture des pronostics, donc le pari est perdu — à condition que
le pilote soit RECONNU par le référentiel, et que la liste des engagés fasse foi.
"""

import asyncio

from app.calcul import points as P
from app.jobs import resultats as job
from test_remplacants import _cote, _donnees_mexique, _engages_mexique


def _bonus(identifiant: str, outcome: str) -> dict:
    return {"id": identifiant, "type": "bonus", "id_outcome_unibet": outcome}


def _podium(identifiant: str, premier: str, second: str) -> dict:
    return {
        "id": identifiant,
        "type": "podium",
        "id_outcome_unibet": premier,
        "pronostic_podium": {"pilote_1": premier, "pilote_2": second},
    }


def _juger(pronostics, cotes, donnees=None):
    return P.calculer(pronostics, cotes, donnees or _donnees_mexique())


# --------------------------------------------------------------------------- #
#  Titulaire absent → perdu
# --------------------------------------------------------------------------- #


def test_titulaire_absent_perdu_sur_chaque_marche_pilote():
    marches = (
        "vainqueur",
        "top-6",
        "top-10",
        "tour-le-plus-rapide",
        "tour-le-plus-rapide-vainqueur",
        "voiture-realisant-le-tour-le-plus-rapide",
    )
    cotes = {f"o-{m}": _cote(f"o-{m}", m, "E.Ocon", 220) for m in marches}
    pronostics = [_bonus(f"p-{m}", f"o-{m}") for m in marches]
    pronostics[0]["type"] = "vainqueur"

    attributions, en_attente = _juger(pronostics, cotes)

    assert en_attente == []
    assert {(a.points, a.statut, a.reussi) for a in attributions} == {(0, P.PERDU, False)}
    assert all("pilote non engagé" in a.detail for a in attributions)


def test_titulaire_absent_perdu_meme_sans_tours():
    # Les tours manquent : un engagé attendrait, l'absent est perdu quand même.
    donnees = _donnees_mexique()
    cotes = {"o": _cote("o", "tour-le-plus-rapide", "E.Ocon")}
    attributions, en_attente = _juger([_bonus("p", "o")], cotes, donnees)
    assert en_attente == []
    assert [a.statut for a in attributions] == [P.PERDU]


def test_titulaire_absent_sans_alerte(monkeypatch):
    ecrites = []

    async def upserter(_table, lignes, _cle):
        ecrites.extend(ligne["type"] for ligne in lignes)

    async def supprimer(_table, _filtre):
        return None

    monkeypatch.setattr(job, "upserter", upserter)
    monkeypatch.setattr(job, "supprimer", supprimer)

    cotes = {"o": _cote("o", "top-10", "E.Ocon", 36)}
    pronostics = [_bonus("p", "o")]
    attributions, _ = _juger(pronostics, cotes)
    asyncio.run(
        job.signaler_en_attente("gp", "GP du Mexique", pronostics, attributions, cotes, _donnees_mexique())
    )
    assert ecrites == []


def test_figeage_ne_signale_pas_le_titulaire_absent():
    cotes = [_cote("o-top", "top-10", "E.Ocon"), _cote("o-v", "vainqueur", "Ocon, Esteban")]
    resultat = P.correspondance(cotes, _engages_mexique())
    assert resultat.non_reconnus == []
    assert resultat.rattachements == []


# --------------------------------------------------------------------------- #
#  Remplaçant reconnu → jugé normalement
# --------------------------------------------------------------------------- #


def test_remplacant_juge_normalement():
    # Hirakawa finit 10ᵉ : son top 10 paie, son top 6 non — sur la course.
    cotes = {
        "o-10": _cote("o-10", "top-10", "Hirakawa, Ryo", 95),
        "o-6": _cote("o-6", "top-6", "Hirakawa, Ryo", 450),
    }
    attributions, en_attente = _juger([_bonus("p-10", "o-10"), _bonus("p-6", "o-6")], cotes)
    assert en_attente == []
    assert {a.pronostic_id: (a.points, a.statut) for a in attributions} == {
        "p-10": (95, P.GAGNE),
        "p-6": (0, P.PERDU),
    }
    assert "non engagé" not in " ".join(a.detail for a in attributions)


def test_un_engage_n_est_jamais_absent():
    course = P.analyser(_donnees_mexique())
    assert course.titulaire_absent("M.Verstappen") is None
    assert course.titulaire_absent("Hirakawa, Ryo") is None
    assert course.titulaire_absent("E.Ocon") == 31


def test_un_pilote_classe_n_est_jamais_absent():
    # Absent de /drivers mais présent au classement : il a couru, la liste est
    # incomplète. Rien n'est jugé perdu.
    donnees = _donnees_mexique()
    donnees["session_result"].append(
        {"driver_number": 31, "position": 22, "number_of_laps": 70, "points": 0,
         "dnf": False, "dns": False, "dsq": False, "gap_to_leader": "+1 LAP"}
    )
    assert P.analyser(donnees).titulaire_absent("E.Ocon") is None


# --------------------------------------------------------------------------- #
#  Libellé inconnu ou ambigu → alerte, jamais perdu
# --------------------------------------------------------------------------- #


def test_libelle_inconnu_reste_en_attente_avec_alerte():
    cotes = {"o": _cote("o", "top-10", "Z.Inventé")}
    pronostics = [_bonus("p", "o")]
    attributions, en_attente = _juger(pronostics, cotes)
    assert attributions == [] and len(en_attente) == 1

    diagnostic = P.diagnostiquer_en_attente(pronostics, attributions, cotes, _donnees_mexique())
    assert [(i["libelle"], i["raison"]) for i in diagnostic.non_reconnus] == [
        ("Z.Inventé", "Aucun engagé ne porte ce nom.")
    ]


def test_libelle_ambigu_n_est_pas_un_absent():
    donnees = _donnees_mexique()
    donnees["pilotes"]["47"] = {"nom": "Mick SCHUMACHER", "prenom": "Mick",
                                "nom_famille": "Schumacher", "acronyme": "MSC", "equipe": "Haas"}
    donnees["pilotes"]["99"] = {"nom": "Michael SCHUMACHER", "prenom": "Michael",
                                "nom_famille": "Schumacher", "acronyme": "SCH", "equipe": "Ferrari"}
    cotes = {"o": _cote("o", "top-10", "M.Schumacher")}
    attributions, en_attente = _juger([_bonus("p", "o")], cotes, donnees)
    assert attributions == [] and len(en_attente) == 1


# --------------------------------------------------------------------------- #
#  Engagés indisponibles → alerte, jamais perdu
# --------------------------------------------------------------------------- #


def test_engages_indisponibles():
    donnees = _donnees_mexique()
    donnees["pilotes"] = {}
    cotes = {"o": _cote("o", "top-10", "E.Ocon")}
    pronostics = [_bonus("p", "o")]
    attributions, en_attente = _juger(pronostics, cotes, donnees)
    assert attributions == [] and len(en_attente) == 1

    diagnostic = P.diagnostiquer_en_attente(pronostics, attributions, cotes, donnees)
    assert [i["raison"] for i in diagnostic.non_reconnus] == [
        "Liste des engagés indisponible ou incomplète : rien n'est jugé."
    ]


def test_engages_incomplets():
    # Une liste qui ne couvre pas tout le classement ne prouve aucune absence.
    donnees = _donnees_mexique()
    del donnees["pilotes"]["44"]
    cotes = {"o": _cote("o", "top-10", "E.Ocon")}
    attributions, en_attente = _juger([_bonus("p", "o")], cotes, donnees)
    assert attributions == [] and len(en_attente) == 1


# --------------------------------------------------------------------------- #
#  Podium : chaque pilote pour son compte
# --------------------------------------------------------------------------- #


def test_podium_un_absent_l_autre_sur_le_podium():
    # Verstappen gagne : sa moitié paie, celle d'Ocon est perdue.
    cotes = {
        "o-ver": _cote("o-ver", "podium", "M.Verstappen", 14),
        "o-oco": _cote("o-oco", "podium", "E.Ocon", 300),
    }
    attributions, en_attente = _juger([_podium("p", "o-ver", "o-oco")], cotes)
    assert en_attente == []
    [attribution] = attributions
    assert (attribution.points, attribution.podium, attribution.statut) == (14, (14, 0), P.GAGNE)


def test_podium_un_absent_l_autre_hors_podium():
    # Hamilton 7ᵉ : les deux moitiés sont perdues.
    cotes = {
        "o-oco": _cote("o-oco", "podium", "E.Ocon", 300),
        "o-ham": _cote("o-ham", "podium", "L.Hamilton", 40),
    }
    attributions, _ = _juger([_podium("p", "o-oco", "o-ham")], cotes)
    [attribution] = attributions
    assert (attribution.points, attribution.podium, attribution.statut) == (0, (0, 0), P.PERDU)


def test_podium_un_absent_l_autre_inconnu_reste_en_attente():
    cotes = {
        "o-oco": _cote("o-oco", "podium", "E.Ocon", 300),
        "o-z": _cote("o-z", "podium", "Z.Inventé", 40),
    }
    attributions, en_attente = _juger([_podium("p", "o-oco", "o-z")], cotes)
    assert attributions == [] and len(en_attente) == 1


# --------------------------------------------------------------------------- #
#  Face-à-face : non décidé, reste en attente
# --------------------------------------------------------------------------- #


def test_face_a_face_avec_un_absent_non_juge():
    marche = "face-a-face-o-bearman-e-ocon"
    cotes = {
        "o-bea": _cote("o-bea", marche, "O.Bearman", 12),
        "o-oco": _cote("o-oco", marche, "E.Ocon", 30),
    }
    attributions, en_attente = _juger([_bonus("p1", "o-bea"), _bonus("p2", "o-oco")], cotes)
    assert attributions == [] and len(en_attente) == 2
    assert not P.absence_jugee(marche)
    assert P.absence_jugee("top-10") and P.absence_jugee("vainqueur")
    assert not P.absence_jugee("ecurie-vainqueur")
