"""Identifiants canoniques des issues (audit §5.1, migration 26).

Au figeage, chaque issue pilote ou écurie est rattachée à un engagé du GP
(`points.correspondance`) ; au calcul, l'identifiant passe avant le libellé
(`points.rattacher_identifiants`). Les engagés viennent de la session de
qualification d'OpenF1 — ici, de l'index `pilotes` des fixtures, qui a la même
forme (`openf1._index_pilotes`) et les mêmes baquets.
"""

import asyncio
import copy

import pytest

from app.calcul import points as P
from app.jobs import rattachement as job
from conftest import GPS, charger_gp


def _engages(nom: str) -> dict:
    return charger_gp(nom)["donnees_brutes"]["pilotes"]


def _cote(identifiant: str, marche: str, pilote: str, valeur: int = 20) -> dict:
    return {"id_outcome_unibet": identifiant, "marche": marche, "pilote": pilote, "valeur": valeur}


def _par_issue(correspondance: P.Correspondance) -> dict[str, dict]:
    return {r["id_outcome_unibet"]: r for r in correspondance.rattachements}


# --------------------------------------------------------------------------- #
#  Correspondance au figeage
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize("nom", GPS)
def test_toutes_les_issues_des_fixtures_sont_rattachees(nom):
    gp = charger_gp(nom)
    resultat = P.correspondance(gp["cotes"].values(), gp["donnees_brutes"]["pilotes"])

    assert resultat.non_reconnus == []
    rattachees = _par_issue(resultat)
    for identifiant, cote in gp["cotes"].items():
        nature = P.nature_des_issues(cote["marche"])
        if nature is None:
            # Oui/Non, tranches d'écart, nationalités : rien à rattacher.
            assert identifiant not in rattachees
            continue
        entree = rattachees[identifiant]
        if nature == P.PILOTE:
            assert entree["numero_pilote"] is not None and entree["ecurie_id"] is None
        if nature == P.ECURIE:
            assert entree["ecurie_id"] is not None and entree["numero_pilote"] is None


def _numero(nom: str, marche: str, libelle: str) -> int | None:
    resultat = P.correspondance([_cote("o", marche, libelle)], _engages(nom))
    return resultat.rattachements[0]["numero_pilote"] if resultat.rattachements else None


@pytest.mark.parametrize(
    ("nom", "marche", "libelle", "numero"),
    [
        # Deux initiales chez Unibet, « Kimi » chez OpenF1 : alias de pilotes.py.
        ("pays-bas", "vainqueur", "AK.Antonelli", 12),
        ("azerbaidjan", "podium", "AK.Antonelli", 12),
        # Suffixe « Jr » chez Unibet seulement : alias de pilotes.py.
        ("espagne", "top-10", "C.Sainz Jr", 55),
        ("azerbaidjan", "vainqueur", "C.Sainz Jr", 55),
        # Prénom en entier, dans un face-à-face.
        ("italie", "face-a-face-franco-colapinto-p-gasly", "Franco Colapinto", 43),
        ("azerbaidjan", "podium", "I.Hadjar", 6),
    ],
)
def test_libelles_difficiles(nom, marche, libelle, numero):
    assert _numero(nom, marche, libelle) == numero


def test_les_engages_viennent_de_la_session_pas_de_la_grille():
    # Espagne : Lawson court chez Red Bull, Hadjar n'est pas engagé. Bakou : Hadjar
    # a repris son baquet, Lawson est revenu chez Racing Bulls, Tsunoda n'a plus
    # de volant. La correspondance suit chaque fois la session du GP.
    assert _numero("espagne", "vainqueur", "L.Lawson") == 30
    assert _numero("espagne", "vainqueur", "I.Hadjar") is None
    assert _numero("azerbaidjan", "vainqueur", "I.Hadjar") == 6
    assert _numero("azerbaidjan", "vainqueur", "Y.Tsunoda") is None

    assert _engages("espagne")["30"]["equipe"] == "Red Bull Racing"
    assert _engages("azerbaidjan")["30"]["equipe"] == "Racing Bulls"
    assert _engages("azerbaidjan")["6"]["equipe"] == "Red Bull Racing"


