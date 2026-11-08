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
from app.scraper import unibet
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


# --------------------------------------------------------------------------- #
#  Événement de course renommé par Unibet (8 novembre 2026)
# --------------------------------------------------------------------------- #


# Libellé exact relevé sur le nœud racine, espace final compris.
RENOMME = "Paris spéciaux Course principale "


@pytest.mark.parametrize("libelle", ["Course", "course", " Course ", RENOMME, "Course principale"])
def test_la_course_est_reconnue(libelle):
    assert unibet.est_course(libelle)


@pytest.mark.parametrize(
    "libelle",
    [
        "Qualifications",
        "Paris spéciaux Qualifications",
        "Course sprint",
        "Paris spéciaux Course sprint",
        "Sprint",
        "Paris spéciaux Essais libres 1",
        "Essais libres 3",
        "Paris spéciaux Qualifications sprint",
        "Championnat du monde",
        "Vainqueur du championnat",
    ],
)
def test_les_autres_evenements_restent_ecartes(libelle):
    assert not unibet.est_course(libelle)


def _racine(*evenements):
    items = {"p59405528": {"desc": "GP du Brésil", "parent": unibet.RACINE_F1}}
    for identifiant, desc, start in evenements:
        items[identifiant] = {"desc": desc, "parent": "p59405528", "start": start}
    return {"items": items}


def test_decouvrir_le_gp_du_bresil_sous_son_nouveau_libelle(monkeypatch):
    async def json_lvs(_client, _noeud, _cle):
        return _racine(
            ("e3365675", RENOMME, "2611081700"),
            ("e3365600", "Paris spéciaux Qualifications", "2611071800"),
            ("e3365601", "Paris spéciaux Course sprint", "2611071400"),
        )

    monkeypatch.setattr(unibet, "_json_lvs", json_lvs)
    (gp,) = asyncio.run(unibet.decouvrir(None, "jeton"))
    assert (gp.id_unibet, gp.nom, gp.id_evenement) == ("p59405528", "GP du Brésil", "e3365675")
    assert gp.date_course == datetime(2026, 11, 8, 17, 0, tzinfo=UTC)
    assert gp.qualifications == [datetime(2026, 11, 7, 18, 0, tzinfo=UTC)]
    # L'URL reste celle que sert Unibet, `/course`.
    assert unibet.url_evenement(gp, unibet.CATEGORIE_F1).endswith("/gp-du-bresil/3365675/course")


def test_seuls_des_evenements_speciaux_aucune_course(monkeypatch):
    async def json_lvs(_client, _noeud, _cle):
        return _racine(("e1", "Paris spéciaux Course sprint", "2611071400"))

    monkeypatch.setattr(unibet, "_json_lvs", json_lvs)
    with pytest.raises(unibet.ErreurScraper, match="Aucune course trouvée"):
        asyncio.run(unibet.decouvrir(None, "jeton"))


# --------------------------------------------------------------------------- #
#  Un échec de découverte déclenche l'alerte
# --------------------------------------------------------------------------- #

DECOUVERTE = unibet.ErreurScraper(
    "Aucune course trouvée sous le nœud racine. 1 nœud(s) examiné(s), 1 événement(s) écarté(s)."
)


def test_echec_de_decouverte_au_job_alerte(base, monkeypatch):
    async def panne():
        raise DECOUVERTE

    monkeypatch.setattr(job, "scraper", panne)
    tour(PREVU + timedelta(hours=1))
    alerte = base.alertes[("gp-bresil", job.COTES_EN_RETARD, "")]
    assert "Aucune course trouvée" in alerte["derniere_erreur"]
    assert len(base.notifications) == 1


def test_echec_de_decouverte_au_declenchement_manuel_alerte(base, monkeypatch):
    async def panne():
        raise DECOUVERTE

    monkeypatch.setattr(job, "scraper", panne)
    reel = job.datetime

    class Horloge(reel):
        @classmethod
        def now(cls, tz=None):
            return PREVU + timedelta(hours=7)

    monkeypatch.setattr(job, "datetime", Horloge)
    asyncio.run(job.declencher_en_tache_de_fond())
    alerte = base.alertes[("gp-bresil", job.COTES_EN_RETARD, "")]
    assert "Aucune course trouvée" in alerte["derniere_erreur"]
    assert len(base.notifications) == 1


def test_echec_manuel_dans_la_premiere_heure_n_alerte_pas(base, monkeypatch):
    async def panne():
        raise DECOUVERTE

    monkeypatch.setattr(job, "scraper", panne)
    asyncio.run(job._signaler_les_retards("x", PREVU + timedelta(minutes=30)))
    assert base.alertes == {}


# --------------------------------------------------------------------------- #
#  Pas de figeage sans le marché « Vainqueur » (page partielle du 8 novembre)
# --------------------------------------------------------------------------- #

PARTIELLE = {
    "grands_prix": [
        {"nom": "GP du Brésil", "gp_id": "gp-bresil", "cotes": 20, "marches": ["top-2"], "fige": False}
    ],
    "echecs": [],
}
COMPLETE = {
    "grands_prix": [
        {
            "nom": "GP du Brésil",
            "gp_id": "gp-bresil",
            "cotes": 146,
            "marches": ["podium", "top-2", "vainqueur"],
            "fige": False,
        }
    ],
    "echecs": [],
}


def test_une_page_sans_vainqueur_ne_fige_pas_et_alerte(base):
    base.unibet = PARTIELLE
    tour(PREVU + timedelta(hours=7))
    assert base.gp["statut"] == "a_venir"
    alerte = base.alertes[("gp-bresil", job.COTES_EN_RETARD, "")]
    assert "marché « vainqueur » absent" in alerte["derniere_erreur"]
    assert "top-2" in alerte["derniere_erreur"]

    base.unibet = COMPLETE
    tour(PREVU + timedelta(hours=7, minutes=15))
    assert base.gp["statut"] == "cotes_figees"
    assert base.alertes == {}


def test_le_declenchement_manuel_ne_fige_pas_non_plus_sans_vainqueur(base):
    base.unibet = PARTIELLE
    asyncio.run(job.declencher_en_tache_de_fond())
    assert base.gp["statut"] == "a_venir"

    base.unibet = COMPLETE
    asyncio.run(job.declencher_en_tache_de_fond())
    assert base.gp["statut"] == "cotes_figees"


def test_marche_requis_absent():
    assert job.marche_requis_absent({"cotes": 3, "marches": ["vainqueur"]}) is None
    assert job.marche_requis_absent({"cotes": 3}) is None  # compte rendu ancien
    assert "absent" in job.marche_requis_absent({"cotes": 3, "marches": ["top-2"]})
