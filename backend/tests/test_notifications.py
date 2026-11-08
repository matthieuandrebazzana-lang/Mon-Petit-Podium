"""Notifications push : fenêtres de déclenchement, doublons, jetons invalides (§25)."""

import asyncio
import time
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
    ("evenement", "echeance", "statut"),
    [
        # « Dans 24h » vise l'ouverture prévue, qualifs + 2 h.
        (job.OUVERTURE_24H, QUALIFS - timedelta(hours=22), "a_venir"),
        (job.DERNIERE_CHANCE, COURSE - timedelta(hours=1), "cotes_figees"),
    ],
)
def test_fenetre_de_quinze_minutes_apres_l_echeance(evenement, echeance, statut):
    # L'ouverture, déjà envoyée, ne brouille pas la fenêtre mesurée.
    deja = {job.OUVERTURE}
    assert dus(echeance - timedelta(seconds=1), deja, statut=statut) == []
    assert dus(echeance, deja, statut=statut) == [evenement]
    assert dus(echeance + timedelta(minutes=14, seconds=59), deja, statut=statut) == [evenement]
    assert dus(echeance + job.FENETRE, deja, statut=statut) == []


def test_un_redemarrage_de_dix_minutes_rattrape_l_evenement():
    # Tour manqué à l'échéance (Railway en redéploiement), repris 10 min après.
    assert dus(COURSE - timedelta(minutes=50), {job.OUVERTURE}) == [job.DERNIERE_CHANCE]


def test_un_evenement_deja_envoye_ne_repart_pas():
    instant = COURSE - timedelta(hours=1)
    assert dus(instant, deja={job.OUVERTURE, job.DERNIERE_CHANCE}) == []


def test_sans_date_rien_ne_part():
    assert dus(QUALIFS - timedelta(hours=22), statut="a_venir", date_qualifications=None) == []


# --------------------------------------------------------------------------- #
#  L'ouverture suit les cotes, jamais l'horloge (GP du Brésil 2026)
# --------------------------------------------------------------------------- #


def test_l_ouverture_ne_part_pas_avant_les_cotes():
    """Elle partait à qualifs − 1 h, trois heures avant le scraping."""
    for instant in (
        QUALIFS - timedelta(hours=1),
        QUALIFS + timedelta(hours=2),
        COURSE - timedelta(minutes=30),
    ):
        assert job.OUVERTURE not in dus(instant, statut="a_venir")


def test_l_ouverture_part_des_que_les_cotes_sont_figees_meme_en_retard():
    # Cotes figées à qualifs + 9 h : aucune fenêtre ne la périme.
    assert dus(QUALIFS + timedelta(hours=9)) == [job.OUVERTURE]


def test_l_ouverture_ne_part_plus_apres_le_depart():
    assert job.OUVERTURE not in dus(COURSE + timedelta(minutes=1))


def test_l_ouverture_sans_depart_connu_part_quand_meme():
    assert dus(QUALIFS + timedelta(hours=3), date_course=None) == [job.OUVERTURE]


def test_dans_24h_se_tait_si_les_cotes_sont_deja_figees():
    assert job.OUVERTURE_24H not in dus(QUALIFS - timedelta(hours=22), {job.OUVERTURE})


def test_pas_de_derniere_chance_sans_cotes():
    assert dus(COURSE - timedelta(hours=1), statut="a_venir") == []


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
        "Les pronos pour le GP de Singapour ouvrent dans 24h"
    )
    assert job.texte(job.RESULTATS, "GP Singapour", "fr") == (
        "Les résultats du GP de Singapour sont disponibles"
    )
    assert job.texte(job.DERNIERE_CHANCE, "GP Brésil", "en") == (
        "Last chance to make your predictions for the Brazilian GP"
    )
    # Langue inconnue : le français.
    assert job.texte(job.OUVERTURE, "GP Qatar", "de") == "Les pronos pour le GP du Qatar sont ouverts"


def test_le_libelle_unibet_francais_ne_fuit_pas_en_anglais():
    """Reçu sur iPhone : « …for the du Mexique GP »."""
    assert job.texte(job.DERNIERE_CHANCE, "GP du Mexique", "en") == (
        "Last chance to make your predictions for the Mexican GP"
    )
    assert job.textes(job.DERNIERE_CHANCE, "GP du Mexique") == {
        "fr": "Dernière chance de faire tes pronos pour le GP du Mexique",
        "en": "Last chance to make your predictions for the Mexican GP",
    }


# --------------------------------------------------------------------------- #
#  Tour complet : réservation et doublons
# --------------------------------------------------------------------------- #


