-- =============================================================================
--  PLAN B — Figer à la main les cotes du GP du Brésil 2026 (p59405528)
-- =============================================================================
--
-- CE N'EST PAS UNE MIGRATION. À n'exécuter que si Unibet ne republie pas le
-- marché « Vainqueur » à temps (backend 0.88.3 : pas de figeage sans lui,
-- `scraper.md` §8), et que la décision d'ouvrir les pronostics sur les cotes
-- déjà en base est prise.
--
-- À jouer dans le SQL Editor, EN TROIS FOIS : sélectionner une section, puis
-- « Run selected ». L'éditeur n'affiche que le résultat de la dernière requête.
--
--   1. Contrôle AVANT   — lecture seule ;
--   2. Figeage          — une transaction, refusée si une garde tombe ;
--   3. Contrôle APRÈS   — lecture seule.
--
-- Ce que fait le figeage normal (`jobs/scraper.figer` puis `_apres_figeage`),
-- et ce que ce script reproduit :
--
--   | Effet du job                                           | Ici          |
--   |--------------------------------------------------------|--------------|
--   | `statut` a_venir → cotes_figees, filtré sur a_venir    | oui          |
--   | alerte `cotes_en_retard` du GP effacée                 | oui          |
--   | rattachement des issues aux engagés (OpenF1)           | NON — étape 4|
--
-- Rien d'autre ne bouge : ni les cotes (aucune colonne touchée), ni
-- `date_course`, ni `date_qualifications`. Une fois `cotes_figees`, le scraper
-- refuse d'écrire les cotes de ce GP et le job ne le scrape plus.
--
-- Notifications : rien n'est envoyé d'ici. Au tour suivant (≤ 5 min), le job de
-- notifications voit le GP `cotes_figees`, avec une cote en base, avant le
-- départ, et envoie « Les pronos pour le GP du Brésil sont ouverts » —
-- **sauf si `ouverture` est déjà dans `notifications_envoyees`** (l'ancien code
-- la réservait à qualifs − 1 h, le 7/11 à 17:00Z). C'est exactement le
-- comportement du figeage normal. Voir la section 4 pour la renvoyer.
-- La « dernière chance » (8/11 16:00Z) exige `cotes_figees` : elle partira.
-- =============================================================================


-- --  1. Contrôle AVANT (lecture seule)  ---------------------------------------

select g.id,
       g.nom,
       g.id_unibet,
       g.statut,
       g.date_qualifications,
       g.date_course,
       now() < g.date_course                                   as course_a_venir,
       count(c.*)                                              as cotes,
       count(c.*) filter (where c.marche = 'vainqueur')        as cotes_vainqueur,
       count(distinct c.marche)                                as marches,
       string_agg(distinct c.marche, ', ' order by c.marche)   as liste_marches,
       min(c.cree_le)                                          as premiere_cote_creee,
       max(c.cree_le)                                          as derniere_cote_creee,
       (select string_agg(n.evenement || ' @ ' || n.envoyee_le, ' ; ' order by n.envoyee_le)
          from public.notifications_envoyees n
         where n.gp_id = g.id)                                 as notifications_deja_envoyees
  from public.grands_prix g
  left join public.cotes c on c.gp_id = g.id
 where g.id_unibet = 'p59405528'
 group by g.id;

-- Attendu : une ligne, statut a_venir, course_a_venir true, cotes_vainqueur > 0.
-- `cree_le` est la date de PREMIÈRE insertion : l'upsert du scraper ne la
-- change pas, elle ne dit donc pas quand une cote a été rafraîchie.


-- --  2. Figeage (une transaction, gardes comprises)  -------------------------

begin;

do $$
declare
  v_gp        public.grands_prix%rowtype;
  v_nombre    integer;
  v_vainqueur integer;
  v_cotes     integer;
  v_touchees  integer;
