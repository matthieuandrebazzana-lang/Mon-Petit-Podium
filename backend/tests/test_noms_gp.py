"""Noms des Grands Prix dans les notifications — `app/noms_gp.py`.

Le nom anglais ne se dérive jamais du libellé français de la base : « GP du
Mexique » donnait « for the du Mexique GP ». Ces tests passent les quatre
modèles, en français et en anglais, sur chaque GP de la saison 2026, et
vérifient que les noms anglais sont ceux du calendrier de l'app iOS.
"""

import re
from datetime import UTC, date, datetime
from pathlib import Path

import pytest

from app import noms_gp
from app.jobs import notifications as job


@pytest.fixture
def absences(monkeypatch):
    """Les GP journalisés comme absents de la table (`uvicorn.error` ne propage pas)."""
    vus = []
    monkeypatch.setattr(noms_gp.logger, "warning", lambda _msg, nom, _slug: vus.append(nom))
    return vus

RACINE = Path(__file__).resolve().parents[2]
TRADUCTIONS_EN = RACINE / "ios" / "Greed F1" / "Localisation" / "TraductionsEN.swift"

# slug → (libellé en base, français attendu, anglais attendu).
SAISON_2026 = {
    "australie": ("GP Australie", "GP d'Australie", "Australian GP"),
    "chine": ("GP Chine", "GP de Chine", "Chinese GP"),
    "japon": ("GP Japon", "GP du Japon", "Japanese GP"),
    "miami": ("GP Miami", "GP de Miami", "Miami GP"),
    "canada": ("GP Canada", "GP du Canada", "Canadian GP"),
    "monaco": ("GP Monaco", "GP de Monaco", "Monaco GP"),
    "barcelone": ("GP Barcelone", "GP de Barcelone", "Barcelona GP"),
    "autriche": ("GP Autriche", "GP d'Autriche", "Austrian GP"),
    "grande-bretagne": ("GP Grande-Bretagne", "GP de Grande-Bretagne", "British GP"),
    "belgique": ("GP Belgique", "GP de Belgique", "Belgian GP"),
    "hongrie": ("GP Hongrie", "GP de Hongrie", "Hungarian GP"),
    "pays-bas": ("GP Pays Bas", "GP des Pays-Bas", "Dutch GP"),
    "italie": ("GP Italie", "GP d'Italie", "Italian GP"),
    "espagne": ("GP Espagne", "GP d'Espagne", "Spanish GP"),
    "azerbaidjan": ("GP Azerbaïdjan", "GP d'Azerbaïdjan", "Azerbaijan GP"),
    "malaisie": ("GP Malaisie", "GP de Malaisie", "Malaysian GP"),
    "singapour": ("GP Singapour", "GP de Singapour", "Singapore GP"),
    "etats-unis": ("GP États-Unis", "GP des États-Unis", "United States GP"),
    "mexique": ("GP du Mexique", "GP du Mexique", "Mexican GP"),
    "bresil": ("GP São Paulo", "GP du Brésil", "Brazilian GP"),
    "las-vegas": ("GP Las Vegas", "GP de Las Vegas", "Las Vegas GP"),
    "qatar": ("GP Qatar", "GP du Qatar", "Qatar GP"),
    "abu-dhabi": ("GP Abou Dabi", "GP d'Abu Dhabi", "Abu Dhabi GP"),
}

MODELES = {
    "fr": {
        job.OUVERTURE_24H: "Les pronos pour le {} ouvrent dans 24h",
        job.OUVERTURE: "Les pronos pour le {} sont ouverts",
        job.DERNIERE_CHANCE: "Dernière chance de faire tes pronos pour le {}",
        job.RESULTATS: "Les résultats du {} sont disponibles",
    },
    "en": {
        job.OUVERTURE_24H: "Predictions for the {} open in 24h",
        job.OUVERTURE: "Predictions for the {} are open",
        job.DERNIERE_CHANCE: "Last chance to make your predictions for the {}",
        job.RESULTATS: "The {} results are available",
    },
}


def _noms_anglais_ios() -> dict[str, str]:
    texte = TRADUCTIONS_EN.read_text(encoding="utf-8")
    return dict(re.findall(r'"gp\.([a-z-]+)\.nom": "([^"]+)"', texte))


def test_la_table_couvre_le_calendrier_ios_avec_les_memes_noms_anglais():
    ios = _noms_anglais_ios()
    assert set(ios) == set(SAISON_2026)
    for slug, nom in ios.items():
        assert noms_gp.NOMS[slug][1] == nom, slug


@pytest.mark.parametrize("slug", sorted(SAISON_2026))
@pytest.mark.parametrize("langue", ["fr", "en"])
@pytest.mark.parametrize("evenement", [job.OUVERTURE_24H, job.OUVERTURE, job.DERNIERE_CHANCE, job.RESULTATS])
def test_quatre_modeles_pour_chaque_gp(slug, langue, evenement, absences):
    libelle, francais, anglais = SAISON_2026[slug]
    attendu = MODELES[langue][evenement].format(francais if langue == "fr" else anglais)
    assert job.texte(evenement, libelle, langue) == attendu
    assert absences == []


