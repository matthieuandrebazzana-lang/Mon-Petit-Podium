"""Notifications push : fenêtres de déclenchement, doublons, jetons invalides (§25)."""

import asyncio
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app import apns
from app.api.deps import utilisateur_courant
from app.api.routes import push
from app.jobs import notifications as job
from app.main import app

QUALIFS = datetime(2026, 10, 10, 13, 0, tzinfo=UTC)
COURSE = datetime(2026, 10, 11, 12, 0, tzinfo=UTC)

GP = {
    "id": "gp-1",
    "nom": "GP Singapour",
    "statut": "cotes_figees",
    "date_qualifications": QUALIFS.isoformat(),
    "date_course": COURSE.isoformat(),
}


def dus(maintenant, deja=frozenset(), **champs):
    return job.evenements_dus({**GP, **champs}, maintenant, set(deja))


# --------------------------------------------------------------------------- #
#  Fenêtres de déclenchement
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    ("evenement", "echeance"),
    [
        (job.OUVERTURE_24H, QUALIFS - timedelta(hours=25)),
        (job.OUVERTURE, QUALIFS - timedelta(hours=1)),
        (job.DERNIERE_CHANCE, COURSE - timedelta(hours=1)),
    ],
)
def test_fenetre_de_quinze_minutes_apres_l_echeance(evenement, echeance):
    assert dus(echeance - timedelta(seconds=1)) == []
    assert dus(echeance) == [evenement]
    assert dus(echeance + timedelta(minutes=14, seconds=59)) == [evenement]
    assert dus(echeance + job.FENETRE) == []


def test_un_redemarrage_de_dix_minutes_rattrape_l_evenement():
    # Tour manqué à l'échéance (Railway en redéploiement), repris 10 min après.
    assert dus(COURSE - timedelta(minutes=50)) == [job.DERNIERE_CHANCE]


def test_un_evenement_deja_envoye_ne_repart_pas():
    instant = QUALIFS - timedelta(hours=1)
    assert dus(instant, deja={job.OUVERTURE}) == []


def test_sans_date_rien_ne_part():
    assert dus(QUALIFS - timedelta(hours=1), date_qualifications=None) == []


def test_resultats_au_passage_a_termine_une_seule_fois():
    apres = COURSE + timedelta(hours=3)
    assert dus(apres) == []
    assert dus(apres, statut="termine") == [job.RESULTATS]
    assert dus(apres, statut="termine", deja={job.RESULTATS}) == []


def test_un_gp_termine_n_envoie_plus_la_derniere_chance():
    assert dus(COURSE - timedelta(hours=1), statut="termine") == [job.RESULTATS]


# --------------------------------------------------------------------------- #
#  Textes
# --------------------------------------------------------------------------- #


def test_texte_dans_la_langue_du_jeton():
    assert job.texte(job.OUVERTURE_24H, "GP Singapour", "fr") == (
        "Les pronos pour GP Singapour ouvrent dans 24h"
    )
    assert job.texte(job.RESULTATS, "GP Singapour", "fr") == (
        "Les résultats du GP Singapour sont disponibles"
    )
    assert job.texte(job.DERNIERE_CHANCE, "GP Brésil", "en") == (
        "Last chance to make your predictions for the Brazilian GP"
    )
    # Un GP inconnu de la table garde un nom lisible.
    assert job.nom_du_gp("GP Chine", "en") == "Chine GP"
    # Langue inconnue : le français.
    assert job.texte(job.OUVERTURE, "GP Qatar", "de") == "Les pronos pour GP Qatar sont ouverts"


# --------------------------------------------------------------------------- #
#  Tour complet : réservation et doublons
# --------------------------------------------------------------------------- #


class Base:
    """`notifications_envoyees` et `push_tokens` en mémoire."""

    def __init__(self, gps, jetons):
        self.gps = gps
        self.jetons = list(jetons)
        self.envoyees: set[tuple[str, str]] = set()

    async def selectionner(self, table, parametres):
        if table == "grands_prix":
            return self.gps
        if table == "notifications_envoyees":
            return [{"gp_id": g, "evenement": e} for g, e in self.envoyees]
        if table == "push_tokens":
            return self.jetons
        raise AssertionError(table)

    async def inserer_sans_doublon(self, table, ligne):
        assert table == "notifications_envoyees"
        cle = (ligne["gp_id"], ligne["evenement"])
        if cle in self.envoyees:
            return False
        self.envoyees.add(cle)
        return True

    async def supprimer(self, table, parametres):
        assert table == "push_tokens"
        retires = parametres["token"].removeprefix("in.(").removesuffix(")").split(",")
        self.jetons = [j for j in self.jetons if j["token"] not in retires]
        return []


