"""Provisoire puis définitif : Bakou 2026, avant et après la pénalité de Bortoleto.

À l'arrivée, OpenF1 place Bortoleto 13ᵉ à +34,230 s. Une pénalité de 10 s le
renvoie ensuite 15ᵉ, derrière Piastri et Pérez (`docs/audit-evaluation.md` §3).
Le classement de la fixture est le définitif ; le provisoire en est dérivé.

Le job tourne ici de bout en bout sur une base simulée en mémoire : ce qui est
vérifié, c'est le chemin réel de `traiter` puis de `consolider`, jusqu'aux
arguments passés à `attribuer_points` et à `remplacer_verdicts`. Les deux
fonctions SQL sont reproduites dans leur sémantique : la première n'écrit que
les `NULL`, la seconde remplace tout.
"""

import asyncio
import copy
from datetime import UTC, datetime, timedelta

import pytest

from app.jobs import resultats as job
from conftest import charger_gp

GP_ID = "3bf1ef36-f97c-446c-a8c6-e605f9750cd4"
BORTOLETO, PIASTRI, PEREZ = 5, 81, 11

# Un face-à-face ajouté aux pronostics réels : le seul marché de Bakou que la
# pénalité fait basculer.
DUEL = "face-a-face-g-bortoleto-o-piastri"
PARI_BORTOLETO = "00000000-0000-4000-8000-00000000b0b0"


def _classement_provisoire(definitif: list[dict]) -> list[dict]:
    """Le classement de l'arrivée : Bortoleto 13ᵉ, Piastri 14ᵉ, Pérez 15ᵉ."""
    lignes = copy.deepcopy(definitif)
    for ligne in lignes:
        if ligne["driver_number"] == BORTOLETO:
            ligne.update(position=13, gap_to_leader=34.23)
        elif ligne["driver_number"] == PIASTRI:
            ligne["position"] = 14
        elif ligne["driver_number"] == PEREZ:
            ligne["position"] = 15
    return sorted(lignes, key=lambda l: (l["position"] is None, l["position"] or 0))


