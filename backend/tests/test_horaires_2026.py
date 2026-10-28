"""Horaires 2026 : les tables statiques, leurs heures locales et le Mexique.

Le GP du Mexique affichait ses qualifications 2 h trop tard et sa course 1 h trop
tard (migration 33) : deux heures locales devinées, pas un fuseau. Ces tests
relisent les deux tables statiques — `GP_2026` (web, propriétaire) et
`FichesGrandPrix.horaires` (iOS, transcription) — et convertissent leurs instants
dans le fuseau du circuit, de part et d'autre des changements d'heure d'automne :
le Mexique n'en a plus depuis 2022, les États-Unis reculent le 1ᵉʳ novembre.
"""

import re
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

RACINE = Path(__file__).resolve().parents[2]
WEB = RACINE / "frontend" / "src" / "lib" / "calendrier2026.js"
IOS = RACINE / "ios" / "Greed F1" / "Views" / "Calendrier" / "FichesGrandPrix.swift"
MIGRATION_33 = RACINE / "supabase" / "migrations" / "20261027130000_horaires_mexique_2026.sql"


def _seances_web() -> dict[str, dict[str, str]]:
    texte = WEB.read_text(encoding="utf-8")
    tables = {}
    for slug, bloc in re.findall(r'slug: "([a-z-]+)".*?seances: \{(.*?)\}', texte, re.S):
        tables[slug] = dict(re.findall(r'(\w+): "([^"]+)"', bloc))
    return tables


def _seances_ios() -> dict[str, dict[str, str]]:
    texte = IOS.read_text(encoding="utf-8")
    bloc = texte.split("horaires: [String: [String: String]] = [", 1)[1].split("\n    ]\n", 1)[0]
    return {
        slug: dict(re.findall(r'"(\w+)": "([^"]+)"', corps))
        for slug, corps in re.findall(r'"([a-z-]+)": \[(.*?)\]', bloc, re.S)
    }


def _locale(iso: str, fuseau: str) -> str:
    instant = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return instant.astimezone(ZoneInfo(fuseau)).strftime("%a %H:%M")


def test_ios_recopie_exactement_le_web():
    web, ios = _seances_web(), _seances_ios()
    assert ios, "table iOS introuvable"
    for slug, seances in ios.items():
        assert seances == web[slug], slug


def test_mexique_aux_heures_officielles():
    # OpenF1, sessions 11400 et 11404 — UTC−6 toute l'année.
    seances = _seances_web()["mexique"]
    assert seances["qualifications"] == "2026-10-31T21:00:00Z"
    assert seances["course"] == "2026-11-01T20:00:00Z"
    assert _locale(seances["qualifications"], "America/Mexico_City") == "Sat 15:00"
    assert _locale(seances["course"], "America/Mexico_City") == "Sun 14:00"


def test_austin_encore_a_l_heure_d_ete_le_25_octobre():
    # Les États-Unis ne reculent que le 1ᵉʳ novembre : Austin est en CDT (UTC−5).
    seances = _seances_web()["etats-unis"]
    assert _locale(seances["el1"], "America/Chicago") == "Fri 12:30"


def test_le_mexique_ne_suit_pas_le_changement_d_heure_americain():
    # Même instant UTC de part et d'autre du 1ᵉʳ novembre : Mexico ne bouge pas,
    # Chicago recule d'une heure. Une table qui supposerait l'inverse décalerait
    # le Mexique d'une heure.
    avant, apres = "2026-10-31T21:00:00Z", "2026-11-01T21:00:00Z"
    assert _locale(avant, "America/Mexico_City")[4:] == _locale(apres, "America/Mexico_City")[4:]
    assert _locale(avant, "America/Chicago")[4:] == "16:00"
    assert _locale(apres, "America/Chicago")[4:] == "15:00"


def test_la_migration_33_pose_les_memes_instants_que_la_table():
    sql = MIGRATION_33.read_text(encoding="utf-8")
    assert "set date_qualifications = timestamptz '2026-10-31 21:00:00+00'" in sql
    assert "set date_course = timestamptz '2026-11-01 20:00:00+00'" in sql
