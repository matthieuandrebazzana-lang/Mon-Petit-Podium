"""Championnat « Démo F1 » — génère l'étape 03 : pronostics des GP terminés.

Captures de la fiche App Store uniquement. Procédure : `docs/contexte-chat.md`,
section « CHAMPIONNAT DÉMO ».

    cd backend
    .venv/bin/python scripts/demo_pronostics.py ~/Downloads/<export>.csv \\
        > ../supabase/demo/03_pronostics_gp_termines.sql

Entrée : l'export CSV de `supabase/demo/02_export_gp_termines.sql`.
Sortie : un script SQL idempotent, sur la sortie standard. Rapport sur stderr.

**Aucun point n'est choisi ici.** Le script choisit des PRONOSTICS — vainqueur,
podium, bonus, pris dans les cotes réelles du GP — et c'est
`app.calcul.points.calculer`, la fonction même du job de résultats, qui les
juge sur les `donnees_brutes` conservées. Le SQL produit n'écrit les verdicts
que par `public.attribuer_points`, comme le job : `points_gagnes` d'abord, le
statut dérivé par le trigger, les gains par pilote du podium en plus.

Le choix vise un étalement plausible : le premier vers 300 points, le dernier
membre démo près de zéro, aucune égalité, et trois membres à zéro sur le
dernier GP couru (la piste). Des favoris le plus souvent, un outsider de temps
en temps : chaque issue est tirée avec un poids inverse à sa cote. Le tirage est
déterministe (graine fixe) : relancé sur le même export, le script rend le même
SQL. S'il ne trouve aucun étalement qui tienne, il le dit et n'écrit rien.
"""

from __future__ import annotations

import csv
import json
import logging
import random
import sys
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.calcul import points as calcul  # noqa: E402

CHAMPIONNAT = "67dc7eb8-a039-43da-9b2f-d7b782e1b20e"

# Identifiants de pronostic stables d'une génération à l'autre : l'étape 03
# rejouée retombe sur les mêmes lignes (`on conflict (id) do nothing`).
ESPACE = uuid.UUID("5b0f8e2a-6c1d-4f7e-9a3b-2d4c6e8f0a1b")

# Total visé par membre, du premier au dernier. Une cible, pas un résultat :
# les points viennent du calcul, le tirage ne fait que s'en approcher.
CIBLES = {
    "Maya": 302,
    "Hugo": 268,
    "Alex": 236,
    "Lina": 197,
    "Noah": 158,
    "Zoe": 117,
    "Leo": 66,
    "Eva": 18,
}
TOLERANCE = 0.12

# Membres qui ratent tout au dernier GP couru : zéro sur la piste.
ZERO_AU_DERNIER = ("Noah", "Leo", "Eva")

# Bornes de plausibilité de l'ensemble.
PREMIER_MIN, PREMIER_MAX = 270, 330
DERNIER_MIN, DERNIER_MAX = 1, 45
ECART_MIN = 4  # entre deux totaux voisins : pas d'égalité, pas de quasi-égalité

TIRAGES_PAR_GP = 4000
ESSAIS = 400

VAINQUEURS_RETENUS = 8
PODIUMS_RETENUS = 10
BONUS_COTE_MAX = 120


def lire_export(chemin: Path) -> tuple[dict[str, str], list[dict]]:
    csv.field_size_limit(sys.maxsize)
    membres: dict[str, str] = {}
    gps: list[dict] = []
    with chemin.open(newline="", encoding="utf-8") as fichier:
        for ligne in csv.DictReader(fichier):
            contenu = json.loads(ligne["contenu"])
            if ligne["nature"] == "membres":
                membres = {m["pseudo"]: m["id"] for m in contenu}
            elif ligne["nature"] == "gp":
                gps.append(contenu)
    gps.sort(key=lambda gp: gp["date_course"])
    return membres, gps


def _id(*parties: str) -> str:
    return str(uuid.uuid5(ESPACE, ":".join(parties)))


