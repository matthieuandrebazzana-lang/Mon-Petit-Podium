"""Rattachement d'un Grand Prix d'Unibet à sa ligne : date de course d'abord.

Le cas fondateur : le 1er octobre 2026, Unibet publie « GP Bahrein » au 4
octobre — la course de Bahreïn, délocalisée à Sepang — là où la migration 19
avait posé « GP Malaisie ». Le rapprochement par le nom n'a rien reconnu et le
scraper a inséré une seconde ligne. Les lignes ci-dessous sont celles de la base
à ce moment-là, recopiées de `grands_prix`.
"""

import asyncio
from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient

from app.api.deps import exiger_admin
from app.api.routes import admin
from app.main import app
from app.scraper import unibet
from app.scraper.unibet import GRAND_PRIX_AMBIGU, ErreurScraper, GrandPrix, choisir_ligne

AZERBAIDJAN = {
    "id": "3bf1ef36", "nom": "GP Azerbaïdjan", "id_unibet": "p59405584",
    "statut": "termine", "date_course": "2026-09-26T11:00:00+00:00",
}
MALAISIE = {
    "id": "3118efe3", "nom": "GP Malaisie", "id_unibet": "manuel-malaisie-2026",
    "statut": "a_venir", "date_course": "2026-10-04T07:00:00+00:00",
}
SINGAPOUR = {
    "id": "676382b2", "nom": "GP Singapour", "id_unibet": "manuel-singapour-2026",
    "statut": "a_venir", "date_course": "2026-10-11T12:00:00+00:00",
}
LAS_VEGAS = {
    "id": "7f1df917", "nom": "GP Las Vegas", "id_unibet": "manuel-las-vegas-2026",
    "statut": "a_venir", "date_course": "2026-11-22T06:00:00+00:00",
}
QATAR = {
    "id": "7e28cc92", "nom": "GP Qatar", "id_unibet": "manuel-qatar-2026",
    "statut": "a_venir", "date_course": "2026-11-29T17:00:00+00:00",
}

BASE = [AZERBAIDJAN, MALAISIE, SINGAPOUR, LAS_VEGAS, QATAR]


def _gp(nom, id_unibet, depart):
    return GrandPrix(id_unibet=id_unibet, nom=nom, id_evenement="e", date_course=depart)


BAHREIN = _gp("GP Bahrein", "p59469828", datetime(2026, 10, 4, 7, 0, tzinfo=UTC))


# --  choisir_ligne : la décision, sans base  -----------------------------------


def test_bahrein_a_sepang_adopte_la_ligne_manuelle_malaisie():
    decision = choisir_ligne(BAHREIN, BASE)

    assert decision.refus is None
    assert decision.ligne is MALAISIE
    assert decision.adopter is True
    assert decision.par == "date"


def test_la_date_l_emporte_sur_un_nom_qui_designe_une_autre_ligne():
    # Unibet nomme « GP Singapour » la course du 4 octobre : c'est la date qui
    # tranche, la ligne de Singapour (11 octobre) n'est pas touchée.
    gp = _gp("GP Singapour", "p1", datetime(2026, 10, 4, 7, 0, tzinfo=UTC))
    assert choisir_ligne(gp, BASE).ligne is MALAISIE


def test_un_depart_decale_de_quelques_heures_reste_dans_le_week_end():
    gp = _gp("GP Las Vegas", "p2", datetime(2026, 11, 21, 4, 0, tzinfo=UTC))
    assert choisir_ligne(gp, BASE).ligne is LAS_VEGAS


def test_le_week_end_voisin_n_est_jamais_atteint():
    # Las Vegas → Qatar : sept jours et onze heures. Un départ au milieu de la
    # semaine ne tombe dans aucun week-end, et le nom inconnu ne repêche rien :
    # aucun candidat, c'est un Grand Prix nouveau.
    gp = _gp("GP Inconnu", "p3", datetime(2026, 11, 25, 12, 0, tzinfo=UTC))
    decision = choisir_ligne(gp, BASE)
    assert decision.ligne is None
    assert decision.refus is None


def test_aucun_candidat_n_est_pas_un_refus():
    gp = _gp("GP Thaïlande", "p8", datetime(2027, 3, 14, 8, 0, tzinfo=UTC))
    decision = choisir_ligne(gp, BASE)
    assert (decision.ligne, decision.refus, decision.adopter) == (None, None, False)


def test_la_ligne_qui_porte_deja_l_identifiant_est_retenue():
    adoptee = {**MALAISIE, "nom": "GP Bahrein", "id_unibet": "p59469828"}
    decision = choisir_ligne(BAHREIN, [AZERBAIDJAN, adoptee, SINGAPOUR])

    assert decision.ligne is adoptee
    assert decision.par == "identifiant"
    assert decision.adopter is False
    assert decision.doublons == []