begin
  select count(*) into v_nombre
    from public.grands_prix where id_unibet = 'p59405528';
  if v_nombre <> 1 then
    raise exception 'Plan B refusé : % ligne(s) portent l''identifiant p59405528, une seule attendue.', v_nombre;
  end if;

  -- Verrou de ligne : le job de scraping (toutes les 15 min) ne peut pas figer
  -- ni réécrire ce GP entre les gardes et l'écriture.
  select * into v_gp
    from public.grands_prix where id_unibet = 'p59405528'
     for update;

  if v_gp.statut <> 'a_venir' then
    raise exception 'Plan B refusé : « % » est déjà « % ». Rien n''est modifié.', v_gp.nom, v_gp.statut;
  end if;

  if v_gp.date_course is null then
    raise exception 'Plan B refusé : heure de départ inconnue pour %.', v_gp.nom;
  end if;

  if now() >= v_gp.date_course then
    raise exception 'Plan B refusé : la course est partie (%). Ouvrir les pronostics n''a plus de sens.', v_gp.date_course;
  end if;

  select count(*), count(*) filter (where marche = 'vainqueur')
    into v_cotes, v_vainqueur
    from public.cotes where gp_id = v_gp.id;

  if v_vainqueur = 0 then
    raise exception 'Plan B refusé : aucune cote du marché « vainqueur » en base pour % (% cote(s) au total).', v_gp.nom, v_cotes;
  end if;

  -- Le même PATCH que `jobs/scraper.figer` : filtré sur le statut autant que
  -- sur l'identifiant.
  update public.grands_prix
     set statut = 'cotes_figees'
   where id = v_gp.id
     and statut = 'a_venir';
  get diagnostics v_touchees = row_count;
  if v_touchees <> 1 then
    raise exception 'Plan B refusé : % ligne(s) touchée(s) au figeage, une attendue.', v_touchees;
  end if;

  -- Comme `_apres_figeage` : l'alerte de retard n'a plus d'objet. Sans la
  -- migration 37 il n'y en a aucune, la suppression ne touche rien.
  delete from public.alertes_admin
   where gp_id = v_gp.id
     and type = 'cotes_en_retard';

  raise notice 'Plan B : % (%) figé — % cote(s), dont % sur « vainqueur ». Départ %.',
    v_gp.nom, v_gp.id, v_cotes, v_vainqueur, v_gp.date_course;
end
$$;

commit;

-- Une garde qui tombe lève : la transaction est annulée, rien n'est écrit.
-- (Si l'éditeur reste en transaction après l'erreur, lancer `rollback;`.)


-- --  3. Contrôle APRÈS (lecture seule)  ---------------------------------------

select g.nom,
       g.statut,
       g.date_course,
       count(c.*)                                             as cotes,
       count(c.*) filter (where c.marche = 'vainqueur')       as cotes_vainqueur,
       count(c.*) filter (where c.numero_pilote is not null
                             or c.ecurie_id is not null)      as issues_rattachees,
       (select count(*) from public.alertes_admin a
         where a.gp_id = g.id and a.type = 'cotes_en_retard') as alertes_retard,
       (select string_agg(n.evenement || ' @ ' || n.envoyee_le, ' ; ' order by n.envoyee_le)
          from public.notifications_envoyees n
         where n.gp_id = g.id)                                as notifications_envoyees
  from public.grands_prix g
  left join public.cotes c on c.gp_id = g.id
 where g.id_unibet = 'p59405528'
 group by g.id;

-- Attendu : statut cotes_figees, alertes_retard 0. Relancer 5 à 10 min plus
-- tard : `ouverture` doit apparaître dans notifications_envoyees (sauf si elle
-- y était déjà avant — voir section 4).


-- --  4. Après le figeage, hors SQL  ------------------------------------------
--
-- a) Rattachement des issues aux engagés, que le job fait juste après un
--    figeage. Sans lui le calcul retombe sur les libellés ; avec lui, les
--    alertes « libellé non reconnu » remontent au profil admin avant la course :
--
--    curl -X POST "https://mon-petit-podium-production.up.railway.app/scraper/rattacher/<id du GP, section 1>" \
--         -H "X-Admin-Secret: <ADMIN_SECRET>"
--
-- b) FACULTATIF — renvoyer « pronos ouverts » si l'ancien code l'a déjà
--    réservée le 7/11 à 17:00Z (envoyée alors sur des pronostics fermés). Le
--    figeage normal ne la renverrait pas ; ce geste sort donc du « comme le
--    job ». Le tour suivant du job de notifications la renvoie à tous :
--
--    delete from public.notifications_envoyees
--     where gp_id = (select id from public.grands_prix where id_unibet = 'p59405528')
--       and evenement = 'ouverture';
--
-- RETOUR ARRIÈRE (avant que quiconque ait pronostiqué) :
--    update public.grands_prix set statut = 'a_venir'
--     where id_unibet = 'p59405528' and statut = 'cotes_figees';
--    Le job reprend alors le scraping au tour suivant.
