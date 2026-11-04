"""Remplaçants d'un week-end et formes de noms (`bugs-connus.md` §44).

Au GP du Mexique 2026, Ryo Hirakawa (n°50) remplace Esteban Ocon chez Haas.
Unibet l'écrit « Hirakawa, Ryo » — forme qu'aucune clé ne produisait —, OpenF1
« Ryo HIRAKAWA ». Son pronostic « Top 10 » est resté en attente alors qu'il
finit 10ᵉ. Au Brésil, Unibet publie de même « Camara, Rafael ».

Les engagés du Mexique sont ceux de l'Azerbaïdjan, Ocon retiré, Hirakawa ajouté
tel qu'OpenF1 le sert (`/drivers` des sessions 11400 et 11404).
"""

import asyncio
import copy

import pytest
from fastapi.testclient import TestClient

from app.api.deps import exiger_admin
from app.api.routes import admin
from app.calcul import points as P
from app.jobs import resultats as job
from app.main import app
from conftest import charger_gp

HIRAKAWA = {
    "nom": "Ryo HIRAKAWA",
    "prenom": "Ryo",
    "nom_famille": "Hirakawa",
    "acronyme": "HIR",
    "equipe": "Haas F1 Team",
}


def _engages_mexique() -> dict:
    engages = copy.deepcopy(charger_gp("azerbaidjan")["donnees_brutes"]["pilotes"])
    del engages["31"]
    engages["50"] = dict(HIRAKAWA)
    return engages


def _avec(*pilotes: tuple[int, str, str, str]) -> dict:
    """Des engagés fabriqués : (numéro, prénom, nom de famille, écurie)."""
    return {
        str(numero): {
            "nom": f"{prenom} {famille.upper()}",
            "prenom": prenom,
            "nom_famille": famille,
            "acronyme": famille[:3].upper(),
            "equipe": equipe,
        }
        for numero, prenom, famille, equipe in pilotes
    }


def _course(engages: dict) -> P.Course:
    return P.analyser({"pilotes": engages})


# --------------------------------------------------------------------------- #
#  Le rapprochement des noms
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    ("libelle", "numero"),
    [
        # Formes réelles d'Unibet, relevées sur les cotes 2026.
        ("Hirakawa, Ryo", 50),
        ("M.Verstappen", 3),
        ("AK.Antonelli", 12),
        ("C.Sainz Jr", 55),
        ("Franco Colapinto", 43),
        # Formes réelles d'OpenF1 : `full_name`, `broadcast_name`, `name_acronym`.
        ("Ryo HIRAKAWA", 50),
        ("R HIRAKAWA", 50),
        ("HIR", 50),
        # Nom inversé, avec ou sans virgule, initiale derrière le nom.
        ("Verstappen, Max", 3),
        ("Verstappen M.", 3),
        ("HIRAKAWA Ryo", 50),
        ("Sainz Jr., Carlos", 55),
        # Accents et casse.
        ("Hülkenberg, Nico", 27),
        ("N.Hülkenberg", 27),
        ("pérez, sergio", 11),
        # Initiale seule, prénom abrégé.
        ("R. Hirakawa", 50),
        ("Alex Albon", 23),
    ],
)
def test_formes_reconnues(libelle, numero):
    assert _course(_engages_mexique()).pilote_du_libelle(libelle) == numero


@pytest.mark.parametrize(
    "libelle",
    [
        "X.Verstappen",  # une autre initiale ne désigne pas Max
        "Mick Verstappen",  # un autre prénom non plus
        "Verstapen",  # aucune ressemblance approximative
        "Z.Inventé",
        "E.Ocon",  # titulaire remplacé : pas engagé ce week-end
    ],
)
def test_formes_refusees(libelle):
    assert _course(_engages_mexique()).pilote_du_libelle(libelle) is None


def test_accent_absent_d_un_cote_seulement():
    # OpenF1 écrit sans accent, Unibet pourrait l'écrire avec, ou l'inverse.
    engages = _avec((99, "Rafael", "Camara", "Ferrari"), (98, "Nico", "Hülkenberg", "Audi"))
    course = _course(engages)
    assert course.pilote_du_libelle("Câmara, Rafael") == 99
    assert course.pilote_du_libelle("Camara, Rafael") == 99
    assert course.pilote_du_libelle("N.Hulkenberg") == 98