def test_un_doublon_deja_forme_est_signale_sans_fusion():
    scrapee = {**MALAISIE, "id": "16a9c686", "nom": "GP Bahrein", "id_unibet": "p59469828"}
    decision = choisir_ligne(BAHREIN, [MALAISIE, scrapee])

    assert decision.ligne is scrapee
    assert decision.adopter is False
    assert decision.doublons == [MALAISIE]


def test_deux_lignes_le_meme_week_end_ne_font_rien_creer():
    autre = {**MALAISIE, "id": "x", "nom": "GP Autre", "id_unibet": "manuel-autre-2026"}
    decision = choisir_ligne(BAHREIN, [MALAISIE, autre])

    assert decision.ligne is None
    assert "2 lignes occupent ce week-end" in decision.refus


def test_une_ligne_reelle_sous_un_autre_identifiant_n_est_pas_reecrite():
    # Unibet a changé d'événement : réécrire l'identifiant d'une ligne
    # peut-être figée n'est pas un geste automatique.
    reelle = {**MALAISIE, "id_unibet": "p11111111", "statut": "cotes_figees"}
    decision = choisir_ligne(BAHREIN, [reelle])

    assert decision.ligne is None
    assert "autre identifiant Unibet" in decision.refus


def test_sans_depart_le_nom_sert_de_repli():
    gp = _gp("GP Pays Bas", "p4", None)
    manuelle = {"id": "nl", "nom": "GP Pays-Bas", "id_unibet": "manuel-pays-bas-2026",
                "statut": "a_venir", "date_course": None}
    decision = choisir_ligne(gp, [manuelle, MALAISIE])

    assert decision.ligne is manuelle
    assert decision.par == "nom"


def test_un_grand_prix_reporte_est_retrouve_par_son_nom():
    # Aucune ligne au nouveau week-end : le nom repêche la ligne manuelle, que
    # l'upsert déplacera à la bonne date.
    gp = _gp("GP Singapour", "p5", datetime(2026, 10, 18, 12, 0, tzinfo=UTC))
    decision = choisir_ligne(gp, BASE)

    assert decision.ligne is SINGAPOUR
    assert decision.par == "nom"


def test_le_repli_par_le_nom_ignore_les_lignes_reelles():
    # Une ligne réelle de même nom n'est pas un candidat du repli : rien à
    # adopter, et rien d'ambigu non plus.
    gp = _gp("GP Azerbaïdjan", "p6", None)
    decision = choisir_ligne(gp, BASE)
    assert (decision.ligne, decision.refus) == (None, None)


def test_deux_lignes_manuelles_de_meme_nom_ne_font_rien_adopter():
    gp = _gp("GP Malaisie", "p7", None)
    jumelle = {**MALAISIE, "id": "jumelle", "id_unibet": "manuel-malaisie-bis"}
    decision = choisir_ligne(gp, [MALAISIE, jumelle])

    assert decision.ligne is None
    assert "2 lignes manuelles" in decision.refus


# --  _enregistrer : ce qui est écrit en base  ----------------------------------


class BaseSimulee:
    def __init__(self, lignes):
        self.lignes = [dict(ligne) for ligne in lignes]
        self.mises_a_jour = []
        self.upserts = []
        self.suppressions = []

    async def selectionner(self, table, parametres):
        assert table == "grands_prix"
        if "id_unibet" in parametres:
            cible = parametres["id_unibet"].removeprefix("eq.")
            return [l for l in self.lignes if l["id_unibet"] == cible]
        return [dict(l) for l in self.lignes]

    async def mettre_a_jour(self, table, filtres, valeurs):
        self.mises_a_jour.append((table, filtres, valeurs))
        ident = filtres["id"].removeprefix("eq.")
        placeholder = filtres["id_unibet"].removeprefix("eq.")
        touchees = [l for l in self.lignes if l["id"] == ident and l["id_unibet"] == placeholder]
        for ligne in touchees:
            ligne.update(valeurs)
        return [dict(l) for l in touchees]

    async def upserter(self, table, lignes, sur_conflit):
        self.upserts.append((table, lignes, sur_conflit))
        if table != "grands_prix":
            return lignes
        [ligne] = lignes
        existante = next((l for l in self.lignes if l["id_unibet"] == ligne["id_unibet"]), None)
        if existante is None:
            existante = {"id": "NOUVELLE", "statut": "a_venir", **ligne}
            self.lignes.append(existante)
        else:
            existante.update(ligne)
        return [dict(existante)]

    async def supprimer(self, table, parametres):
        self.suppressions.append((table, parametres))
        return []

    def tables(self):
        return [table for table, _lignes, _conflit in self.upserts]


@pytest.fixture
def base(monkeypatch):
    simulee = BaseSimulee(BASE)
    for nom in ("selectionner", "mettre_a_jour", "upserter", "supprimer"):
        monkeypatch.setattr(unibet, nom, getattr(simulee, nom))
    return simulee