class Base:
    """`notifications_envoyees` et `push_tokens` en mémoire."""

    def __init__(self, gps, jetons, cotes=("gp-1",)):
        self.gps = gps
        self.jetons = list(jetons)
        self.envoyees: set[tuple[str, str]] = set()
        self.cotes = set(cotes)

    async def selectionner(self, table, parametres):
        if table == "grands_prix":
            return self.gps
        if table == "cotes":
            gp_id = parametres["gp_id"].removeprefix("eq.")
            return [{"id": "c-1"}] if gp_id in self.cotes else []
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
    # L'ouverture du GP de la fixture est déjà partie : les tests qui suivent
    # mesurent la « dernière chance ». L'ouverture a les siens, plus bas.
    simulee.envoyees.add(("gp-1", job.OUVERTURE))

    async def envoyer(token, corps, titre=None, tentative=1):
        simulee.envois.append((token, corps))
        if token in getattr(simulee, "morts", set()):
            return apns.Issue(token, envoyee=False, invalide=True, raison="410 Unregistered")
        return apns.Issue(token, envoyee=True)

    monkeypatch.setattr(job.apns, "envoyer", envoyer)
    # Sans clé APNs dans les tests : le job ne vérifie rien ici, `tous` rétablit.
    monkeypatch.setattr(job.apns, "verifier_configuration", lambda: None)
    return simulee


