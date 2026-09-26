"""Fixtures communes : les quatre Grands Prix 2026 rejoués par l'audit.

Chaque fichier de `fixtures/gp/` porte ce que `calculer()` reçoit en production
(`donnees_brutes`, cotes, pronostics) et les verdicts de la base, désormais
justes. Leur provenance est écrite dans la clé `source` de chaque fichier.
"""

import json
import logging
from pathlib import Path

import pytest

FIXTURES = Path(__file__).parent / "fixtures" / "gp"

GPS = ("pays-bas", "italie", "espagne", "azerbaidjan")

# Référence des causes, pour les raisons des tests marqués xfail.
AUDIT = "docs/audit-evaluation.md §4.3"


def charger_gp(nom: str) -> dict:
    return json.loads((FIXTURES / f"{nom}.json").read_text(encoding="utf-8"))


@pytest.fixture(autouse=True)
def _journal_muet():
    """`points.py` journalise chaque pronostic en attente : inutile en test."""
    journal = logging.getLogger("uvicorn.error")
    journal.disabled = True
    yield
    journal.disabled = False
