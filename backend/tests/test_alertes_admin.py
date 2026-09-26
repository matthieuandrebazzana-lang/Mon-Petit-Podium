"""`GET /admin/alertes` : ce que le profil admin voit (migration 26)."""

import pytest
from fastapi.testclient import TestClient

from app.api.deps import exiger_admin
from app.api.routes import admin
from app.main import app
from app.supabase_client import ErreurSupabase

LIGNES = [
    {"type": "libelle_non_reconnu", "gp_id": "gp-1", "marche": "vainqueur",
     "libelle": "Z.Inventé", "tentatives": 1, "derniere_erreur": None,
     "modifie_le": "2026-09-19T14:05:00+00:00", "grands_prix": {"nom": "GP Azerbaïdjan"}},
    {"type": "definitif_en_echec", "gp_id": "gp-2", "marche": None, "libelle": None,
     "tentatives": 2, "derniere_erreur": "statut 502", "modifie_le": None,
     "grands_prix": {"nom": "GP Singapour"}},
    {"type": "definitif_en_echec", "gp_id": "gp-3", "marche": None, "libelle": None,
     "tentatives": 4, "derniere_erreur": "statut 502", "modifie_le": None,
     "grands_prix": [{"nom": "GP Austin"}]},
]


@pytest.fixture
def client():
    app.dependency_overrides[exiger_admin] = lambda: "admin"
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_alertes_servies_avec_le_gp_et_au_seuil(client, monkeypatch):
    async def selectionner(table, _parametres):
        assert table == "alertes_admin"
        return LIGNES

    monkeypatch.setattr(admin, "selectionner", selectionner)
    reponse = client.get("/admin/alertes").json()

    assert reponse["disponible"] is True
    # Deux échecs du définitif : sous le seuil, pas encore une alerte.
    assert [(a["type"], a["gp"], a["libelle"], a["tentatives"]) for a in reponse["alertes"]] == [
        ("libelle_non_reconnu", "GP Azerbaïdjan", "Z.Inventé", 1),
        ("definitif_en_echec", "GP Austin", None, 4),
    ]


def test_table_absente(client, monkeypatch):
    async def selectionner(_table, _parametres):
        raise ErreurSupabase("relation absente", code="42P01", statut=404)

    monkeypatch.setattr(admin, "selectionner", selectionner)
    assert client.get("/admin/alertes").json() == {"disponible": False, "alertes": []}