def test_identifiants_d_ecurie():
    cotes = [
        _cote("rb", "ecurie-vainqueur", "Red Bull"),
        _cote("vcarb", "ecurie-qui-marque-le-plus-de-points", "Racing Bulls"),
        _cote("audi", "ecurie-vainqueur", "Audi F1 Team"),
        _cote("haas", "ecurie-vainqueur", "Haas"),
        _cote("meilleur", "voiture-realisant-le-tour-le-plus-rapide", "Mercedes"),
        _cote("pilote", "voiture-realisant-le-tour-le-plus-rapide", "G.Russell"),
    ]
    rattachees = _par_issue(P.correspondance(cotes, _engages("azerbaidjan")))

    assert rattachees["rb"]["ecurie_id"] == "red-bull-racing"
    assert rattachees["vcarb"]["ecurie_id"] == "racing-bulls"
    assert rattachees["audi"]["ecurie_id"] == "audi"
    assert rattachees["haas"]["ecurie_id"] == "haas-f1-team"
    # « Voiture » : un pilote ou une écurie, selon ce que nomme l'issue.
    assert rattachees["meilleur"] == {
        "id_outcome_unibet": "meilleur", "numero_pilote": None, "ecurie_id": "mercedes",
    }
    assert rattachees["pilote"]["numero_pilote"] == 63


def test_un_libelle_invente_remonte_non_reconnu():
    cotes = [
        _cote("o-invente", "vainqueur", "Z.Inventé"),
        _cote("o-brawn", "ecurie-vainqueur", "Brawn GP"),
        _cote("o-oui", "vainqueur-course-qualification-et-tour-le-plus-rapide", "Oui"),
        _cote("o-russell", "vainqueur", "G.Russell"),
    ]
    resultat = P.correspondance(cotes, _engages("azerbaidjan"))

    assert resultat.non_reconnus == [
        {"id_outcome_unibet": "o-invente", "marche": "vainqueur", "libelle": "Z.Inventé",
         "nature": P.PILOTE},
        {"id_outcome_unibet": "o-brawn", "marche": "ecurie-vainqueur", "libelle": "Brawn GP",
         "nature": P.ECURIE},
    ]
    assert list(_par_issue(resultat)) == ["o-russell"]


def test_chaque_marche_exact_declare_sa_nature():
    assert set(P._NATURES_EXACTES) == set(P._EXACTS)
    assert len(P._NATURES_FAMILLES) == len(P._FAMILLES)
    assert P.nature_des_issues("top-6") == P.PILOTE
    assert P.nature_des_issues("face-a-face-c-leclerc-l-hamilton") == P.PILOTE
    assert P.nature_des_issues("red-bull-les-2-voitures-dans-le-top-10") is None
    assert P.nature_des_issues("premier-abandon") is None


# --------------------------------------------------------------------------- #
#  Évaluation par identifiant
# --------------------------------------------------------------------------- #


def _cotes_rattachees(gp: dict) -> dict[str, dict]:
    cotes = copy.deepcopy(gp["cotes"])
    for entree in P.correspondance(cotes.values(), gp["donnees_brutes"]["pilotes"]).rattachements:
        cotes[entree["id_outcome_unibet"]].update(
            numero_pilote=entree["numero_pilote"], ecurie_id=entree["ecurie_id"]
        )
    return cotes


def _verdicts(pronostics, cotes, donnees) -> dict:
    attributions, en_attente = P.calculer(pronostics, cotes, donnees)
    return {
        **{a.pronostic_id: (a.points, a.statut) for a in attributions},
        **{ligne.split(" ", 1)[0]: None for ligne in en_attente},
    }


@pytest.mark.parametrize("nom", GPS)
def test_identifiants_et_libelles_rendent_les_memes_verdicts(nom):
    gp = charger_gp(nom)
    par_libelle = _verdicts(gp["pronostics"], gp["cotes"], gp["donnees_brutes"])
    par_identifiant = _verdicts(gp["pronostics"], _cotes_rattachees(gp), gp["donnees_brutes"])

    assert par_identifiant == par_libelle
    juges = {pid: points for pid, points in gp["attendus"].items() if points is not None}
    assert {pid: par_identifiant[pid][0] for pid in juges} == juges


