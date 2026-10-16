"""Jeton du widget iOS et classement en lecture seule (`decisions.md` §28)."""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import jwt
import pytest
from fastapi.testclient import TestClient

from app.api import deps, jeton_widget
from app.api.routes import pronostics, widget
from app.config import Settings
from app.main import app

SECRET = "secret-de-test-du-widget-assez-long-pour-hs256"
MOI = str(uuid4())
AUTRE = str(uuid4())
CHAMPIONNAT = str(uuid4())

LIGNE_SQL = {
    "profil_id": MOI,
    "pseudo": "Matt",
    "total_points": 128,
    "pronostics_reussis": 7,
    "meilleure_cote": 41,
    "rang": 1,
    "ordre_inscription": 1,
    "couleur1": "#003087",
    "couleur2": "#FFFFFF",
    "couleur_texte": None,
    "numero": 44,
    "livree_mode": "ecurie",
    "livree_ecurie": "ferrari",
    "avatar_url": "https://exemple.test/a.jpg",
}


def reglages(secret: str = SECRET) -> Settings:
    return Settings(
        supabase_url="https://exemple.supabase.co",
        supabase_anon_key="anon",
        supabase_service_role_key="service",
        widget_token_secret=secret,
    )


@pytest.fixture
def client(monkeypatch):
    """Base simulée : `MOI` est membre de `CHAMPIONNAT`, `AUTRE` ne l'est pas.

    Supabase « accepte » n'importe quel jeton de session et le rattache à `MOI` :
    c'est le pire cas pour le cloisonnement, celui où seul notre propre refus
    empêche le jeton widget d'ouvrir une autre route.
    """
    parametres = reglages()
    monkeypatch.setattr(deps, "get_settings", lambda: parametres)
    monkeypatch.setattr(jeton_widget, "get_settings", lambda: parametres)

    async def identifiant_du_jeton(_jeton):
        return MOI

    async def selectionner(table, filtres):
        assert table == "membres_championnat"
        membre = filtres["profil_id"] == f"eq.{MOI}"
        return [{"profil_id": MOI}] if membre else []

    async def appeler_fonction(nom, parametres_sql):
        assert nom == "classement_du_championnat"
        assert parametres_sql == {"p_championnat": CHAMPIONNAT}
        return [LIGNE_SQL]

    monkeypatch.setattr(deps, "identifiant_du_jeton", identifiant_du_jeton)
    monkeypatch.setattr(pronostics, "selectionner", selectionner)
    monkeypatch.setattr(widget, "appeler_fonction", appeler_fonction)
    app.dependency_overrides.clear()
    return TestClient(app)


def jeton(profil: str = MOI, **surcharge) -> str:
    maintenant = datetime.now(UTC)
    charge = {
        "sub": profil,
        "aud": jeton_widget.AUDIENCE,
        "scope": jeton_widget.PORTEE,
        "iat": int(maintenant.timestamp()),
        "exp": int((maintenant + timedelta(days=30)).timestamp()),
        **surcharge,
    }
    return jwt.encode(charge, SECRET, algorithm="HS256")


def bearer(valeur: str) -> dict:
    return {"Authorization": f"Bearer {valeur}"}


URL = f"/widget/championnats/{CHAMPIONNAT}/classement"


def test_emission_puis_lecture(client):
    reponse = client.post("/widget/token", headers=bearer("session-supabase"))
    assert reponse.status_code == 200
    corps = reponse.json()
    assert corps["profil_id"] == MOI

    expire = datetime.fromisoformat(corps["expire_le"])
    assert timedelta(days=29, hours=23) < expire - datetime.now(UTC) <= timedelta(days=30)

    charge = jwt.decode(corps["jeton"], SECRET, algorithms=["HS256"],
                        audience=jeton_widget.AUDIENCE)
    assert charge["sub"] == MOI
    assert charge["scope"] == "widget:lecture"

    lignes = client.get(URL, headers=bearer(corps["jeton"]))
    assert lignes.status_code == 200
    assert lignes.json() == [{
        "profil_id": MOI,
        "pseudo": "Matt",
        "rang": 1,
        "total_points": 128,
        "avatar_url": "https://exemple.test/a.jpg",
        "couleur1": "#003087",
        "couleur2": "#FFFFFF",
        "couleur_texte": None,
        "numero": 44,
        "livree_mode": "ecurie",
        "livree_ecurie": "ferrari",
    }]


