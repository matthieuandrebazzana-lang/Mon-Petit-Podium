"""`GET /calendrier` : les GP de la saison, sans leurs cotes, en une requête."""

import pytest
from fastapi.testclient import TestClient

from app.api.deps import exiger_configuration
from app.api.routes import calendrier
from app.main import app

LIGNES = [
    {"id": "3bf1ef36-0000-4000-8000-000000000001", "nom": "GP Azerbaïdjan",
     "date_course": "2026-09-26T11:00:00+00:00", "date_qualifications": "2026-09-25T12:00:00+00:00",
     "statut": "termine", "cotes": [{"count": 48}]},
    {"id": "3118efe3-0000-4000-8000-000000000002", "nom": "GP Malaisie",
     "date_course": "2026-10-04T07:00:00+00:00", "date_qualifications": None,
     "statut": "a_venir", "cotes": [{"count": 0}]},
    # Forme objet, que rendent certaines versions de PostgREST.
    {"id": "676382b2-0000-4000-8000-000000000003", "nom": "GP Singapour",
     "date_course": None, "statut": "a_venir", "cotes": {"count": 3}},
]


@pytest.fixture
def client():
    app.dependency_overrides[exiger_configuration] = lambda: None
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture
def appels(monkeypatch):
    lus = []

    async def selectionner(table, parametres):
        lus.append((table, parametres))
        return LIGNES

    monkeypatch.setattr(calendrier, "selectionner", selectionner)
    return lus


def test_une_seule_requete_sans_cotes_detaillees(client, appels):
    reponse = client.get("/calendrier?saison=2026")

    assert reponse.status_code == 200
    assert len(appels) == 1
    table, parametres = appels[0]
    assert table == "grands_prix"
    assert parametres["select"] == "id,nom,date_course,date_qualifications,statut,cotes(count)"


def test_champs_servis_et_a_des_cotes(client, appels):
    gps = client.get("/calendrier?saison=2026").json()

    assert [set(gp) for gp in gps] == [
        {"id", "nom", "date_course", "date_qualifications", "statut", "a_des_cotes"}
    ] * 3
    assert [(gp["nom"], gp["a_des_cotes"]) for gp in gps] == [
        ("GP Azerbaïdjan", True),
        ("GP Malaisie", False),
        ("GP Singapour", True),
    ]
    assert gps[2]["date_course"] is None
    assert gps[2]["date_qualifications"] is None


def test_filtre_sur_la_saison_demandee_sans_perdre_les_gp_sans_horaire(client, appels):
    client.get("/calendrier?saison=2027")

    filtre = appels[0][1]["or"]
    assert "date_course.is.null" in filtre
    assert "date_course.gte.2027-01-01T00:00:00Z" in filtre
    assert "date_course.lt.2028-01-01T00:00:00Z" in filtre


def test_saison_en_cours_par_defaut(client, appels, monkeypatch):
    class Horloge:
        @staticmethod
        def now(_tz):
            from datetime import UTC, datetime
            return datetime(2026, 10, 7, tzinfo=UTC)

    monkeypatch.setattr(calendrier, "datetime", Horloge)
    client.get("/calendrier")

    assert "date_course.gte.2026-01-01T00:00:00Z" in appels[0][1]["or"]


def test_embarquement_absent_vaut_sans_cotes():
    assert calendrier._compte(None) == 0
    assert calendrier._compte([]) == 0
    assert calendrier._compte([{"count": 2}]) == 2


def test_publique_sans_jeton(client, appels):
    assert client.get("/calendrier", headers={}).status_code == 200


def test_ping():
    reponse = TestClient(app).get("/ping")
    assert reponse.status_code == 200
    assert reponse.text == "pong"
    assert TestClient(app).head("/ping").status_code == 200