def _pari(identifiant: str) -> dict:
    return {"id": "p1", "type": "bonus", "id_outcome_unibet": identifiant}


def test_l_identifiant_passe_avant_le_libelle():
    gp = charger_gp("azerbaidjan")
    # Libellé que rien ne rapproche, numéro de Russell, vainqueur à Bakou.
    cotes = {"o": {**_cote("o", "vainqueur", "Libellé abîmé", 13), "numero_pilote": 63}}
    attributions, _ = P.calculer([_pari("o")], cotes, gp["donnees_brutes"])
    assert attributions[0].points == 13

    # Même chose pour une écurie : Mercedes marque le plus de points à Bakou.
    cotes = {"o": {**_cote("o", "ecurie-qui-marque-le-plus-de-points", "Écurie abîmée", 30),
                   "ecurie_id": "mercedes"}}
    attributions, _ = P.calculer([_pari("o")], cotes, gp["donnees_brutes"])
    assert attributions[0].points == 30


def test_un_identifiant_absent_de_la_course_laisse_la_main_au_libelle():
    gp = charger_gp("azerbaidjan")
    # Le 22 (Tsunoda) n'est pas à Bakou : le libellé « G.Russell » décide.
    cotes = {"o": {**_cote("o", "vainqueur", "G.Russell", 13), "numero_pilote": 22}}
    attributions, _ = P.calculer([_pari("o")], cotes, gp["donnees_brutes"])
    assert attributions[0].points == 13


# --------------------------------------------------------------------------- #
#  Le job de rattachement
# --------------------------------------------------------------------------- #


class BaseSimulee:
    def __init__(self, cotes: dict):
        self.cotes = cotes
        self.appels: list[tuple[str, dict]] = []
        self.alertes: list[dict] = []

    async def selectionner(self, table: str, _parametres: dict) -> list[dict]:
        if table == "grands_prix":
            return [{"id": "gp", "nom": "GP Azerbaïdjan",
                     "date_qualifications": "2026-09-19T12:00:00+00:00",
                     "date_course": "2026-09-20T11:00:00+00:00"}]
        if table == "cotes":
            return list(copy.deepcopy(self.cotes).values())
        raise AssertionError(table)

    async def appeler_fonction(self, nom: str, arguments: dict):
        self.appels.append((nom, arguments))
        return {"rattachees": len(arguments["p_rattachements"]), "non_reconnues": 0}

    async def upserter(self, table: str, lignes: list[dict], _cle: str):
        assert table == "alertes_admin"
        self.alertes.extend(lignes)
        return lignes


@pytest.fixture
def base(monkeypatch):
    cotes = copy.deepcopy(charger_gp("azerbaidjan")["cotes"])
    cotes["o-invente"] = _cote("o-invente", "vainqueur", "Z.Inventé")
    simulee = BaseSimulee(cotes)
    for nom in ("selectionner", "appeler_fonction", "upserter"):
        monkeypatch.setattr(job, nom, getattr(simulee, nom))

    async def engages(_nom, _reference):
        return _engages("azerbaidjan")

    monkeypatch.setattr(job, "engages", engages)
    return simulee


def test_le_job_ecrit_les_identifiants_et_remonte_le_libelle_inconnu(base):
    rapport = asyncio.run(job.rattacher("gp"))

    [(nom, arguments)] = base.appels
    assert nom == "rattacher_issues"
    assert [issue["libelle"] for issue in arguments["p_non_reconnus"]] == ["Z.Inventé"]
    assert arguments["p_non_reconnus"][0]["marche"] == "vainqueur"
    assert rapport["non_reconnues"] == arguments["p_non_reconnus"]
    assert rapport["engages"] == 22


def test_un_echec_openf1_ne_bloque_rien_et_devient_une_alerte(base, monkeypatch):
    async def muette(_nom, _reference):
        raise job.ErreurOpenF1("drivers : statut 503.")

    monkeypatch.setattr(job, "engages", muette)
    asyncio.run(job.rattacher_sans_echec("gp", "GP Azerbaïdjan"))

    assert base.appels == []
    assert [(a["type"], a["derniere_erreur"]) for a in base.alertes] == [
        (job.RATTACHEMENT_IMPOSSIBLE, "drivers : statut 503.")
    ]
