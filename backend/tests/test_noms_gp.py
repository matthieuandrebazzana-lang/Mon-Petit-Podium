"""Noms des Grands Prix dans les notifications — `app/noms_gp.py`.

Le nom anglais ne se dérive jamais du libellé français de la base : « GP du
Mexique » donnait « for the du Mexique GP ». Ces tests passent les quatre
modèles, en français et en anglais, sur chaque GP de la saison 2026, et
vérifient que les noms anglais sont ceux du calendrier de l'app iOS.
"""

import re
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