def candidats_du_gp(gp: dict) -> dict:
    """Toutes les issues jouables du GP, chacune déjà jugée par `calculer`.

    Une issue que le calcul ne sait pas juger (en attente, non évaluable) est
    écartée : un pronostic démo doit finir `gagne` ou `perdu`, jamais affiché
    « en attente » sur une capture.
    """
    cotes = {c["id_outcome_unibet"]: c for c in gp["cotes"]}

    def tri(marche: str, nombre: int) -> list[dict]:
        return sorted(
            (c for c in cotes.values() if c["marche"] == marche), key=lambda c: c["valeur"]
        )[:nombre]

    vainqueurs = tri(calcul.MARCHE_VAINQUEUR, VAINQUEURS_RETENUS)
    podiums = tri(calcul.MARCHE_PODIUM, PODIUMS_RETENUS)
    bonus = [
        c
        for c in cotes.values()
        if c["marche"] not in (calcul.MARCHE_VAINQUEUR, calcul.MARCHE_PODIUM)
        and c["valeur"] <= BONUS_COTE_MAX
    ]

    essais = [
        {"id": f"v|{c['id_outcome_unibet']}", "type": "vainqueur",
         "id_outcome_unibet": c["id_outcome_unibet"]}
        for c in vainqueurs
    ] + [
        {"id": f"b|{c['id_outcome_unibet']}", "type": "bonus",
         "id_outcome_unibet": c["id_outcome_unibet"]}
        for c in bonus
    ]
    for i, a in enumerate(podiums):
        for b in podiums[i + 1:]:
            essais.append({
                "id": f"p|{a['id_outcome_unibet']}|{b['id_outcome_unibet']}",
                "type": "podium",
                "id_outcome_unibet": a["id_outcome_unibet"],
                "pronostic_podium": {"pilote_1": a["id_outcome_unibet"],
                                     "pilote_2": b["id_outcome_unibet"]},
            })

    attributions, _ = calcul.calculer(essais, cotes, gp["donnees"])
    juges = {
        a.pronostic_id: a
        for a in attributions
        if a.points is not None and a.statut in (calcul.GAGNE, calcul.PERDU)
    }

    return {
        "cotes": cotes,
        "vainqueurs": [c for c in vainqueurs if f"v|{c['id_outcome_unibet']}" in juges],
        "podiums": podiums,
        "bonus": [c for c in bonus if f"b|{c['id_outcome_unibet']}" in juges],
        "juges": juges,
    }


def _tirer(rng: random.Random, issues: list[dict], exclus: set[str]) -> dict | None:
    restantes = [c for c in issues if c["id_outcome_unibet"] not in exclus]
    if not restantes:
        return None
    return rng.choices(restantes, weights=[1 / c["valeur"] for c in restantes])[0]


def tirer_jeu(rng: random.Random, cand: dict) -> dict | None:
    """Un jeu complet et valide : vainqueur, podium à deux, zéro à trois bonus."""
    juges = cand["juges"]
    vainqueur = _tirer(rng, cand["vainqueurs"], set())
    if vainqueur is None:
        return None
    nom_vainqueur = calcul.normaliser(vainqueur["pilote"])

    # Exclusion croisée sur le LIBELLÉ (`metier.md` §2) : le vainqueur ne
    # figure pas au podium.
    podium_possible = [
        c for c in cand["podiums"] if calcul.normaliser(c["pilote"]) != nom_vainqueur
    ]
    a = _tirer(rng, podium_possible, set())
    b = _tirer(rng, podium_possible, {a["id_outcome_unibet"]} if a else set())
    if a is None or b is None:
        return None
    a, b = sorted((a, b), key=lambda c: c["valeur"])
    cle_podium = f"p|{a['id_outcome_unibet']}|{b['id_outcome_unibet']}"
    if cle_podium not in juges:
        cle_podium = f"p|{b['id_outcome_unibet']}|{a['id_outcome_unibet']}"
    if cle_podium not in juges:
        return None

    # Un bonus par marché au plus : trois paris sur le même marché ne
    # ressemblent pas à un joueur.
    bonus: list[dict] = []
    marches: set[str] = set()
    for _ in range(rng.choices((0, 1, 2, 3), weights=(1, 3, 4, 5))[0]):
        possibles = [c for c in cand["bonus"] if c["marche"] not in marches]
        choisi = _tirer(rng, possibles, set())
        if choisi is None:
            break
        bonus.append(choisi)
        marches.add(choisi["marche"])

    cles = [f"v|{vainqueur['id_outcome_unibet']}", cle_podium] + [
        f"b|{c['id_outcome_unibet']}" for c in bonus
    ]
    return {
        "vainqueur": vainqueur,
        "podium": cle_podium.split("|")[1:],
        "bonus": bonus,
        "points": sum(juges[c].points for c in cles),
    }