class BaseSimulee:
    """Ce que le job lit et écrit dans Supabase, en mémoire."""

    def __init__(self, gp: dict, date_course: str):
        self.gp = {
            "id": GP_ID,
            "nom": "GP Azerbaïdjan",
            "date_course": date_course,
            "statut": "cotes_figees",
            "statut_resultats": None,
        }
        self.cotes = copy.deepcopy(gp["cotes"])
        for identifiant, pilote, valeur in (("o-bor", "G.Bortoleto", 18), ("o-pia", "O.Piastri", 20)):
            self.cotes[identifiant] = {
                "id_outcome_unibet": identifiant, "marche": DUEL, "pilote": pilote, "valeur": valeur,
            }
        self.pronostics = {
            p["id"]: {**copy.deepcopy(p), "profil_id": "joueur", "points_gagnes": None,
                      "statut_evaluation": "en_attente"}
            for p in gp["pronostics"]
        }
        self.pronostics[PARI_BORTOLETO] = {
            "id": PARI_BORTOLETO, "profil_id": "joueur", "type": "bonus",
            "id_outcome_unibet": "o-bor", "points_gagnes": None, "statut_evaluation": "en_attente",
        }
        self.resultats: dict | None = None
        self.appels: list[str] = []
        self.alertes: dict[str, dict] = {}

    # -- supabase_client ---------------------------------------------------- #

    async def selectionner(self, table: str, parametres: dict) -> list[dict]:
        if table == "grands_prix":
            if parametres.get("statut_resultats") == f"eq.{job.PROVISOIRE}":
                return [dict(self.gp)] if self.gp["statut_resultats"] == job.PROVISOIRE else []
            return [dict(self.gp)]
        if table == "resultats_gp":
            return [{"donnees_brutes": copy.deepcopy(self.resultats)}] if self.resultats else []
        if table == "cotes":
            return list(copy.deepcopy(self.cotes).values())
        if table == "pronostics":
            lignes = list(self.pronostics.values())
            if parametres.get("points_gagnes") == "is.null":
                lignes = [p for p in lignes if p["points_gagnes"] is None]
            return copy.deepcopy(lignes)
        raise AssertionError(table)

    async def upserter(self, table: str, lignes: list[dict], _cle: str) -> list[dict]:
        assert table == "resultats_gp"
        self.resultats = copy.deepcopy(lignes[0]["donnees_brutes"])
        return lignes

    async def mettre_a_jour(self, table: str, _filtre: dict, valeurs: dict) -> list[dict]:
        assert table == "grands_prix"
        self.gp.update(valeurs)
        return [dict(self.gp)]

    async def supprimer(self, table: str, _filtre: dict) -> list[dict]:
        assert table == "alertes_admin"
        supprimees = list(self.alertes.values())
        self.alertes.clear()
        return supprimees

    async def appeler_fonction(self, nom: str, arguments: dict):
        self.appels.append(nom)
        if nom == "noter_echec_definitif":
            alerte = self.alertes.setdefault(arguments["p_gp"], {"tentatives": 0})
            alerte.update(tentatives=alerte["tentatives"] + 1, derniere_erreur=arguments["p_erreur"])
            return alerte["tentatives"]
        entrees = {a["pronostic_id"]: a for a in arguments["p_attributions"]}
        if nom == "attribuer_points":
            for pid, entree in entrees.items():
                prono = self.pronostics[pid]
                if prono["points_gagnes"] is None:
                    self._ecrire(prono, entree)
            return {"attribues": 0, "restants": 0}
        if nom == "remplacer_verdicts":
            if arguments["p_donnees"] is not None:
                self.resultats = copy.deepcopy(arguments["p_donnees"])
            modifies = 0
            for pid, prono in self.pronostics.items():
                avant = (prono["points_gagnes"], prono["statut_evaluation"])
                self._ecrire(prono, entrees.get(pid, {"points": None, "statut": "en_attente"}))
                modifies += avant != (prono["points_gagnes"], prono["statut_evaluation"])
            self.gp.update(statut="termine", statut_resultats=arguments["p_statut_resultats"])
            return {"modifies": modifies, "attribues": 0, "restants": 0}
        raise AssertionError(nom)

    @staticmethod
    def _ecrire(prono: dict, entree: dict) -> None:
        points = entree.get("points")
        prono["points_gagnes"] = points
        if points is None:
            prono["statut_evaluation"] = entree.get("statut") or "en_attente"
        else:
            prono["statut_evaluation"] = "gagne" if points > 0 else "perdu"

    def points(self) -> dict[str, int | None]:
        return {pid: p["points_gagnes"] for pid, p in self.pronostics.items()}


@pytest.fixture
def bakou(monkeypatch):
    """La base simulée, et OpenF1 qui rend le provisoire puis le définitif."""
    gp = charger_gp("azerbaidjan")
    definitif = copy.deepcopy(gp["donnees_brutes"])
    provisoire = copy.deepcopy(definitif)
    provisoire["session_result"] = _classement_provisoire(definitif["session_result"])

    # Couru il y a 25 heures : le définitif est échu.
    depart = (datetime.now(UTC) - timedelta(hours=25)).isoformat()
    base = BaseSimulee(gp, depart)
    reponses = [provisoire, definitif]

    async def recuperer(_nom, _depart):
        return copy.deepcopy(reponses.pop(0))

    async def completer_qualification(_nom, _donnees):
        return False

    for nom in ("selectionner", "upserter", "mettre_a_jour", "appeler_fonction", "supprimer"):
        monkeypatch.setattr(job, nom, getattr(base, nom))
    monkeypatch.setattr(job, "recuperer", recuperer)
    monkeypatch.setattr(job, "completer_qualification", completer_qualification)
    base.attendus = gp["attendus"]
    return base


def _position(donnees: dict, numero: int) -> int | None:
    return next(l["position"] for l in donnees["session_result"] if l["driver_number"] == numero)


