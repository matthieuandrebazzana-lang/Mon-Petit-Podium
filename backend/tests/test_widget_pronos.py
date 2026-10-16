"""Widget iOS « Mes pronos » — `GET /widget/pronos`, jeton widget seul (`decisions.md` §30)."""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import jwt
import pytest
from fastapi.testclient import TestClient

from app.api import deps, jeton_widget
from app.api.routes import widget
from app.config import Settings
from app.main import app

SECRET = "secret-de-test-du-widget-assez-long-pour-hs256"
MOI = str(uuid4())
PROCHAIN = str(uuid4())
DERNIER = str(uuid4())
URL = "/widget/pronos"

GP_PROCHAIN = {
    "id": PROCHAIN,
    "nom": "GP Etats Unis",
    "date_course": "2026-10-25T19:00:00+00:00",
    "date_qualifications": "2026-10-24T21:00:00+00:00",
    "statut": "cotes_figees",
    "statut_resultats": None,
}
GP_DERNIER = {
    "id": DERNIER,
    "nom": "GP Singapour",
    "date_course": "2026-10-11T12:00:00+00:00",
    "date_qualifications": "2026-10-10T13:00:00+00:00",
    "statut": "termine",
    "statut_resultats": "definitif",
}

# La forme exacte de `pronostics_du_joueur` (migration 27).
GRILLE_OUVERTE = [
    {"id": str(uuid4()), "type": "vainqueur", "outcome": "o1", "pilote": "Lando Norris",
     "marche": "vainqueur", "libelle": "Vainqueur", "points": 28, "points_gagnes": None,
     "statut_evaluation": "en_attente", "podium": None},
    {"id": str(uuid4()), "type": "podium", "outcome": "o2", "pilote": "Oscar Piastri",
     "marche": "podium", "libelle": "Podium", "points": 14, "points_gagnes": None,
     "statut_evaluation": "en_attente",
     "podium": {"pilote_1": "o2", "pilote_2": "o3", "nom_1": "Oscar Piastri",
                "nom_2": "George Russell", "points_2": 19,
                "points_gagnes_1": None, "points_gagnes_2": None}},
    {"id": str(uuid4()), "type": "bonus", "outcome": "o4", "pilote": "Hamilton",
     "marche": "top-6", "libelle": "Top 6", "points": 17, "points_gagnes": None,
     "statut_evaluation": "en_attente", "podium": None},
]
GRILLE_JUGEE = [
    {"id": str(uuid4()), "type": "vainqueur", "outcome": "o1", "pilote": "Max Verstappen",
     "marche": "vainqueur", "libelle": "Vainqueur", "points": 35, "points_gagnes": 35,
     "statut_evaluation": "gagne", "podium": None},
    {"id": str(uuid4()), "type": "podium", "outcome": "o2", "pilote": "Lando Norris",
     "marche": "podium", "libelle": "Podium", "points": 12, "points_gagnes": 12,
     "statut_evaluation": "gagne",
     "podium": {"pilote_1": "o2", "pilote_2": "o3", "nom_1": "Lando Norris",
                "nom_2": "Charles Leclerc", "points_2": 21,
                "points_gagnes_1": 12, "points_gagnes_2": 0}},
    {"id": str(uuid4()), "type": "bonus", "outcome": "o5", "pilote": "Oui",
     "marche": "voiture-de-securite", "libelle": "Voiture de sécurité", "points": 16,
     "points_gagnes": None, "statut_evaluation": "non_evaluable", "podium": None},
]


def reglages(secret: str = SECRET) -> Settings:
    return Settings(
        supabase_url="https://exemple.supabase.co",
        supabase_anon_key="anon",
        supabase_service_role_key="service",
        widget_token_secret=secret,
    )


def monter(monkeypatch, grilles: dict[str, list], gps=(GP_PROCHAIN, GP_DERNIER)):
    """Base simulée : `gps` en base, `grilles` les pronostics de `MOI` par GP.

    Supabase « accepte » n'importe quel jeton de session et le rattache à `MOI` :
    seul notre propre garde empêche une session d'ouvrir la route du widget.
    """
    parametres = reglages()
    monkeypatch.setattr(deps, "get_settings", lambda: parametres)
    monkeypatch.setattr(jeton_widget, "get_settings", lambda: parametres)

    async def identifiant_du_jeton(_jeton):
        return MOI

    async def selectionner(table, filtres):
        assert table == "grands_prix"
        if filtres["statut"] == "eq.termine":
            return [gp for gp in gps if gp["statut"] == "termine"][:1]
        return [gp for gp in gps if gp["statut"] != "termine"][:1]

    async def appeler_fonction(nom, parametres_sql):
        assert nom == "pronostics_du_joueur"
        # L'identité vient du jeton, jamais d'un paramètre.
        assert parametres_sql["p_profil"] == MOI
        return grilles.get(parametres_sql["p_gp"], [])

    monkeypatch.setattr(deps, "identifiant_du_jeton", identifiant_du_jeton)
    monkeypatch.setattr(widget, "selectionner", selectionner)
    monkeypatch.setattr(widget, "appeler_fonction", appeler_fonction)
    app.dependency_overrides.clear()
    return TestClient(app)


