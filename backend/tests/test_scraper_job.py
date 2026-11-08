"""Job de scraping : rattrapage jusqu'au départ, alerte admin (GP du Brésil 2026).

Le 7 novembre 2026, les cotes du Brésil n'étaient pas en base à la fin de la
fenêtre fixe de quatre heures, et le job s'est tu : elles n'ont été récupérées
que par un déclenchement manuel. Ces tests tiennent les trois règles qui
l'empêchent de se reproduire — réessayer tant que les cotes manquent, jusqu'au
départ ; alerter une heure après l'heure prévue ; une notification admin, une
seule.
"""

import asyncio
from datetime import UTC, datetime, timedelta

import pytest

from app.jobs import scraper as job
from app.supabase_client import ErreurSupabase

QUALIFS = datetime(2026, 11, 7, 18, 0, tzinfo=UTC)
PREVU = QUALIFS + timedelta(hours=2)
COURSE = datetime(2026, 11, 8, 17, 0, tzinfo=UTC)

GP = {
    "id": "gp-bresil",
    "nom": "GP Brésil",
    "statut": "a_venir",
    "date_qualifications": QUALIFS.isoformat(),
    "date_course": COURSE.isoformat(),
}

ABSENT = {"grands_prix": [], "echecs": [], "cotes_enregistrees": 0}
PUBLIE = {
    "grands_prix": [{"nom": "GP São Paulo", "gp_id": "gp-bresil", "cotes": 44, "fige": False}],
    "echecs": [],
}


class Base:
    """`grands_prix` et `alertes_admin` en mémoire, Unibet simulé."""

    def __init__(self):
        self.gp = dict(GP)
        self.alertes: dict[tuple, dict] = {}
        self.unibet = ABSENT
        self.scrapings = 0
        self.notifications: list[dict] = []
        self.refuser_alerte = False

    async def selectionner(self, table, parametres):
        assert table == "grands_prix"
        return [self.gp] if self.gp["statut"] == "a_venir" else []

    async def scraper(self):
        self.scrapings += 1
        return self.unibet

    async def mettre_a_jour(self, table, parametres, valeurs):
        if table == "grands_prix":
            if self.gp["statut"] != parametres["statut"].removeprefix("eq."):
                return []
            self.gp.update(valeurs)
            return [self.gp]
        assert table == "alertes_admin"
        for alerte in self.alertes.values():
            alerte.update(valeurs)
        return list(self.alertes.values())

    async def inserer_sans_doublon(self, table, ligne, sur_conflit=None):
        assert (table, sur_conflit) == ("alertes_admin", "gp_id,type,cle")
        if self.refuser_alerte:
            raise ErreurSupabase("violates check constraint alertes_admin_type_valide")
        cle = (ligne["gp_id"], ligne["type"], ligne["cle"])
        if cle in self.alertes:
            return False
        self.alertes[cle] = dict(ligne)
        return True

    async def supprimer(self, table, parametres):
        assert table == "alertes_admin"
        retirees = [
            cle
            for cle in self.alertes
            if f"eq.{cle[0]}" == parametres["gp_id"] and f"eq.{cle[1]}" == parametres["type"]
        ]
        for cle in retirees:
            del self.alertes[cle]
        return retirees

    async def notifier_admins(self, messages):
        self.notifications.append(messages)
        return {"envoyees": 1, "echecs": 0}


@pytest.fixture
def base(monkeypatch):
    simulee = Base()
    for nom in ("selectionner", "scraper", "mettre_a_jour", "inserer_sans_doublon", "supprimer"):
        monkeypatch.setattr(job, nom, getattr(simulee, nom))
    monkeypatch.setattr(job.notifications, "notifier_admins", simulee.notifier_admins)

    async def rattacher(_gp_id, _nom):
        return None

    monkeypatch.setattr(job, "rattacher_sans_echec", rattacher)
    job._signales_en_memoire.clear()
    return simulee


def tour(instant):
    asyncio.run(job.surveiller(instant))


# --------------------------------------------------------------------------- #
#  Échéances
# --------------------------------------------------------------------------- #


def test_echeances_du_bresil():
    assert job.echeances(GP) == (PREVU, PREVU + timedelta(hours=1), COURSE)


def test_sans_depart_connu_le_rattrapage_a_une_borne():
    prevu, _, limite = job.echeances({**GP, "date_course": None})
    assert limite == prevu + job.RATTRAPAGE_SANS_DEPART


def test_sans_qualifications_rien():
    assert job.echeances({**GP, "date_qualifications": None}) is None


def test_rien_avant_l_heure_prevue(base):
    tour(PREVU - timedelta(minutes=1))
    assert base.scrapings == 0


# --------------------------------------------------------------------------- #
#  Cotes publiées en retard, rattrapage jusqu'au départ
# --------------------------------------------------------------------------- #


