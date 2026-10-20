-- =============================================================================
-- Championnat « Démo F1 » — 04 · PRONOSTICS DU PROCHAIN GRAND PRIX
-- =============================================================================
--
-- Les 8 membres démo pronostiquent le prochain GP ; le reviewer, rien.
--
-- QUAND : entre le figeage des cotes (samedi, qualifications + 2 h) et le
-- départ de la course. Avant le figeage, le scraper réécrit encore les cotes
-- et une issue retirée par Unibet laisserait un pronostic orphelin ; après le
-- départ, `enregistrer_pronostics` refuse (`PT423`). Le script lève dans les
-- deux cas, sans rien écrire.
--
-- Écrit par `public.enregistrer_pronostics`, le chemin même de la route de
-- saisie : effacement du jeu précédent puis réécriture, contrôle de fermeture
-- en base, trois bonus au plus. Les points restent à NULL : c'est le VRAI job
-- de résultats qui les jugera après la course, avec ceux de tout le monde.
--
-- Idempotent : rejoué avant le départ, il réécrit exactement les mêmes choix
-- (tirage déterministe sur l'identifiant du membre).
--
-- Exécuter `00_controles.sql` §1 avant et après : l'empreinte des données
-- réelles ne doit pas bouger.
-- =============================================================================

begin;

do $$
declare
  gp        record;
  membre    record;
  vainqueur record;
  podium    text[];
  bonus     text[];
  favoris   int;
begin
  select * into gp
    from public.grands_prix
   where statut <> 'termine' and date_course > now()
   order by date_course
   limit 1;

  if gp.id is null then
    raise exception 'Aucun Grand Prix à venir avec une heure de départ.';
  end if;
  if gp.statut <> 'cotes_figees' then
    raise exception 'Le prochain GP (%) n''a pas encore ses cotes figées (statut %) : attendre le figeage du samedi.',
      gp.nom, gp.statut;
  end if;
  if public.pronostics_fermes(gp.id) then
    raise exception 'Les pronostics de % sont fermés.', gp.nom;
  end if;

  -- Les cinq favoris au plus : un GP peu fourni en a moins.
  select least(5, count(*)) into favoris
    from public.cotes where gp_id = gp.id and marche = 'vainqueur';
  if favoris = 0 then
    raise exception 'Aucune cote « vainqueur » sur %.', gp.nom;
  end if;

  for membre in
    select u.id, p.pseudo,
           (row_number() over (order by p.pseudo))::int as rang
      from auth.users u
      join public.profils p on p.id = u.id
     where u.raw_app_meta_data ->> 'demo' = 'true'
       and u.email like 'demo-%@greedf1.invalid'
     order by p.pseudo
  loop
    -- Vainqueur : l'un des cinq favoris, différent selon le membre.
    select c.* into vainqueur
      from public.cotes c
     where c.gp_id = gp.id and c.marche = 'vainqueur'
     order by c.valeur, c.id_outcome_unibet
     offset (membre.rang * 3) % favoris
     limit 1;

    -- Podium : deux pilotes parmi les huit premiers du marché, hors vainqueur.
    -- L'exclusion compare le NOM DE FAMILLE du libellé (« AK.Antonelli » →
    -- « antonelli ») : un même pilote ne s'écrit pas pareil d'un marché à
    -- l'autre (`metier.md` §2).
    select array_agg(id_outcome_unibet) into podium
      from (
        select c.id_outcome_unibet
          from (select c.*, row_number() over (order by c.valeur, c.id_outcome_unibet) as n
                  from public.cotes c
                 where c.gp_id = gp.id and c.marche = 'podium'
                   and regexp_replace(lower(c.pilote), '^.*[.\s]', '')
                       <> regexp_replace(lower(vainqueur.pilote), '^.*[.\s]', '')) c
         where c.n <= 8
         order by md5(membre.id::text || c.id_outcome_unibet)
         limit 2
      ) t;

    -- Bonus : zéro à trois, un par marché au plus, cotes raisonnables.
    select array_agg(id_outcome_unibet) into bonus
      from (
        select id_outcome_unibet
          from (select distinct on (c.marche) c.marche, c.id_outcome_unibet
                  from public.cotes c
                 where c.gp_id = gp.id
                   and c.marche not in ('vainqueur', 'podium')
                   and c.valeur <= 120
                 order by c.marche, md5(membre.id::text || c.id_outcome_unibet)) m
         order by md5(membre.id::text || m.marche)
         limit (membre.rang % 4)
      ) t;

    if coalesce(array_length(podium, 1), 0) <> 2 then
      raise exception 'Cotes « podium » insuffisantes sur %.', gp.nom;
    end if;

    perform public.enregistrer_pronostics(
      membre.id, gp.id,
      vainqueur.id_outcome_unibet, podium[1], podium[2],
      coalesce(bonus, array[]::text[]));
  end loop;

  -- Contrôle : les 8 membres démo ont un vainqueur et un podium sur ce GP.
  if (select count(distinct p.profil_id)
        from public.pronostics p
        join auth.users u on u.id = p.profil_id
       where p.gp_id = gp.id
         and p.type in ('vainqueur', 'podium')
         and u.raw_app_meta_data ->> 'demo' = 'true'
         and u.email like 'demo-%@greedf1.invalid') <> 8 then
    raise exception 'Les 8 membres démo n''ont pas tous pronostiqué %.', gp.nom;
  end if;
end $$;

commit;

-- Ce que voit l'écran : un jeu par membre démo, et rien pour le reviewer.
select p.pseudo, pr.type, c.marche, c.pilote, c.valeur as points_potentiels
  from public.pronostics pr
  join public.profils p on p.id = pr.profil_id
  left join public.cotes c on c.gp_id = pr.gp_id and c.id_outcome_unibet = pr.id_outcome_unibet
 where pr.gp_id = (select id from public.grands_prix
                    where statut <> 'termine' and date_course > now()
                    order by date_course limit 1)
   and pr.profil_id in (select profil_id from public.membres_championnat
                         where championnat_id = '67dc7eb8-a039-43da-9b2f-d7b782e1b20e')
 order by p.pseudo, pr.type, c.pilote;
