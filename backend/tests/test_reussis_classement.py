"""« Réussis » du classement : la même unité que « Mes Grands Prix » (migration 32).

Le classement comptait une ligne de `pronostics` par réussite — un podium y valait
1 —, l'écran iOS « Mes Grands Prix » une ligne d'affichage — un podium détaillé en
vaut deux, une par pilote (`PronosticMembre.paris`). La règle vit désormais dans
une seule fonction SQL, `reussites_du_pronostic`, que lit le classement.

Aucun PostgreSQL ici : ces tests gardent la migration et son ordre. La migration
s'éprouve elle-même à l'exécution (bloc `do $$` final).
"""

import re
from pathlib import Path

MIGRATIONS = Path(__file__).resolve().parents[2] / "supabase" / "migrations"
MIGRATION_32 = MIGRATIONS / "20261027120000_reussis_par_pilote.sql"


def _definitions(fonction: str) -> list[tuple[str, str]]:
    """(fichier, corps) de chaque `create or replace function public.<fonction>`,
    dans l'ordre d'application des migrations."""
    motif = re.compile(
        rf"create or replace function public\.{fonction}\(.*?\n\$\$;", re.S | re.I
    )
    trouvees = []
    for fichier in sorted(MIGRATIONS.glob("*.sql")):
        for corps in motif.findall(fichier.read_text(encoding="utf-8")):
            trouvees.append((fichier.name, corps))
    return trouvees


def test_la_derniere_version_du_classement_lit_la_regle_unique():
    # Une migration future qui recopierait un ancien corps du classement
    # rétablirait le compteur par ligne : ce test le verrait.
    fichier, corps = _definitions("classement_du_championnat")[-1]
    assert "reussites_du_pronostic(" in corps, fichier
    assert "count(*) filter (where pr.points_gagnes > 0)" not in corps


def test_la_jointure_au_podium_est_un_a_un_et_les_points_ne_bougent_pas():
    _, corps = _definitions("classement_du_championnat")[-1]
    assert "left join public.pronostic_podium pp on pp.pronostic_id = pr.id" in corps
    # Total et meilleur coup calculés comme avant, sur la ligne parente seule.
    assert "sum(pr.points_gagnes)" in corps
    assert "max(pr.points_gagnes) filter (where pr.points_gagnes > 0)" in corps


def test_la_regle_suit_la_decoupe_du_podium_de_l_app():
    _, corps = _definitions("reussites_du_pronostic")[-1]
    assert "when p_points_gagnes is null then 0" in corps
    assert "when p_gagnes_1 is null or p_gagnes_2 is null" in corps
    assert "(p_gagnes_1 > 0)::integer + (p_gagnes_2 > 0)::integer" in corps


def test_l_epreuve_couvre_le_podium_double_et_le_podium_sans_detail():
    sql = MIGRATION_32.read_text(encoding="utf-8")
    assert "(54,        24,        30,        2)" in sql  # deux bons pilotes
    assert "(54,        null,      null,      1)" in sql  # jugé sans détail
    assert "(null,      10,        20,        0)" in sql  # pas encore jugé


def test_la_regle_est_reservee_au_service():
    sql = MIGRATION_32.read_text(encoding="utf-8")
    for role in ("public", "anon", "authenticated"):
        assert (
            f"revoke all on function public.reussites_du_pronostic(integer, integer, integer) from {role};"
            in sql
        )