def test_nom_compose():
    course = _course(_avec((21, "Nyck", "de Vries", "AlphaTauri"), (4, "Lando", "Norris", "McLaren")))
    for libelle in ("N.De Vries", "De Vries, Nyck", "Nyck DE VRIES", "N.DeVries", "de-vries"):
        assert course.pilote_du_libelle(libelle) == 21, libelle
    # « Vries » seul n'est pas le nom de famille.
    assert course.pilote_du_libelle("N.Vries") is None


def test_homonymes_et_initiale_ambigue():
    course = _course(
        _avec(
            (47, "Mick", "Schumacher", "Haas F1 Team"),
            (99, "Michael", "Schumacher", "Ferrari"),
            (3, "Max", "Verstappen", "Red Bull Racing"),
        )
    )
    # Même nom, même initiale : ambigu, jamais le premier venu.
    assert course.candidats_du_libelle("M.Schumacher") == (47, 99)
    assert course.pilote_du_libelle("M.Schumacher") is None
    assert course.pilote_du_libelle("Schumacher") is None
    assert course.pilote_du_libelle("Schumacher, M.") is None
    # Le prénom en entier tranche.
    assert course.pilote_du_libelle("Mick Schumacher") == 47
    assert course.pilote_du_libelle("Schumacher, Michael") == 99


# --------------------------------------------------------------------------- #
#  Au figeage : correspondance et alertes
# --------------------------------------------------------------------------- #


def _cote(identifiant: str, marche: str, pilote: str, valeur: int = 20) -> dict:
    return {"id_outcome_unibet": identifiant, "marche": marche, "pilote": pilote, "valeur": valeur}


def test_le_remplacant_est_rattache_sur_tous_ses_marches():
    cotes = [
        _cote("o737456286", "vainqueur", "Hirakawa, Ryo", 5000),
        _cote("o737488980", "podium", "Hirakawa, Ryo", 5000),
        _cote("o737491917", "top-6", "Hirakawa, Ryo", 450),
        _cote("o737507486", "top-10", "Hirakawa, Ryo", 95),
        _cote("o737514628", "tour-le-plus-rapide-vainqueur", "Hirakawa, Ryo", 2000),
    ]
    resultat = P.correspondance(cotes, _engages_mexique())
    assert resultat.non_reconnus == []
    assert {r["numero_pilote"] for r in resultat.rattachements} == {50}


def test_raisons_explicites_des_libelles_non_reconnus():
    engages = _engages_mexique()
    engages["47"] = _avec((47, "Mick", "Schumacher", "Haas F1 Team"))["47"]
    engages["99"] = _avec((99, "Michael", "Schumacher", "Ferrari"))["99"]
    cotes = [
        _cote("o-ocon", "top-10", "E.Ocon"),
        _cote("o-schu", "top-10", "M.Schumacher"),
        _cote("o-z", "top-10", "Z.Inventé"),
    ]
    raisons = {r["id_outcome_unibet"]: r["raison"] for r in P.correspondance(cotes, engages).non_reconnus}
    assert raisons == {
        "o-ocon": "Pilote non engagé ce week-end (n°31 Esteban Ocon, absent des engagés d'OpenF1).",
        "o-schu": "Ambigu : n°47 Mick Schumacher, n°99 Michael Schumacher.",
        "o-z": "Aucun engagé ne porte ce nom.",
    }


def test_le_choix_de_l_admin_passe_avant_la_regle():
    cotes = [_cote("o-z", "top-10", "Z.Inventé"), _cote("o-z2", "vainqueur", "Z.Inventé")]
    manuelles = {"zinvente": {"numero_pilote": 50, "ecurie_id": None}}
    resultat = P.correspondance(cotes, _engages_mexique(), manuelles)
    assert resultat.non_reconnus == []
    assert [r["numero_pilote"] for r in resultat.rattachements] == [50, 50]


def test_un_choix_perime_rend_la_main_a_la_regle():
    # Le n°31 n'est pas engagé au Mexique : le choix est ignoré, l'alerte reste.
    cotes = [_cote("o-z", "top-10", "Z.Inventé")]
    resultat = P.correspondance(cotes, _engages_mexique(), {"zinvente": {"numero_pilote": 31}})
    assert [r["id_outcome_unibet"] for r in resultat.non_reconnus] == ["o-z"]