def test_emission_exige_une_session(client):
    assert client.post("/widget/token").status_code == 401


def test_jeton_expire(client):
    passe = datetime.now(UTC) - timedelta(days=31)
    perime = jeton(iat=int(passe.timestamp()),
                   exp=int((passe + timedelta(days=30)).timestamp()))
    reponse = client.get(URL, headers=bearer(perime))
    assert reponse.status_code == 401
    assert "expiré" in reponse.json()["detail"]


@pytest.mark.parametrize(
    "falsifie",
    [
        # Signé avec un autre secret.
        jwt.encode({"sub": MOI, "aud": jeton_widget.AUDIENCE, "scope": jeton_widget.PORTEE,
                    "exp": 4102444800}, "pas-le-bon-secret-mais-tout-aussi-long-que-lui",
                   algorithm="HS256"),
        # Non signé.
        jwt.encode({"sub": MOI, "aud": jeton_widget.AUDIENCE, "scope": jeton_widget.PORTEE,
                    "exp": 4102444800}, None, algorithm="none"),
        # Charge modifiée après signature : un autre `sub` sous la signature de MOI.
        "LIVRE",
        # Bonne signature, mauvaise portée.
        "PORTEE",
        "n'importe quoi",
    ],
)
def test_jeton_falsifie(client, falsifie):
    if falsifie == "LIVRE":
        tete, _, signature = jeton().split(".")
        _, charge, _ = jeton(profil=AUTRE).split(".")
        falsifie = f"{tete}.{charge}.{signature}"
    elif falsifie == "PORTEE":
        falsifie = jeton(scope="profil:ecriture")
    assert client.get(URL, headers=bearer(falsifie)).status_code == 401


def test_sans_jeton(client):
    assert client.get(URL).status_code == 401


def test_utilisateur_non_membre(client):
    reponse = client.get(URL, headers=bearer(jeton(profil=AUTRE)))
    assert reponse.status_code == 403


def test_jeton_session_refuse_par_le_widget(client):
    """Une session Supabase n'ouvre pas la route du widget : elle n'est pas signée par lui."""
    assert client.get(URL, headers=bearer("session-supabase")).status_code == 401


@pytest.mark.parametrize(
    ("methode", "chemin"),
    [
        ("get", f"/championnats/{CHAMPIONNAT}/classement"),
        ("get", "/championnats/moi"),
        ("post", "/widget/token"),
        ("delete", "/push/token"),
        ("get", f"/grands-prix/{uuid4()}/favoris"),
        ("post", f"/grands-prix/{uuid4()}/pronostics"),
    ],
)
def test_jeton_widget_refuse_ailleurs(client, methode, chemin):
    reponse = getattr(client, methode)(chemin, headers=bearer(jeton()))
    assert reponse.status_code == 401
    assert reponse.json()["detail"] == "Ce jeton est réservé au widget."


def test_sans_secret_configure(client, monkeypatch):
    parametres = reglages(secret="")
    monkeypatch.setattr(deps, "get_settings", lambda: parametres)
    monkeypatch.setattr(jeton_widget, "get_settings", lambda: parametres)

    for reponse in (
        client.post("/widget/token", headers=bearer("session-supabase")),
        client.get(URL, headers=bearer(jeton())),
    ):
        assert reponse.status_code == 503
        assert "WIDGET_TOKEN_SECRET" in reponse.json()["detail"]