def generer(candidats: list[dict], graine: int) -> dict | None:
    rng = random.Random(graine)
    dernier = len(candidats) - 1
    jeux: dict[str, list[dict]] = {}
    totaux: dict[str, int] = {}

    for pseudo, cible in CIBLES.items():
        total = 0
        jeux[pseudo] = []
        zero = pseudo in ZERO_AU_DERNIER
        for i, cand in enumerate(candidats):
            if zero and i == dernier:
                vise, exact = 0, True
            else:
                restants = (dernier if zero else dernier + 1) - i
                vise = max(0, (cible - total) / max(restants, 1))
                vise *= rng.uniform(0.6, 1.4) if restants > 1 else 1
                exact = False

            meilleur, ecart = None, None
            for _ in range(TIRAGES_PAR_GP):
                jeu = tirer_jeu(rng, cand)
                if jeu is None:
                    continue
                d = abs(jeu["points"] - vise)
                if exact and d != 0:
                    continue
                if ecart is None or d < ecart:
                    meilleur, ecart = jeu, d
                    if d == 0:
                        break
            if meilleur is None:
                return None
            jeux[pseudo].append(meilleur)
            total += meilleur["points"]
        totaux[pseudo] = total

    valeurs = sorted(totaux.values(), reverse=True)
    ordre = sorted(totaux, key=totaux.get, reverse=True)
    if not (PREMIER_MIN <= valeurs[0] <= PREMIER_MAX):
        return None
    if not (DERNIER_MIN <= valeurs[-1] <= DERNIER_MAX):
        return None
    if any(a - b < ECART_MIN for a, b in zip(valeurs, valeurs[1:])):
        return None
    if ordre != list(CIBLES):
        return None
    if any(abs(totaux[p] - c) > c * TOLERANCE + 8 for p, c in CIBLES.items()):
        return None
    return {"jeux": jeux, "totaux": totaux, "candidats": candidats}


def _sql_texte(valeur: str) -> str:
    return "'" + valeur.replace("'", "''") + "'"