def test_choix_d_une_ecurie():
    cotes = [_cote("o-e", "ecurie-vainqueur", "Écurie américaine")]
    manuelles = {"ecurieamericaine": {"numero_pilote": None, "ecurie_id": "haas-f1-team"}}
    resultat = P.correspondance(cotes, _engages_mexique(), manuelles)
    assert resultat.rattachements == [
        {"id_outcome_unibet": "o-e", "numero_pilote": None, "ecurie_id": "haas-f1-team"}
    ]


# --------------------------------------------------------------------------- #
#  Au calcul : le pronostic du Mexique, et aucun « en attente » sans alerte
# --------------------------------------------------------------------------- #


def _donnees_mexique() -> dict:
    lignes = [
        {"driver_number": numero, "position": rang, "number_of_laps": 71, "points": 0,
         "dnf": False, "dns": False, "dsq": False, "gap_to_leader": None if rang == 1 else 1.0}
        for rang, numero in enumerate(
            (3, 16, 1, 63, 81, 12, 44, 6, 87, 50, 55, 23, 14, 18, 10, 43, 27, 5, 11, 77, 30, 41),
            start=1,
        )
    ]
    return {"session_result": lignes, "pilotes": _engages_mexique()}


def test_le_top_10_de_hirakawa_rapporte_95_points():
    cotes = {"o737507486": _cote("o737507486", "top-10", "Hirakawa, Ryo", 95)}
    pronostic = {"id": "p1", "type": "bonus", "id_outcome_unibet": "o737507486"}
    attributions, en_attente = P.calculer([pronostic], cotes, _donnees_mexique())
    assert en_attente == []
    assert [(a.points, a.statut) for a in attributions] == [(95, P.GAGNE)]


def test_le_numero_pose_par_la_migration_35_suffit_au_calcul():
    # Libellé que la règle ne reconnaîtrait pas : seul le numéro de la cote juge.
    cotes = {"o": {**_cote("o", "top-10", "?? inconnu ??", 95), "numero_pilote": 50}}
    pronostic = {"id": "p1", "type": "bonus", "id_outcome_unibet": "o"}
    attributions, _ = P.calculer([pronostic], cotes, _donnees_mexique())
    assert [a.points for a in attributions] == [95]


def test_chaque_pronostic_en_attente_a_une_cause():
    cotes = {
        "o-ocon": _cote("o-ocon", "top-10", "E.Ocon"),
        "o-triple": _cote("o-triple", "vainqueur-course-qualification-et-tour-le-plus-rapide", "Oui"),
        "o-ham": _cote("o-ham", "podium", "L.Hamilton"),
        "o-z": _cote("o-z", "podium", "Z.Inventé"),
    }
    pronostics = [
        {"id": "p-ocon", "type": "bonus", "id_outcome_unibet": "o-ocon"},
        # Qualifications absentes des données : le triplé ne peut pas se juger.
        {"id": "p-triple", "type": "bonus", "id_outcome_unibet": "o-triple"},
        {"id": "p-podium", "type": "podium", "id_outcome_unibet": "o-ham",
         "pronostic_podium": {"pilote_1": "o-ham", "pilote_2": "o-z"}},
    ]
    donnees = _donnees_mexique()
    attributions, en_attente = P.calculer(pronostics, cotes, donnees)
    assert len(en_attente) == 3

    diagnostic = P.diagnostiquer_en_attente(pronostics, attributions, cotes, donnees)
    assert [(i["id_outcome_unibet"], i["libelle"]) for i in diagnostic.non_reconnus] == [
        ("o-ocon", "E.Ocon"),
        ("o-z", "Z.Inventé"),
    ]
    assert len(diagnostic.autres) == 1 and diagnostic.autres[0].startswith("bonus : ")


def test_aucune_alerte_quand_tout_est_juge(monkeypatch):
    ecrites, effacees = [], []

    async def upserter(table, lignes, _cle):
        ecrites.extend((table, ligne["type"]) for ligne in lignes)

    async def supprimer(table, filtre):
        effacees.append((table, filtre["type"]))

    monkeypatch.setattr(job, "upserter", upserter)
    monkeypatch.setattr(job, "supprimer", supprimer)

    cotes = {"o737507486": _cote("o737507486", "top-10", "Hirakawa, Ryo", 95)}
    pronostics = [{"id": "p1", "type": "bonus", "id_outcome_unibet": "o737507486"}]
    attributions, _ = P.calculer(pronostics, cotes, _donnees_mexique())
    asyncio.run(job.signaler_en_attente("gp", "GP du Mexique", pronostics, attributions, cotes, _donnees_mexique()))
    assert ecrites == []
    assert effacees == [("alertes_admin", f"eq.{job.PRONOSTICS_EN_ATTENTE}")]

    # Le même pronostic sur un libellé inconnu : une alerte de libellé, avec sa raison.
    cotes = {"o": _cote("o", "top-10", "Z.Inventé")}
    pronostics = [{"id": "p1", "type": "bonus", "id_outcome_unibet": "o"}]
    attributions, _ = P.calculer(pronostics, cotes, _donnees_mexique())
    asyncio.run(job.signaler_en_attente("gp", "GP du Mexique", pronostics, attributions, cotes, _donnees_mexique()))
    assert ecrites == [("alertes_admin", job.LIBELLE_NON_RECONNU)]


