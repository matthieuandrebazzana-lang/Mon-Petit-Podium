-- =============================================================================
-- Migration 28 — suppression de compte (conformité App Store 5.1.1(v))
-- =============================================================================
--
-- À exécuter dans le SQL Editor de Supabase, APRÈS les migrations 2, 4, 5 et 7
-- (`championnats`, `createur_nullable_championnat_vide`, `favoris_pronostics`,
-- `classement_championnat`) : elle lit `public.championnats`,
-- `public.membres_championnat`, `public.pronostics`, `public.favoris` et appelle
-- `public.classement_du_championnat`.
--
-- Une seule fonction, `public.supprimer_mon_compte(p_profil uuid)`, appelée par
-- `DELETE /profils/moi` (`backend/app/api/routes/profils.py`) AVANT que le
-- backend supprime la photo de Storage puis le compte Supabase Auth :
--
--   1. pour chaque championnat créé par le compte, la propriété passe au
--      membre le mieux classé (règle 4.6, via `classement_du_championnat` — un
--      seul propriétaire pour l'ordre de départage, jamais reprogrammé ici) ;
--      s'il n'y a personne d'autre, rien n'est écrit : le championnat
--      disparaît de lui-même à l'étape 3, par le trigger
--      `membres_championnat_supprime_vide` de la migration 4 ;
--   2. les pronostics et les favoris du compte sont effacés
--      (`pronostic_podium` suit par cascade) ;
--   3. ses adhésions sont effacées, ce qui déclenche le trigger ci-dessus sur
--      tout championnat qu'il quitte en dernier.
--
-- **Pourquoi une fonction plutôt que la cascade `auth.users` seule.** Supprimer
-- directement le compte Supabase Auth cascaderait déjà `public.profils`
-- (1-1), `membres_championnat` et `pronostics` (`on delete cascade`,
-- `docs/database.md` §1) — mais laisserait `championnats.cree_par` retomber à
-- NULL (migration 4), jamais transférer à un autre membre. C'est la seule
-- pièce que la cascade ne sait pas faire, et donc la seule que cette fonction
-- ajoute : le reste n'est écrit qu'en clair, pour que la route obtienne un état
-- prévisible avant d'appeler l'API d'administration Auth.
--
-- Idempotente : `create or replace function`, rejouable sans effet si aucun
-- compte n'est en cours de suppression.
-- =============================================================================

create or replace function public.supprimer_mon_compte(p_profil uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  championnat            record;
  nouveau_proprietaire   uuid;
begin
  -- --  1. Transfert ou extinction des championnats créés par le compte  ------
  for championnat in
    select id from public.championnats where cree_par = p_profil
  loop
    -- Le classement fait déjà foi (règle 4.6) : on y pioche le premier membre
    -- qui n'est pas le compte qu'on supprime, dans l'ordre où la fonction le
    -- range déjà. `jsonb_array_elements` plutôt qu'une requête SQL réécrite :
    -- reprogrammer les quatre critères de départage ici les ferait diverger de
    -- l'écran de classement au premier ajustement de l'un des deux.
    select (element ->> 'profil_id')::uuid
    into nouveau_proprietaire
    from jsonb_array_elements(
      public.classement_du_championnat(championnat.id)
    ) as element
    where (element ->> 'profil_id')::uuid <> p_profil
    order by (element ->> 'rang')::int asc
    limit 1;

    if nouveau_proprietaire is not null then
      update public.championnats
      set cree_par = nouveau_proprietaire
      where id = championnat.id;
    end if;
    -- Sinon : personne d'autre. Rien à écrire ici — le championnat s'éteint à
    -- l'étape 3, quand la dernière adhésion (la sienne) disparaît.

    nouveau_proprietaire := null;
  end loop;

  -- --  2. Pronostics et favoris  ----------------------------------------------
  -- `pronostic_podium` suit par cascade sur `pronostics` (clé étrangère,
  -- migration 5). Même geste que `quitter_championnat` (migration 5).
  delete from public.pronostics where profil_id = p_profil;
  delete from public.favoris    where profil_id = p_profil;

  -- --  3. Adhésions — déclenche le nettoyage des championnats devenus vides --
  delete from public.membres_championnat where profil_id = p_profil;
end;
$$;

comment on function public.supprimer_mon_compte(uuid) is
  'Transfère ou éteint les championnats créés par le compte (règle 4.6), efface ses pronostics, favoris et adhésions. Réservée au backend — appelée par DELETE /profils/moi AVANT la suppression du compte Supabase Auth.';

revoke all on function public.supprimer_mon_compte(uuid) from public;
revoke all on function public.supprimer_mon_compte(uuid) from anon;
revoke all on function public.supprimer_mon_compte(uuid) from authenticated;
grant execute on function public.supprimer_mon_compte(uuid) to service_role;