@pytest.fixture
def client(monkeypatch):
    return monter(monkeypatch, {PROCHAIN: GRILLE_OUVERTE, DERNIER: GRILLE_JUGEE})


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


def test_jeton_valide_pronos_enregistres(client):
    reponse = client.get(URL, headers=bearer(jeton()))
    assert reponse.status_code == 200
    prochain = reponse.json()["prochain"]
    assert prochain["id"] == PROCHAIN
    assert prochain["nom"] == "GP Etats Unis"
    assert prochain["statut"] == "cotes_figees"
    assert prochain["date_course"].startswith("2026-10-25T19:00:00")
    assert prochain["date_qualifications"].startswith("2026-10-24T21:00:00")
    assert prochain["etat_pronos"] == "enregistres"
    # Pas encore couru : aucun total, jamais 0.
    assert prochain["points_gagnes"] is None
    # Le podium en deux lignes, chacune avec SES points en jeu.
    assert [(p["type"], p["categorie"], p["choix"], p["points"]) for p in prochain["pronostics"]] == [
        ("vainqueur", "obligatoire", "Lando Norris", 28),
        ("podium", "obligatoire", "Oscar Piastri", 14),
        ("podium", "obligatoire", "George Russell", 19),
        ("bonus", "bonus", "Hamilton", 17),
    ]
    assert all(p["points_gagnes"] is None for p in prochain["pronostics"])
    assert all(p["statut"] == "en_attente" for p in prochain["pronostics"])
    assert prochain["pronostics"][3]["libelle"] == "Top 6"


def test_aucun_prono(monkeypatch):
    client = monter(monkeypatch, {})
    corps = client.get(URL, headers=bearer(jeton())).json()
    assert corps["prochain"]["etat_pronos"] == "aucun"
    assert corps["prochain"]["pronostics"] == []
    assert corps["prochain"]["points_gagnes"] is None
    assert corps["dernier"]["etat_pronos"] == "aucun"
    # Rien joué : pas de total, pas même 0.
    assert corps["dernier"]["points_gagnes"] is None


def test_gp_termine_avec_resultats(client):
    dernier = client.get(URL, headers=bearer(jeton())).json()["dernier"]
    assert dernier["id"] == DERNIER
    assert dernier["statut"] == "termine"
    assert dernier["statut_resultats"] == "definitif"
    # 35 (vainqueur) + 12 (podium : Norris oui, Leclerc non) ; le bonus non évaluable
    # ne compte pas, et ne compte pas pour 0.
    assert dernier["points_gagnes"] == 47
    assert [(p["choix"], p["points_gagnes"], p["statut"]) for p in dernier["pronostics"]] == [
        ("Max Verstappen", 35, "gagne"),
        ("Lando Norris", 12, "gagne"),
        ("Charles Leclerc", 0, "perdu"),
        ("Oui", None, "non_evaluable"),
    ]


def test_aucun_grand_prix(monkeypatch):
    client = monter(monkeypatch, {}, gps=())
    assert client.get(URL, headers=bearer(jeton())).json() == {"prochain": None, "dernier": None}


def test_jeton_expire(client):
    passe = datetime.now(UTC) - timedelta(days=31)
    perime = jeton(iat=int(passe.timestamp()), exp=int((passe + timedelta(days=30)).timestamp()))
    reponse = client.get(URL, headers=bearer(perime))
    assert reponse.status_code == 401
    assert "expiré" in reponse.json()["detail"]


@pytest.mark.parametrize(
    "falsifie",
    [
        jwt.encode({"sub": MOI, "aud": jeton_widget.AUDIENCE, "scope": jeton_widget.PORTEE,
                    "exp": 4102444800}, "pas-le-bon-secret-mais-tout-aussi-long-que-lui",
                   algorithm="HS256"),
        jwt.encode({"sub": MOI, "aud": jeton_widget.AUDIENCE, "scope": jeton_widget.PORTEE,
                    "exp": 4102444800}, None, algorithm="none"),
        "LIVRE",
        "PORTEE",
        "n'importe quoi",
    ],
)
def test_jeton_falsifie(client, falsifie):
    if falsifie == "LIVRE":
        tete, _, signature = jeton().split(".")
        _, charge, _ = jeton(profil=str(uuid4())).split(".")
        falsifie = f"{tete}.{charge}.{signature}"
    elif falsifie == "PORTEE":
        falsifie = jeton(scope="profil:ecriture")
    assert client.get(URL, headers=bearer(falsifie)).status_code == 401


def test_sans_jeton(client):
    assert client.get(URL).status_code == 401


def test_jeton_session_refuse(client):
    """Une session Supabase, que Supabase accepterait, n'ouvre pas la route du widget."""
    assert client.get(URL, headers=bearer("session-supabase")).status_code == 401


def test_lecture_seule(client):
    for methode in ("post", "put", "patch", "delete"):
        assert getattr(client, methode)(URL, headers=bearer(jeton())).status_code == 405


def test_sans_secret_configure(client, monkeypatch):
    parametres = reglages(secret="")
    monkeypatch.setattr(deps, "get_settings", lambda: parametres)
    monkeypatch.setattr(jeton_widget, "get_settings", lambda: parametres)
    reponse = client.get(URL, headers=bearer(jeton()))
    assert reponse.status_code == 503
    assert "WIDGET_TOKEN_SECRET" in reponse.json()["detail"]