def test_trois_tours_dans_la_fenetre_un_seul_envoi(base):
    echeance = COURSE - timedelta(hours=1)
    for minutes in (0, 5, 10):
        asyncio.run(job.surveiller(echeance + timedelta(minutes=minutes)))

    assert base.envoyees == {("gp-1", job.OUVERTURE), ("gp-1", job.DERNIERE_CHANCE)}
    assert sorted(base.envois) == [
        ("aa" * 32, "Dernière chance de faire tes pronos pour le GP de Singapour"),
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
    assert base.envoyees == {("gp-1", job.OUVERTURE)}
    assert base.envois == []


def test_l_ouverture_part_au_premier_tour_qui_voit_les_cotes(base):
    base.envoyees.clear()
    base.gps[0]["statut"] = "a_venir"
    asyncio.run(job.surveiller(QUALIFS - timedelta(hours=1)))
    assert base.envois == []  # l'ancienne échéance : plus rien ne part

    base.gps[0]["statut"] = "cotes_figees"  # le scraper a figé, en retard
    for minutes in (0, 5):
        asyncio.run(job.surveiller(QUALIFS + timedelta(hours=6, minutes=minutes)))
    assert base.envoyees == {("gp-1", job.OUVERTURE)}
    assert sorted(base.envois) == [
        ("aa" * 32, "Les pronos pour le GP de Singapour sont ouverts"),
        ("bb" * 32, "Predictions for the Singapore GP are open"),
    ]


def test_l_ouverture_attend_une_cote_en_base(base):
    """Statut posé à la main sans une cote : rien n'est réservé, rien ne part."""
    base.envoyees.clear()
    base.cotes.clear()
    asyncio.run(job.surveiller(QUALIFS + timedelta(hours=3)))
    assert base.envoyees == set()
    assert base.envois == []

    base.cotes.add("gp-1")
    asyncio.run(job.surveiller(QUALIFS + timedelta(hours=3, minutes=5)))
    assert base.envoyees == {("gp-1", job.OUVERTURE)}


def test_alerte_admin_aux_seuls_appareils_administrateurs(base, monkeypatch):
    base.jetons = [
        {"token": "aa" * 32, "langue": "fr", "user_id": "admin"},
        {"token": "bb" * 32, "langue": "en", "user_id": "joueur"},
    ]
    lu = {}

    async def selectionner(table, parametres):
        if table == "profils":
            assert parametres["is_admin"] == "eq.true"
            return [{"id": "admin"}]
        assert table == "push_tokens"
        lu.update(parametres)
        ids = parametres["user_id"].removeprefix("in.(").removesuffix(")").split(",")
        return [j for j in base.jetons if j["user_id"] in ids]

    monkeypatch.setattr(job, "selectionner", selectionner)
    bilan = asyncio.run(job.notifier_admins({"fr": "alerte", "en": "alert"}))
    assert lu["user_id"] == "in.(admin)"
    assert bilan["envoyees"] == 1
    assert base.envois == [("aa" * 32, "alerte")]


def test_alerte_admin_sans_apns_ne_leve_pas(base, monkeypatch):
    def casse():
        raise apns.ErreurAPNs("APNs non configuré")

    monkeypatch.setattr(job.apns, "verifier_configuration", casse)
    assert asyncio.run(job.notifier_admins({"fr": "alerte"})) is None
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


# --------------------------------------------------------------------------- #
#  POST /push/test/tous — secret seul, sans session
# --------------------------------------------------------------------------- #

SECRET = "s3cret"


def _cle_p8() -> str:
    """Une vraie clé P-256 : la route signe le JWT avant d'envoyer quoi que ce soit."""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    return (
        ec.generate_private_key(ec.SECP256R1())
        .private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
        .decode()
    )


CLE_P8 = _cle_p8()

# `apns.envoyer` d'origine : la fixture `base` le remplace pour tout le module.
ENVOYER_REEL = apns.envoyer
VERIFIER_REEL = apns.verifier_configuration


def _sans_duree(reponse) -> dict:
    corps = reponse.json()
    assert 0 <= corps.pop("duree") < 30
    return corps


@pytest.fixture
def tous(monkeypatch, base):
    """Client sans session : la route ne doit dépendre que de `X-Admin-Secret`."""
    from app.api import deps
    from app.config import Settings

    reglages = Settings(
        admin_secret=SECRET, apns_key_id="K", apns_team_id="T", apns_key=CLE_P8, apns_env="production"
    )
    monkeypatch.setattr(deps, "get_settings", lambda: reglages)
    monkeypatch.setattr(push, "get_settings", lambda: reglages)
    monkeypatch.setattr(apns, "get_settings", lambda: reglages)
    monkeypatch.setattr(apns, "_jeton_fournisseur", None)
    monkeypatch.setattr(apns, "_client", None)
    monkeypatch.setattr(apns, "verifier_configuration", VERIFIER_REEL)
    monkeypatch.setattr(push, "selectionner", base.selectionner)
    app.dependency_overrides.clear()
    return TestClient(app)


@pytest.mark.parametrize("entetes", [{}, {"X-Admin-Secret": "faux"}])
def test_tous_exige_le_bon_secret(tous, base, entetes):
    assert tous.post("/push/test/tous", headers=entetes).status_code == 401
    assert base.envois == []


def test_tous_envoie_a_chaque_jeton_dans_sa_langue(tous, base):
    reponse = tous.post("/push/test/tous", headers={"X-Admin-Secret": SECRET})

    assert reponse.status_code == 200
    assert _sans_duree(reponse) == {"jetons": 2, "envoyees": 2, "echecs": 0, "supprimes": 0, "erreurs": []}
    assert sorted(base.envois) == [
        ("aa" * 32, "🏎️ Test Greed F1 — les notifications fonctionnent !"),
        ("bb" * 32, "🏎️ Greed F1 test — notifications are working!"),
    ]


def test_tous_supprime_les_jetons_invalides(tous, base):
    base.morts = {"bb" * 32}
    reponse = tous.post("/push/test/tous", headers={"X-Admin-Secret": SECRET})

    assert _sans_duree(reponse) == {
        "jetons": 2,
        "envoyees": 1,
        "echecs": 1,
        "supprimes": 1,
        "erreurs": [{"jeton": "…bbbbbbbb", "motif": "410 Unregistered"}],
    }
    assert [j["token"] for j in base.jetons] == ["aa" * 32]


# --------------------------------------------------------------------------- #
#  Délais — un APNs muet ne bloque jamais la route
# --------------------------------------------------------------------------- #


class Reponse:
    status_code = 200

    def json(self):
        return {}


class ClientAPNs:
    """Un faux client HTTP/2. `muet` : APNs ne répond jamais, sinon `200`.

    `en_vol` compte les envois simultanés de TOUS les clients ouverts.
    """

    en_vol = 0
    pic = 0

    def __init__(self, muet: bool):
        self.muet = muet
        self.appels = 0
        self.ferme = False

    async def post(self, *args, **kwargs):
        self.appels += 1
        ClientAPNs.en_vol += 1
        ClientAPNs.pic = max(ClientAPNs.pic, ClientAPNs.en_vol)
        try:
            if self.muet:
                await asyncio.Event().wait()
            await asyncio.sleep(0.01)
            return Reponse()
        finally:
            ClientAPNs.en_vol -= 1

    async def aclose(self):
        self.ferme = True


@pytest.fixture
def apns_simule(monkeypatch, tous):
    """Remplace le client httpx d'`apns` par des `ClientAPNs`.

    Rend `(clients, muets)` : les clients dans l'ordre d'ouverture, et pour
    chacun s'il est muet — la dernière valeur vaut pour tous les suivants.
    """
    clients: list[ClientAPNs] = []
    clients_muets = [True]
    monkeypatch.setattr(ClientAPNs, "en_vol", 0)
    monkeypatch.setattr(ClientAPNs, "pic", 0)

    def ouvrir(**options):
        rang = min(len(clients), len(clients_muets) - 1)
        clients.append(ClientAPNs(muet=clients_muets[rang]))
        return clients[-1]

    monkeypatch.setattr(apns, "envoyer", ENVOYER_REEL)
    monkeypatch.setattr(apns.httpx, "AsyncClient", ouvrir)
    monkeypatch.setattr(apns, "DELAI_ENVOI", 0.2)
    return clients, clients_muets


def _test_tous(tous):
    return tous.post("/push/test/tous", headers={"X-Admin-Secret": SECRET})


def test_les_envois_partent_en_serie_sur_une_seule_connexion(tous, base, apns_simule):
    clients, muets = apns_simule
    muets[:] = [False]
    base.jetons = [{"token": c * 64, "langue": "fr"} for c in "abcde"]

    corps = _sans_duree(_test_tous(tous))

    assert corps == {"jetons": 5, "envoyees": 5, "echecs": 0, "supprimes": 0, "erreurs": []}
    # Jamais deux envois à la fois, tous sur la connexion du premier.
    assert ClientAPNs.pic == 1
    assert [c.appels for c in clients] == [5]


def test_un_envoi_expire_reussit_au_second_essai_sur_une_connexion_neuve(tous, base, apns_simule):
    clients, muets = apns_simule
    muets[:] = [True, False]

    corps = _sans_duree(_test_tous(tous))

    assert corps == {"jetons": 2, "envoyees": 2, "echecs": 0, "supprimes": 0, "erreurs": []}
    # Le premier client, muet, est jeté ; le neuf sert la reprise puis le jeton suivant.
    assert [c.appels for c in clients] == [1, 2]
    assert clients[0].ferme and not clients[1].ferme


def test_apns_muet_deux_essais_par_jeton_puis_echec(tous, base, apns_simule):
    clients, _ = apns_simule

    debut = time.monotonic()
    reponse = _test_tous(tous)

    assert reponse.status_code == 200
    assert time.monotonic() - debut < 3
    corps = _sans_duree(reponse)
    assert corps["envoyees"] == 0 and corps["echecs"] == 2 and corps["supprimes"] == 0
    assert {e["motif"] for e in corps["erreurs"]} == {"Délai dépassé (0.2 s)"}
    # Chaque essai expiré jette son client : quatre connexions, une par essai.
    assert [c.appels for c in clients] == [1, 1, 1, 1]
    assert all(c.ferme for c in clients) and apns._client is None


def test_apns_muet_la_route_repond_dans_le_delai_global(tous, base, apns_simule, monkeypatch):
    monkeypatch.setattr(apns, "DELAI_ENVOI", 60.0)
    monkeypatch.setattr(push, "DELAI_ROUTE_TEST", 0.3)
    base.jetons.append({"token": "cc" * 32, "langue": "fr"})

    debut = time.monotonic()
    reponse = _test_tous(tous)

    assert reponse.status_code == 200
    assert time.monotonic() - debut < 3
    corps = _sans_duree(reponse)
    assert corps["jetons"] == 3 and corps["envoyees"] == 0 and corps["echecs"] == 3
    # Le premier est coupé en vol, les deux autres n'ont jamais eu leur tour.
    assert [e["motif"] for e in corps["erreurs"]] == [
        "Délai global dépassé",
        job.NON_TRAITE,
        job.NON_TRAITE,
    ]
    assert apns._client is None


@pytest.mark.parametrize(
    "reglage, motif",
    [
        ({"apns_key": "pas une clé"}, "Jeton JWT APNs impossible à signer"),
        ({"apns_env": "prod"}, "APNS_ENV='prod' inconnu"),
        ({"apns_bundle_id": " "}, "APNs non configuré"),
    ],
)
def test_configuration_cassee_erreur_explicite(tous, base, monkeypatch, reglage, motif):
    reglages = apns.get_settings().model_copy(update=reglage)
    monkeypatch.setattr(apns, "get_settings", lambda: reglages)

    reponse = tous.post("/push/test/tous", headers={"X-Admin-Secret": SECRET})

    assert reponse.status_code == 503
    assert motif in reponse.json()["detail"]
    assert "pas une clé" not in reponse.json()["detail"]
    assert base.envois == []


def test_le_job_ne_reserve_rien_si_apns_est_casse(base, monkeypatch):
    def casse():
        raise apns.ErreurAPNs("clé illisible")

    monkeypatch.setattr(apns, "verifier_configuration", casse)
    asyncio.run(job.surveiller(COURSE - timedelta(hours=1)))

    assert base.envoyees == {("gp-1", job.OUVERTURE)}  # celle de la fixture, seule
    assert base.envois == []