def ecrire_sql(membres: dict[str, str], gps: list[dict], resultat: dict, graine: int) -> str:
    jeux, totaux, candidats = resultat["jeux"], resultat["totaux"], resultat["candidats"]
    lignes_pronos: list[str] = []
    lignes_podiums: list[str] = []
    verdicts: dict[str, list[dict]] = {gp["id"]: [] for gp in gps}

    for pseudo, liste in jeux.items():
        profil = membres[pseudo]
        for gp, cand, jeu in zip(gps, candidats, liste):
            depart = datetime.fromisoformat(gp["date_course"].replace("Z", "+00:00"))
            # Saisis la veille au soir : avant la fermeture, après le figeage.
            saisi = (depart - timedelta(hours=18, minutes=7 * list(CIBLES).index(pseudo))).astimezone(UTC)
            horodatage = _sql_texte(saisi.isoformat())

            def ajouter(type_: str, outcome: str, cle: str, podium=None):
                ident = _id("demo", profil, gp["id"], type_, outcome)
                lignes_pronos.append(
                    f"  ({_sql_texte(ident)}, {_sql_texte(profil)}, {_sql_texte(gp['id'])}, "
                    f"{_sql_texte(outcome)}, {_sql_texte(type_)}, {horodatage}, {horodatage})"
                )
                if podium:
                    lignes_podiums.append(
                        f"  ({_sql_texte(ident)}, {_sql_texte(podium[0])}, {_sql_texte(podium[1])})"
                    )
                a = cand["juges"][cle]
                entree = {"pronostic_id": ident, "points": a.points, "statut": a.statut}
                if a.podium is not None:
                    entree["podium"] = list(a.podium)
                verdicts[gp["id"]].append(entree)

            v = jeu["vainqueur"]["id_outcome_unibet"]
            ajouter("vainqueur", v, f"v|{v}")
            p1, p2 = jeu["podium"]
            ajouter("podium", p1, f"p|{p1}|{p2}", (p1, p2))
            for b in jeu["bonus"]:
                ajouter("bonus", b["id_outcome_unibet"], f"b|{b['id_outcome_unibet']}")

    gardes = "\n".join(
        f"  perform 1 from public.grands_prix g\n"
        f"    join public.resultats_gp r on r.gp_id = g.id\n"
        f"   where g.id = {_sql_texte(gp['id'])} and g.statut = 'termine'\n"
        f"     and md5(r.donnees_brutes::text) = {_sql_texte(gp['empreinte_donnees'])}\n"
        f"     and (select md5(string_agg(c.id_outcome_unibet || ':' || c.marche || ':'\n"
        f"                                || c.pilote || ':' || c.valeur || ':'\n"
        f"                                || coalesce(c.numero_pilote::text, '') || ':'\n"
        f"                                || coalesce(c.ecurie_id, ''),\n"
        f"                                ',' order by c.id_outcome_unibet))\n"
        f"            from public.cotes c where c.gp_id = g.id) = {_sql_texte(gp['empreinte_cotes'])};\n"
        f"  if not found then\n"
        f"    raise exception '{gp['nom'].replace(chr(39), chr(39) * 2)} : cotes ou résultats modifiés "
        f"depuis l''export. Réexporter (02) et régénérer.';\n"
        f"  end if;"
        for gp in gps
    )
    ids_membres = ", ".join(_sql_texte(i) + "::uuid" for i in membres.values())
    appels = "\n".join(
        f"-- {gp['nom']}\n"
        f"select public.attribuer_points({_sql_texte(gp['id'])},\n"
        f"  {_sql_texte(json.dumps(verdicts[gp['id']], ensure_ascii=False))}::jsonb);"
        for gp in gps
    )
    attendus = ",\n".join(
        f"    ({_sql_texte(membres[p])}::uuid, {t})" for p, t in totaux.items()
    )
    total_pronos = len(lignes_pronos)

    return f"""-- =============================================================================
-- Championnat « Démo F1 » — 03 · PRONOSTICS DES GRANDS PRIX TERMINÉS
-- =============================================================================
--
-- GÉNÉRÉ par `backend/scripts/demo_pronostics.py` (graine {graine}) le
-- {datetime.now(UTC).strftime('%Y-%m-%d %H:%M UTC')}. Ne pas modifier à la main, ne pas versionner.
--
-- {total_pronos} pronostics pour 8 membres démo sur {len(gps)} GP :
-- {", ".join(gp['nom'] for gp in gps)}.
--
-- Les verdicts ci-dessous sont ceux rendus par `app.calcul.points.calculer`
-- sur les `donnees_brutes` et les cotes de l'export ; ils ne sont écrits que
-- par `public.attribuer_points`, qui ne touche QUE les identifiants reçus et
-- encore à NULL. Un garde-fou par GP refuse tout si les cotes ou les résultats
-- ont changé depuis l'export.
--
-- Idempotent : rejoué, il n'insère rien et n'attribue rien.
-- Exécuter `00_controles.sql` §1 avant et après : l'empreinte des données
-- réelles ne doit pas bouger.
-- =============================================================================

begin;

do $$
begin
  if (select count(*) from auth.users
       where id in ({ids_membres})
         and raw_app_meta_data ->> 'demo' = 'true'
         and email like 'demo-%@greedf1.invalid') <> 8 then
    raise exception 'Les 8 comptes démo de l''export ne sont plus tous là : rejouer 01, puis 02.';
  end if;
{gardes}
end $$;

insert into public.pronostics
  (id, profil_id, gp_id, id_outcome_unibet, type, cree_le, modifie_le)
values
{",\n".join(lignes_pronos)}
on conflict (id) do nothing;

insert into public.pronostic_podium (pronostic_id, pilote_1, pilote_2)
values
{",\n".join(lignes_podiums)}
on conflict (pronostic_id) do nothing;

{appels}

-- Contrôle final : chaque pronostic démo est jugé, et le classement servi par
-- `classement_du_championnat` porte exactement les totaux du calcul.
do $$
declare
  ecart record;
begin
  if exists (select 1 from public.pronostics p
              join public.grands_prix g on g.id = p.gp_id
             where g.statut = 'termine'
               and p.profil_id in ({ids_membres})
               and p.points_gagnes is null) then
    raise exception 'Un pronostic démo d''un GP terminé est resté sans points.';
  end if;

  for ecart in
    select a.profil_id, a.total as attendu, (l ->> 'total_points')::int as obtenu
      from (values
{attendus}
      ) a (profil_id, total)
      left join jsonb_array_elements(
        public.classement_du_championnat('{CHAMPIONNAT}')) l
        on (l ->> 'profil_id')::uuid = a.profil_id
     where (l ->> 'total_points')::int is distinct from a.total
  loop
    raise exception 'Total inattendu pour % : % au lieu de %.',
      ecart.profil_id, ecart.obtenu, ecart.attendu;
  end loop;
end $$;

commit;
"""