def test_bakou_provisoire_puis_definitif(bakou):
    # 1. Arrivée : Bortoleto 13ᵉ, devant Piastri. Le face-à-face est gagné, et
    #    les points comptent aussitôt.
    rapport = asyncio.run(job.traiter(dict(bakou.gp)))
    assert rapport["statut_resultats"] == job.PROVISOIRE
    assert bakou.gp["statut"] == "termine"
    assert bakou.gp["statut_resultats"] == job.PROVISOIRE
    assert _position(bakou.resultats, BORTOLETO) == 13
    assert bakou.points()[PARI_BORTOLETO] == 18
    assert bakou.appels == ["attribuer_points"]

    provisoires = bakou.points()

    # 2. J+1 : OpenF1 relue, Bortoleto 15ᵉ. Le verdict DÉJÀ écrit bascule, en un
    #    seul appel transactionnel.
    asyncio.run(job.consolider_echus())
    assert bakou.appels == ["attribuer_points", "remplacer_verdicts"]
    assert bakou.gp["statut_resultats"] == job.DEFINITIF
    assert _position(bakou.resultats, BORTOLETO) == 15
    assert _position(bakou.resultats, PIASTRI) == 13
    assert bakou.points()[PARI_BORTOLETO] == 0
    assert bakou.pronostics[PARI_BORTOLETO]["statut_evaluation"] == "perdu"

    # Les pronostics réels de Bakou ne dépendaient pas de Bortoleto : aucun ne
    # bouge, et tous ont un verdict (le triplé et la marge compris).
    definitifs = bakou.points()
    for pid in bakou.attendus:
        assert definitifs[pid] == provisoires[pid]
        assert definitifs[pid] is not None
    assert {pid: definitifs[pid] for pid, v in bakou.attendus.items() if v is not None} == {
        pid: v for pid, v in bakou.attendus.items() if v is not None
    }


def test_definitif_pas_avant_24_heures(bakou):
    asyncio.run(job.traiter(dict(bakou.gp)))
    bakou.gp["date_course"] = (datetime.now(UTC) - timedelta(hours=23)).isoformat()

    asyncio.run(job.consolider_echus())

    assert bakou.appels == ["attribuer_points"]
    assert bakou.gp["statut_resultats"] == job.PROVISOIRE
    assert bakou.points()[PARI_BORTOLETO] == 18


def test_plus_aucun_recalcul_automatique_apres_le_definitif(bakou):
    asyncio.run(job.traiter(dict(bakou.gp)))
    asyncio.run(job.consolider_echus())
    asyncio.run(job.consolider_echus())  # le GP n'est plus provisoire

    assert bakou.appels == ["attribuer_points", "remplacer_verdicts"]
    with pytest.raises(job.GrandPrixDefinitif):
        asyncio.run(job.traiter(dict(bakou.gp)))


def test_recalcul_admin_reserve_aux_gp_definitifs(bakou):
    asyncio.run(job.traiter(dict(bakou.gp)))
    with pytest.raises(job.GrandPrixNonDefinitif):
        asyncio.run(job.recalculer(GP_ID))

    asyncio.run(job.consolider_echus())
    # Un verdict faussé à la main : le recalcul, sans relire OpenF1, le rétablit.
    bakou.pronostics[PARI_BORTOLETO].update(points_gagnes=18, statut_evaluation="gagne")
    rapport = asyncio.run(job.recalculer(GP_ID))

    assert rapport["modifies"] == 1
    assert bakou.points()[PARI_BORTOLETO] == 0
    assert _position(bakou.resultats, BORTOLETO) == 15


def test_echecs_repetes_du_definitif_comptes_puis_effaces(bakou, monkeypatch):
    """`roadmap.md` §3.17 : le définitif réessaie sans fin, mais chaque échec est
    compté en base ; un succès efface l'alerte."""
    asyncio.run(job.traiter(dict(bakou.gp)))

    async def muette(_nom, _depart):
        raise job.ErreurOpenF1("session_result : statut 502.")

    recuperer = job.recuperer
    monkeypatch.setattr(job, "recuperer", muette)
    for _ in range(job.SEUIL_ALERTE_DEFINITIF):
        asyncio.run(job.consolider_echus())

    assert bakou.gp["statut_resultats"] == job.PROVISOIRE
    assert bakou.alertes[GP_ID] == {
        "tentatives": job.SEUIL_ALERTE_DEFINITIF,
        "derniere_erreur": "session_result : statut 502.",
    }

    monkeypatch.setattr(job, "recuperer", recuperer)
    asyncio.run(job.consolider_echus())
    assert bakou.gp["statut_resultats"] == job.DEFINITIF
    assert bakou.alertes == {}
