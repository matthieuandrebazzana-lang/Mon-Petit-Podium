-- =============================================================================
-- Championnat « Démo F1 » — 99 · SUPPRESSION COMPLÈTE
-- =============================================================================
--
-- Retire tout ce que les étapes 01, 03 et 04 ont créé, et rien d'autre :
--   · le championnat « Démo F1 » (ses adhésions suivent par cascade — celle du
--     reviewer comprise, et celle de tout vrai compte qui l'aurait rejoint par
--     son code : ce compte perd l'adhésion, garde ses pronostics) ;
--   · les 8 comptes démo `auth.users` — profils, pronostics, podiums, favoris
--     et jetons suivent par cascade (toutes ces clés sont `on delete cascade`).
--
-- Les comptes sont désignés par les DEUX marques à la fois, jamais une seule :
-- `raw_app_meta_data.demo = true` ET une adresse `demo-…@greedf1.invalid`.
-- Aucun vrai compte ne peut porter l'une ni l'autre : `app_metadata` ne
-- s'écrit qu'avec la clé de service, et `.invalid` ne reçoit aucun e-mail de
-- confirmation.
--
-- Le reviewer n'est PAS supprimé : il n'a été qu'ajouté comme membre.
--
-- Exécuter `00_controles.sql` §1 avant et après : l'empreinte des données
-- réelles ne doit pas bouger. Idempotent : rejoué, il ne supprime rien.
-- =============================================================================

begin;

do $$
declare
  demo_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into demo_ids
    from auth.users
   where raw_app_meta_data ->> 'demo' = 'true'
     and email like 'demo-%@greedf1.invalid';

  if coalesce(array_length(demo_ids, 1), 0) > 8 then
    raise exception 'Plus de 8 comptes marqués démo (%) : vérifier avant de supprimer.',
      array_length(demo_ids, 1);
  end if;

  -- Un compte démo membre d'un AUTRE championnat : jamais censé arriver, et
  -- sa suppression changerait un vrai classement. On s'arrête.
  if exists (select 1 from public.membres_championnat
              where profil_id = any (demo_ids)
                and championnat_id <> '67dc7eb8-a039-43da-9b2f-d7b782e1b20e') then
    raise exception 'Un compte démo est membre d''un vrai championnat : rien n''est supprimé.';
  end if;

  -- Le championnat ne se supprime que s'il est bien celui de la démo.
  if exists (select 1 from public.championnats
              where id = '67dc7eb8-a039-43da-9b2f-d7b782e1b20e'
                and (nom <> 'Démo F1' or not (cree_par is null or cree_par = any (demo_ids)))) then
    raise exception 'Le championnat % n''est pas celui de la démo : rien n''est supprimé.',
      '67dc7eb8-a039-43da-9b2f-d7b782e1b20e';
  end if;
end $$;

-- Les vrais comptes qui auraient rejoint par le code, pour mémoire.
select p.pseudo as vrai_membre_retire, m.rejoint_le
  from public.membres_championnat m
  join public.profils p on p.id = m.profil_id
 where m.championnat_id = '67dc7eb8-a039-43da-9b2f-d7b782e1b20e'
   and m.profil_id not in (select id from auth.users
                            where raw_app_meta_data ->> 'demo' = 'true'
                              and email like 'demo-%@greedf1.invalid');

delete from public.championnats
 where id = '67dc7eb8-a039-43da-9b2f-d7b782e1b20e';

delete from auth.users
 where raw_app_meta_data ->> 'demo' = 'true'
   and email like 'demo-%@greedf1.invalid';

-- Contrôle : plus aucune trace. Lève, et annule tout, sinon.
do $$
begin
  if exists (select 1 from auth.users where email like 'demo-%@greedf1.invalid')
     or exists (select 1 from public.profils
                 where id not in (select id from auth.users))
     or exists (select 1 from public.championnats
                 where id = '67dc7eb8-a039-43da-9b2f-d7b782e1b20e')
     or exists (select 1 from public.membres_championnat
                 where championnat_id = '67dc7eb8-a039-43da-9b2f-d7b782e1b20e')
     or exists (select 1 from public.pronostics
                 where profil_id not in (select id from auth.users)) then
    raise exception 'Il reste des traces de la démo : suppression annulée.';
  end if;
end $$;

commit;

-- Contrôle lisible : tout doit valoir 0.
select
  (select count(*) from auth.users where email like 'demo-%@greedf1.invalid') as comptes_demo,
  (select count(*) from public.championnats
    where id = '67dc7eb8-a039-43da-9b2f-d7b782e1b20e') as championnat_demo,
  (select count(*) from public.membres_championnat
    where championnat_id = '67dc7eb8-a039-43da-9b2f-d7b782e1b20e') as adhesions_demo;