def main() -> int:
    # `calculer` journalise chaque appel : le rapport utile est le nôtre.
    logging.getLogger("uvicorn.error").setLevel(logging.ERROR)
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    membres, gps = lire_export(Path(sys.argv[1]).expanduser())

    manquants = set(CIBLES) - set(membres)
    if manquants:
        print(f"Membres démo absents de l'export : {sorted(manquants)}. Jouer 01.", file=sys.stderr)
        return 1
    if len(gps) < 3:
        print(
            f"Seulement {len(gps)} GP terminés avec cotes et résultats : trop peu pour un "
            "classement plausible autour de 300 points.",
            file=sys.stderr,
        )
        return 1

    # Chaque issue n'est jugée qu'une fois : le tirage ne fait ensuite que
    # sommer des verdicts déjà rendus par `calculer`.
    candidats = [candidats_du_gp(gp) for gp in gps]
    for graine in range(ESSAIS):
        resultat = generer(candidats, graine)
        if resultat is not None:
            break
    else:
        print(
            f"Aucun étalement plausible trouvé en {ESSAIS} essais sur {len(gps)} GP. "
            "Les cotes de ces GP ne permettent pas d'approcher les cibles : "
            "voir CIBLES en tête du script.",
            file=sys.stderr,
        )
        return 1

    print(f"Graine {graine} — {len(gps)} GP : {', '.join(g['nom'] for g in gps)}", file=sys.stderr)
    for pseudo, total in resultat["totaux"].items():
        par_gp = " + ".join(str(j["points"]) for j in resultat["jeux"][pseudo])
        print(f"  {pseudo:<5} {total:>4} pts  ({par_gp})", file=sys.stderr)
    print(ecrire_sql(membres, gps, resultat, graine))
    return 0


if __name__ == "__main__":
    sys.exit(main())