def _bahrein_avec_cotes():
    gp = _gp(BAHREIN.nom, BAHREIN.id_unibet, BAHREIN.date_course)
    gp.cotes = [unibet.Cote("vainqueur", "Vainqueur", "G.Russell", 28, "o1")]
    return gp


def test_bahrein_ecrit_sur_la_ligne_malaisie_sans_en_creer(base):
    rapport = asyncio.run(unibet._enregistrer(_bahrein_avec_cotes()))

    assert rapport["gp_id"] == MALAISIE["id"]
    assert len(base.lignes) == len(BASE)
    assert not any(l["id"] == "NOUVELLE" for l in base.lignes)
    [(_, filtres, valeurs)] = base.mises_a_jour
    assert filtres == {"id": "eq.3118efe3", "id_unibet": "eq.manuel-malaisie-2026"}
    assert valeurs == {"id_unibet": "p59469828"}
    ligne = next(l for l in base.lignes if l["id"] == MALAISIE["id"])
    assert (ligne["nom"], ligne["id_unibet"]) == ("GP Bahrein", "p59469828")
    # L'alerte éventuelle d'un passage précédent est effacée.
    assert base.suppressions == [
        ("alertes_admin", {"type": f"eq.{GRAND_PRIX_AMBIGU}", "cle": "eq.p59469828"})
    ]


def test_le_passage_suivant_retombe_sur_la_meme_ligne(base):
    asyncio.run(unibet._enregistrer(_bahrein_avec_cotes()))
    rapport = asyncio.run(unibet._enregistrer(_bahrein_avec_cotes()))

    assert rapport["gp_id"] == MALAISIE["id"]
    assert len(base.mises_a_jour) == 1
    assert len(base.lignes) == len(BASE)


def test_un_cas_ambigu_ne_cree_rien_et_remonte_une_alerte(base):
    base.lignes.append({**MALAISIE, "id": "x", "nom": "GP Autre", "id_unibet": "manuel-autre-2026"})
    avant = len(base.lignes)

    with pytest.raises(ErreurScraper, match="2 lignes occupent ce week-end"):
        asyncio.run(unibet._enregistrer(_bahrein_avec_cotes()))

    assert base.tables() == ["alertes_admin"]
    assert base.mises_a_jour == []
    [(_, [alerte], conflit)] = base.upserts
    assert conflit == "gp_id,type,cle"
    assert (alerte["gp_id"], alerte["type"], alerte["cle"], alerte["libelle"]) == (
        None, GRAND_PRIX_AMBIGU, "p59469828", "GP Bahrein",
    )
    assert len(base.lignes) == avant


def test_un_grand_prix_nouveau_est_cree_comme_avant(base):
    gp = _gp("GP Thaïlande", "p8", datetime(2027, 3, 14, 8, 0, tzinfo=UTC))
    gp.cotes = [unibet.Cote("vainqueur", "Vainqueur", "G.Russell", 28, "o1")]

    rapport = asyncio.run(unibet._enregistrer(gp))

    assert rapport["gp_id"] == "NOUVELLE"
    assert rapport["fige"] is False
    assert base.mises_a_jour == []
    assert base.tables() == ["grands_prix", "cotes"]
    assert len(base.lignes) == len(BASE) + 1


def test_un_doublon_deja_forme_continue_et_donne_la_commande(base):
    base.lignes.append({**MALAISIE, "id": "16a9c686", "nom": "GP Bahrein", "id_unibet": "p59469828"})

    rapport = asyncio.run(unibet._enregistrer(_bahrein_avec_cotes()))

    assert rapport["gp_id"] == "16a9c686"
    assert base.mises_a_jour == []
    alerte = next(lignes[0] for table, lignes, _ in base.upserts if table == "alertes_admin")
    assert alerte["gp_id"] == "16a9c686"
    assert "adopter_grand_prix('manuel-malaisie-2026', 'p59469828')" in alerte["derniere_erreur"]


# --  GET /admin/alertes : une alerte sans Grand Prix  ---------------------------


def test_une_alerte_sans_gp_est_servie_sous_le_nom_d_unibet(monkeypatch):
    async def selectionner(_table, _parametres):
        return [{"type": GRAND_PRIX_AMBIGU, "gp_id": None, "marche": None,
                 "libelle": "GP Inconnu", "tentatives": 1, "derniere_erreur": "aucune ligne",
                 "modifie_le": None, "grands_prix": None}]

    monkeypatch.setattr(admin, "selectionner", selectionner)
    app.dependency_overrides[exiger_admin] = lambda: "admin"
    try:
        [alerte] = TestClient(app).get("/admin/alertes").json()["alertes"]
    finally:
        app.dependency_overrides.clear()

    assert (alerte["type"], alerte["gp_id"], alerte["gp"]) == (GRAND_PRIX_AMBIGU, None, "GP Inconnu")