# --------------------------------------------------------------------------- #
#  Le profil admin : engagés et résolution
# --------------------------------------------------------------------------- #

GP_ID = "6cbac282-10ac-45c9-a382-05f4a4e05fa4"


@pytest.fixture
def client(monkeypatch):
    app.dependency_overrides[exiger_admin] = lambda: "00000000-0000-0000-0000-000000000001"
    traces: dict = {"choix": [], "rattache": 0, "recalcul": []}

    async def selectionner(table, _parametres):
        assert table == "grands_prix"
        return [{"id": GP_ID, "nom": "GP du Mexique", "statut": "termine",
                 "statut_resultats": "definitif"}]

    async def engages_du_gp(_gp):
        return _engages_mexique()

    async def upserter(table, lignes, cle):
        assert (table, cle) == ("correspondances_manuelles", "gp_id,cle")
        traces["choix"].extend(lignes)

    async def rattacher(_gp_id):
        traces["rattache"] += 1
        return {"rattachees": 120, "non_reconnues": []}

    async def recalculer(gp_id, relire=False):
        traces["recalcul"].append((gp_id, relire))
        return {"gp": "GP du Mexique", "gp_id": gp_id, "modifies": 1}

    monkeypatch.setattr(admin, "selectionner", selectionner)
    monkeypatch.setattr(admin, "engages_du_gp", engages_du_gp)
    monkeypatch.setattr(admin, "upserter", upserter)
    monkeypatch.setattr(admin, "rattacher", rattacher)
    monkeypatch.setattr(admin.job, "recalculer", recalculer)
    yield TestClient(app), traces
    app.dependency_overrides.clear()


def test_les_engages_du_gp_sont_servis(client):
    http, _ = client
    reponse = http.get(f"/admin/grands-prix/{GP_ID}/engages").json()
    haas = [p for p in reponse["pilotes"] if p["equipe"] == "Haas F1 Team"]
    assert [(p["numero"], p["nom"]) for p in haas] == [(50, "Ryo Hirakawa"), (87, "Oliver Bearman")]
    assert {"ecurie_id": "haas-f1-team", "nom": "Haas F1 Team"} in reponse["ecuries"]


def test_resoudre_enregistre_le_choix_et_recalcule(client):
    http, traces = client
    reponse = http.post(
        "/admin/alertes/resoudre",
        json={"gp_id": GP_ID, "libelle": "Hirakawa, Ryo", "numero_pilote": 50},
    )
    assert reponse.status_code == 200, reponse.text
    assert reponse.json()["statut"] == "recalcule"
    assert [(c["cle"], c["numero_pilote"]) for c in traces["choix"]] == [("hirakawaryo", 50)]
    assert traces["rattache"] == 1
    # Recalcul définitif sur les données conservées : seul le rattachement a changé.
    assert traces["recalcul"] == [(GP_ID, False)]


@pytest.mark.parametrize(
    "corps",
    [
        {"libelle": "E.Ocon", "numero_pilote": 31},  # pas engagé à ce GP
        {"libelle": "Hirakawa, Ryo"},  # ni pilote ni écurie
        {"libelle": "Hirakawa, Ryo", "numero_pilote": 50, "ecurie_id": "haas-f1-team"},
        {"libelle": "Écurie", "ecurie_id": "brawn-gp"},
    ],
)
def test_resoudre_refuse_ce_qui_n_est_pas_engage(client, corps):
    http, traces = client
    reponse = http.post("/admin/alertes/resoudre", json={"gp_id": GP_ID, **corps})
    assert reponse.status_code == 422
    assert traces["choix"] == [] and traces["recalcul"] == []
