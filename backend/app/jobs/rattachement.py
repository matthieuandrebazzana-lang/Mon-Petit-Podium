"""Rattachement des issues aux engagés, au figeage des cotes (migration 26).

`docs/audit-evaluation.md` §5.1. Le figeage (qualifications + 2 h) est aussi
l'ouverture des pronostics : c'est le moment où un libellé Unibet non reconnu
doit se voir, pas le soir de la course. OpenF1 connaît alors les engagés du GP
par sa session de qualification (`openf1.engages`) ; chaque issue pilote ou
écurie reçoit son numéro ou son identifiant d'écurie (`points.correspondance`).

**Rien ici ne bloque le figeage.** Il a déjà eu lieu quand `rattacher` est
appelé, et un échec — OpenF1 muette, base non migrée — laisse les cotes sans
identifiant : le calcul retombe sur le libellé, comme avant. Ce qui manque est
journalisé et remonte au profil admin (`alertes_admin`).
"""

import logging
from datetime import UTC, datetime

from app.calcul import points as calcul
from app.scraper.openf1 import ErreurOpenF1, engages
from app.supabase_client import ErreurSupabase, appeler_fonction, selectionner, upserter

logger = logging.getLogger("uvicorn.error")

RATTACHEMENT_IMPOSSIBLE = "rattachement_impossible"


def _en_datetime(brut: object) -> datetime | None:
    if not isinstance(brut, str) or not brut.strip():
        return None
    try:
        lue = datetime.fromisoformat(brut.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return lue.replace(tzinfo=UTC) if lue.tzinfo is None else lue.astimezone(UTC)


async def rattacher(gp_id: str) -> dict:
    """Rattache les issues d'un GP à ses engagés. Lève en cas d'échec.

    Rejouable : un second passage remplace les identifiants et les alertes de
    libellé du premier (`rattacher_issues`).
    """
    lignes = await selectionner(
        "grands_prix",
        {"id": f"eq.{gp_id}", "select": "id,nom,date_course,date_qualifications", "limit": "1"},
    )
    if not lignes:
        raise ValueError("Ce Grand Prix n'existe pas.")
    gp = lignes[0]
    nom = str(gp.get("nom") or gp_id)

    reference = _en_datetime(gp.get("date_qualifications")) or _en_datetime(
        gp.get("date_course")
    )
    if reference is None:
        raise ErreurOpenF1(f"{nom} : ni heure de qualifications ni heure de départ.")

    index = await engages(nom, reference)
    cotes = await selectionner(
        "cotes",
        {"gp_id": f"eq.{gp_id}", "select": "id_outcome_unibet,marche,pilote"},
    )
    resultat = calcul.correspondance(cotes, index)

    ecrit = await appeler_fonction(
        "rattacher_issues",
        {
            "p_gp": gp_id,
            "p_rattachements": resultat.rattachements,
            "p_non_reconnus": resultat.non_reconnus,
        },
    )

    if resultat.non_reconnus:
        logger.warning(
            "[rattachement] %s : %d issue(s) ne désignent aucun engagé : %s",
            nom,
            len(resultat.non_reconnus),
            " ; ".join(
                f"« {issue['libelle']} » [{issue['marche']}]"
                for issue in resultat.non_reconnus
            ),
        )
    logger.info(
        "[rattachement] %s : %d issue(s) rattachée(s), %d non reconnue(s), "
        "%d engagé(s).",
        nom,
        len(resultat.rattachements),
        len(resultat.non_reconnus),
        len(index),
    )

    return {
        "gp": nom,
        "gp_id": gp_id,
        "engages": len(index),
        "rattachees": (ecrit or {}).get("rattachees", len(resultat.rattachements)),
        "non_reconnues": resultat.non_reconnus,
    }


async def rattacher_sans_echec(gp_id: str, nom: str) -> None:
    """`rattacher`, appelé juste après le figeage : ne laisse rien s'échapper.

    Un échec est journalisé et devient une alerte `rattachement_impossible` —
    elle-même best effort : sans la migration 26, seul le journal en garde trace.
    """
    try:
        await rattacher(gp_id)
        return
    except (ErreurOpenF1, ErreurSupabase, ValueError) as erreur:
        message = str(erreur) or type(erreur).__name__
    except Exception as erreur:  # noqa: BLE001 — le figeage a déjà eu lieu
        message = f"{type(erreur).__name__}: {erreur}"

    logger.error(
        "[rattachement] %s : issues non rattachées (%s). Le calcul se fera sur les "
        "libellés. Rejouer : POST /scraper/rattacher/%s",
        nom,
        message,
        gp_id,
    )
    try:
        await upserter(
            "alertes_admin",
            [
                {
                    "gp_id": gp_id,
                    "type": RATTACHEMENT_IMPOSSIBLE,
                    "cle": "",
                    "derniere_erreur": message[:1000],
                    "modifie_le": datetime.now(UTC).isoformat(),
                }
            ],
            "gp_id,type,cle",
        )
    except ErreurSupabase:
        logger.exception("[rattachement] %s : alerte admin non enregistrée.", nom)