@pytest.fixture
def base(monkeypatch):
    simulee = Base(
        [dict(GP)],
        [{"token": "aa" * 32, "langue": "fr"}, {"token": "bb" * 32, "langue": "en"}],
    )
    for nom in ("selectionner", "inserer_sans_doublon", "supprimer"):
        monkeypatch.setattr(job, nom, getattr(simulee, nom))
    simulee.envois = []

    async def envoyer(token, corps, titre=None):
        simulee.envois.append((token, corps))
        if token in getattr(simulee, "morts", set()):
            return apns.Issue(token, envoyee=False, invalide=True, raison="410 Unregistered")
        return apns.Issue(token, envoyee=True)

    monkeypatch.setattr(job.apns, "envoyer", envoyer)
    return simulee


def test_trois_tours_dans_la_fenetre_un_seul_envoi(base):
    echeance = COURSE - timedelta(hours=1)
    for minutes in (0, 5, 10):
        asyncio.run(job.surveiller(echeance + timedelta(minutes=minutes)))

    assert base.envoyees == {("gp-1", job.DERNIERE_CHANCE)}
    assert sorted(base.envois) == [
        ("aa" * 32, "Dernière chance de faire tes pronos pour GP Singapour"),
        ("bb" * 32, "Last chance to make your predictions for the Singapore GP"),
    ]


def test_ligne_deja_reservee_par_un_autre_processus(base, monkeypatch):
    # La lecture préalable ne voit rien, mais la réservation échoue : on n'envoie pas.
    async def rien(_ids):
        return {}

    monkeypatch.setattr(job, "_deja_envoyes", rien)
    base.envoyees.add(("gp-1", job.DERNIERE_CHANCE))
    asyncio.run(job.surveiller(COURSE - timedelta(hours=1)))
    assert base.envois == []


def test_hors_fenetre_rien_n_est_reserve(base):
    asyncio.run(job.surveiller(COURSE - timedelta(hours=3)))
    assert base.envoyees == set()
    assert base.envois == []


def test_les_jetons_invalides_sont_supprimes(base):
    base.morts = {"bb" * 32}
    asyncio.run(job.surveiller(COURSE - timedelta(hours=1)))
    assert [j["token"] for j in base.jetons] == ["aa" * 32]


def test_une_panne_ne_casse_pas_la_boucle(base, monkeypatch):
    async def panne(*_args):
        raise RuntimeError("Supabase injoignable")

    monkeypatch.setattr(job, "selectionner", panne)
    asyncio.run(job.surveiller(COURSE - timedelta(hours=1)))


# --------------------------------------------------------------------------- #
#  APNs : ce qui condamne un jeton
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    ("statut", "raison", "invalide"),
    [
        (410, "Unregistered", True),
        (400, "BadDeviceToken", True),
        (400, "DeviceTokenNotForTopic", True),
        (400, "PayloadTooLarge", False),
        (403, "ExpiredProviderToken", False),
        (429, "TooManyRequests", False),
        (500, "InternalServerError", False),
    ],
)
def test_jeton_invalide(statut, raison, invalide):
    assert apns.jeton_invalide(statut, raison) is invalide


# --------------------------------------------------------------------------- #
#  Routes
# --------------------------------------------------------------------------- #


@pytest.fixture
def client(monkeypatch):
    app.dependency_overrides[utilisateur_courant] = lambda: "moi"
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_enregistrer_un_jeton(client, monkeypatch):
    appels = []

    async def upserter(table, lignes, sur_conflit):
        appels.append((table, lignes, sur_conflit))
        return lignes

    monkeypatch.setattr(push, "upserter", upserter)
    reponse = client.post("/push/token", json={"token": "AB" * 32, "langue": "en"})

    assert reponse.status_code == 204
    table, (ligne,), cle = appels[0]
    assert (table, cle) == ("push_tokens", "token")
    # L'identité vient du jeton vérifié, jamais du corps.
    assert ligne["user_id"] == "moi"
    assert (ligne["token"], ligne["langue"]) == ("ab" * 32, "en")


@pytest.mark.parametrize(
    "corps",
    [{"token": "pas-hexa", "langue": "fr"}, {"token": "ab" * 32, "langue": "de"}],
)
def test_jeton_ou_langue_refuses(client, corps):
    assert client.post("/push/token", json=corps).status_code == 422


def test_retirer_ne_touche_que_ses_jetons(client, monkeypatch):
    filtres = []

    async def supprimer(table, parametres):
        filtres.append(parametres)
        return []

    monkeypatch.setattr(push, "supprimer", supprimer)
    assert client.request("DELETE", "/push/token", json={"token": "ab" * 32}).status_code == 204
    assert client.delete("/push/token").status_code == 204
    assert filtres == [
        {"user_id": "eq.moi", "token": f"eq.{'ab' * 32}"},
        {"user_id": "eq.moi"},
    ]


def test_le_test_exige_le_secret(client):
    assert client.post("/push/test").status_code in (401, 503)