def test_cotes_publiees_en_retard_sont_rattrapees(base):
    """Page Unibet absente jusqu'à prévu + 5 h : l'ancienne fenêtre de 4 h se taisait."""
    instant = PREVU
    while instant < PREVU + timedelta(hours=5):
        tour(instant)
        instant += job.INTERVALLE
    assert base.gp["statut"] == "a_venir"
    essais = base.scrapings

    base.unibet = PUBLIE
    tour(PREVU + timedelta(hours=5))
    assert base.scrapings == essais + 1
    assert base.gp["statut"] == "cotes_figees"

    # Figé : plus aucun scraping, plus candidat.
    tour(PREVU + timedelta(hours=5, minutes=15))
    assert base.scrapings == essais + 1


def test_le_rattrapage_court_jusqu_au_depart(base):
    tour(COURSE - timedelta(minutes=1))
    assert base.scrapings == 1


def test_apres_le_depart_on_ne_scrape_plus(base):
    base.unibet = PUBLIE
    tour(COURSE)
    tour(COURSE + timedelta(hours=1))
    assert base.scrapings == 0
    assert base.gp["statut"] == "a_venir"


def test_une_panne_du_scraper_est_retentee_au_tour_suivant(base, monkeypatch):
    async def panne():
        raise job.ErreurScraper("Jeton introuvable")

    monkeypatch.setattr(job, "scraper", panne)
    tour(PREVU)
    monkeypatch.setattr(job, "scraper", base.scraper)
    base.unibet = PUBLIE
    tour(PREVU + job.INTERVALLE)
    assert base.gp["statut"] == "cotes_figees"


# --------------------------------------------------------------------------- #
#  Alerte et notification admin
# --------------------------------------------------------------------------- #


def test_pas_d_alerte_dans_la_premiere_heure(base):
    for minutes in (0, 15, 30, 45):
        tour(PREVU + timedelta(minutes=minutes))
    assert base.alertes == {}
    assert base.notifications == []


def test_alerte_et_notification_une_heure_apres_l_heure_prevue(base):
    tour(PREVU + timedelta(hours=1))

    alerte = base.alertes[("gp-bresil", job.COTES_EN_RETARD, "")]
    assert "1 h 00 après l'heure prévue" in alerte["derniere_erreur"]
    assert "absent du compte rendu Unibet" in alerte["derniere_erreur"]
    assert len(base.notifications) == 1
    assert base.notifications[0] == {
        "fr": "⚠️ Cotes du GP du Brésil toujours absentes — le scraping réessaie jusqu'au départ.",
        "en": "⚠️ Brazilian GP odds still missing — scraping keeps retrying until the race start.",
    }


def test_une_seule_notification_les_tours_suivants_mettent_l_alerte_a_jour(base):
    for minutes in (60, 75, 90, 180):
        tour(PREVU + timedelta(minutes=minutes))
    assert len(base.notifications) == 1
    alerte = base.alertes[("gp-bresil", job.COTES_EN_RETARD, "")]
    assert "3 h 00 après" in alerte["derniere_erreur"]


def test_l_alerte_s_efface_au_figeage(base):
    tour(PREVU + timedelta(hours=1))
    assert base.alertes

    base.unibet = PUBLIE
    tour(PREVU + timedelta(hours=2))
    assert base.gp["statut"] == "cotes_figees"
    assert base.alertes == {}


def test_l_alerte_s_efface_au_declenchement_manuel(base):
    tour(PREVU + timedelta(hours=1))
    base.unibet = PUBLIE
    asyncio.run(job.declencher_en_tache_de_fond())
    assert base.gp["statut"] == "cotes_figees"
    assert base.alertes == {}


def test_une_panne_du_scraper_alerte_aussi(base, monkeypatch):
    async def panne():
        raise job.ErreurScraper("Jeton introuvable sur /paris-formule-1")

    monkeypatch.setattr(job, "scraper", panne)
    tour(PREVU + timedelta(hours=1, minutes=10))
    alerte = base.alertes[("gp-bresil", job.COTES_EN_RETARD, "")]
    assert "Jeton introuvable" in alerte["derniere_erreur"]
    assert len(base.notifications) == 1


def test_sans_la_migration_37_la_notification_part_quand_meme_une_fois(base):
    base.refuser_alerte = True
    for minutes in (60, 75, 90):
        tour(PREVU + timedelta(minutes=minutes))
    assert base.alertes == {}
    assert len(base.notifications) == 1


def test_un_gp_fige_par_un_autre_n_est_pas_un_echec(base):
    base.unibet = {
        "grands_prix": [{"nom": "GP Brésil", "gp_id": "gp-bresil", "cotes": 0, "fige": True}],
        "echecs": [],
    }
    tour(PREVU + timedelta(hours=2))
    assert base.alertes == {}
    assert base.notifications == []