@pytest.mark.parametrize(
    ("libelle", "slug"),
    [
        ("GP Mexique", "mexique"),
        ("GP du Mexique", "mexique"),
        ("Mexico City GP", "mexique"),
        ("GP Brésil", "bresil"),
        ("GP du Brésil", "bresil"),
        ("GP São Paulo", "bresil"),
        ("GP Pays-Bas", "pays-bas"),
        ("GP des Pays-Bas", "pays-bas"),
        ("GP d'Italie", "italie"),
        ("GP de Las Vegas", "las-vegas"),
        ("GP Las Vegas", "las-vegas"),
        ("GP des États-Unis", "etats-unis"),
        ("GP Émirats arabes unis", "abu-dhabi"),
        ("GP Bahrein", "bahrein"),
        ("Grand Prix du Qatar", "qatar"),
    ],
)
def test_libelles_unibet(libelle, slug):
    assert noms_gp.slug_du_gp(libelle) == slug


@pytest.mark.parametrize(
    ("libelle", "francais", "anglais"),
    [
        ("GP de Corée", "Grand Prix Corée", "Grand Prix Corée"),
        ("GP Afrique du Sud", "Grand Prix Afrique du Sud", "Grand Prix Afrique du Sud"),
        ("", "Grand Prix", "Grand Prix"),
    ],
)
def test_gp_inconnu_formulation_neutre_et_journalisee(libelle, francais, anglais, absences):
    assert noms_gp.nom_du_gp(libelle, "fr") == francais
    assert noms_gp.nom_du_gp(libelle, "en") == anglais
    assert absences == [libelle, libelle]
    assert job.texte(job.DERNIERE_CHANCE, libelle, "en") == (
        f"Last chance to make your predictions for the {anglais}"
    )
    assert job.texte(job.RESULTATS, libelle, "fr") == f"Les résultats du {francais} sont disponibles"


# --- La date de course passe avant le nom, comme `SlugCircuit.de(_:dateCourse:)` (iOS) ---

SAISON_IOS = RACINE / "ios" / "Greed F1" / "Models" / "GrandPrixSaison.swift"
MOIS_IOS = {
    "JANV": 1, "FÉVR": 2, "MARS": 3, "AVR": 4, "MAI": 5, "JUIN": 6,
    "JUIL": 7, "AOÛT": 8, "SEPT": 9, "OCT": 10, "NOV": 11, "DÉC": 12,
}


def test_le_calendrier_est_celui_de_l_app_ios():
    texte = SAISON_IOS.read_text(encoding="utf-8")
    ios = {
        slug: date(2026, MOIS_IOS[mois], int(jour))
        for slug, jour, mois in re.findall(r'\.init\(slug: "([a-z-]+)", jour: "(\d+)", mois: "([^"]+)"', texte)
    }
    assert ios == noms_gp.CALENDRIER_2026


def test_gp_bahrein_couru_a_sepang_est_le_gp_de_malaisie(absences):
    depart = "2026-10-04T07:00:00+00:00"
    assert noms_gp.slug_du_gp("GP Bahrein", depart) == "malaisie"
    assert noms_gp.nom_du_gp("GP Bahrein", "fr", depart) == "GP de Malaisie"
    assert noms_gp.nom_du_gp("GP Bahrein", "en", depart) == "Malaysian GP"
    assert job.textes(job.DERNIERE_CHANCE, "GP Bahrein", depart) == {
        "fr": "Dernière chance de faire tes pronos pour le GP de Malaisie",
        "en": "Last chance to make your predictions for the Malaysian GP",
    }
    assert absences == []


def test_gp_renomme_par_unibet_retrouve_par_sa_date(absences):
    depart = datetime(2026, 11, 8, 17, 0, tzinfo=UTC)
    assert noms_gp.slug_du_gp("GP São Paulo", depart) == "bresil"
    assert job.texte(job.RESULTATS, "GP São Paulo", "en", depart) == "The Brazilian GP results are available"
    assert job.texte(job.RESULTATS, "GP São Paulo", "fr", "2026-11-08T17:00:00Z") == (
        "Les résultats du GP du Brésil sont disponibles"
    )
    assert absences == []


@pytest.mark.parametrize("depart", [None, "", "pas une date", "2027-03-07T05:00:00Z"])
def test_gp_sans_date_ou_hors_calendrier_le_nom_tranche(depart, absences):
    assert noms_gp.slug_par_date(depart) is None
    assert noms_gp.slug_du_gp("GP Bahrein", depart) == "bahrein"
    assert noms_gp.nom_du_gp("GP Bahrein", "en", depart) == "Bahrain GP"
    assert noms_gp.nom_du_gp("GP São Paulo", "fr", depart) == "GP du Brésil"
    assert absences == []


@pytest.mark.parametrize(
    ("depart", "slug"),
    [
        # Las Vegas est écrit le 21 et part le 22 à 06:00 UTC.
        ("2026-11-22T06:00:00Z", "las-vegas"),
        # Mexique, un dimanche soir UTC : le Brésil, sept jours plus tard, ne l'attire pas.
        ("2026-11-01T20:00:00Z", "mexique"),
        # Un départ en heure locale, ramené en UTC.
        ("2026-10-04T15:00:00+08:00", "malaisie"),
    ],
)
def test_tolerance_de_trois_jours(depart, slug):
    assert noms_gp.slug_par_date(depart) == slug
