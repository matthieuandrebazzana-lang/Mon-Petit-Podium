-- =============================================================================
-- Étape 20 — Horaires de qualifications 2026, explicites et non plus dérivés
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, **TOUJOURS APRÈS
-- LA 19**. Elle ne crée ni table, ni colonne, ni fonction : elle corrige des
-- données et réécrit un commentaire de colonne.
--
-- Elle suppose appliquées la 3 (`public.grands_prix`), la 11
-- (`date_qualifications`) et la 19 (`public.slug_gp` et les onze lignes
-- manuelles). Elle ne remplace aucune fonction, donc elle n'entre en conflit
-- d'ordre avec aucune des autres — ni avec la 15, la 16, la 17 ou la 18, qui
-- peuvent se jouer avant ou après elle.
--
-- > ### Le seul ordre qui compte : 19 PUIS 20, jamais l'inverse
-- >
-- > **La 19 n'est pas réécrite**, parce que les migrations de ce dépôt sont
-- > historiques et ne le sont jamais (`database.md` §7 — un commentaire périmé
-- > subsiste dans la 3 pour la même raison). Elle continue donc d'insérer
-- > `date_course − 22h`, et **c'est cette migration-ci qui corrige derrière
-- > elle**. Jouée avant la 19, elle ne trouverait rien à corriger et la 19
-- > reposerait ensuite les heures dérivées : il faudrait la rejouer.
--
-- La migration est idempotente : la rejouer ne corrige plus rien et ne détruit
-- rien. Le compte annoncé en fin d'exécution le dit — **« 9 corrigés » au
-- premier passage**, puis « rien à corriger ». Neuf et non onze : Austin et le
-- Mexique ont un écart réel de 22 h, donc le repli tombait juste pour eux deux.
-- =============================================================================


-- --  1. Pourquoi cette migration existe  --------------------------------------
--
-- La 19 pose `date_qualifications = date_course − 22 heures`, c'est-à-dire
-- l'ancien `REPLI_QUALIFICATIONS` du scraper. Le motif était de n'avoir qu'une
-- seule règle et un seul propriétaire ; **le motif était bon, la règle était
-- fausse.** 22 h est une constante, et l'écart réel entre les qualifications et
-- le départ n'en est pas une :
--
--     23 h — Italie, Espagne, Azerbaïdjan, Malaisie, Singapour, Qatar, Abu Dhabi
--     22 h — États-Unis, Mexique   (course deux heures plus tôt en heure locale)
--     24 h — Brésil                (qualifications et course à la même heure)
--     26 h — Las Vegas             (qualifications le VENDREDI soir)
--
-- **Neuf des onze lignes portaient donc une heure fausse**, de une à quatre
-- heures. Et le défaut n'était pas seulement en base : `seancesDuGp`
-- (`lib/calendrier2026.js`) préfère l'heure de la BASE à celle de la table
-- statique — c'est la règle « la base l'emporte partout où elle a une réponse »,
-- posée en `0.59.0`. La fiche du GP d'Italie aurait donc annoncé des
-- qualifications à 17h00 alors que `GP_2026` porte la bonne heure, 16h00 :
-- **une heure devinée chassait une heure relevée.**
--
-- Les onze valeurs ci-dessous sont les mêmes instants UTC que
-- `GP_2026.seances.qualifications` (`frontend/src/lib/calendrier2026.js`). **Les
-- deux tables se relisent ensemble**, une fois par saison, sur le calendrier
-- officiel de la FIA — au même titre que `GP_2026` elle-même et que la grille de
-- `backend/app/calcul/pilotes.py`.


-- --  2. La correction  ---------------------------------------------------------
--
-- **Trois gardes, et chacune protège d'une chose précise :**
--
-- 1. `slug_gp(nom)` plutôt que `id_unibet` — une ligne déjà adoptée
--    (`adopter_grand_prix`, migration 19) ne porte plus son placeholder, et
--    c'est justement celle qu'il faut corriger. Le slug survit à l'adoption
--    comme au changement d'orthographe qu'Unibet apporte au premier scraping.
--
-- 2. `date_qualifications is null or = date_course − 22 h` — **on ne corrige
--    que ce qui porte encore la marque du repli.** Une heure qu'Unibet a
--    réellement annoncée depuis n'est jamais réécrite : elle vaut mieux que la
--    nôtre, qui reste prévisionnelle. Deux Grands Prix — Austin et le Mexique —
--    ont un écart réel de 22 h : pour eux la garde ne distingue pas le repli de
--    la bonne valeur, et la troisième garde rend l'écriture inoffensive.
--
-- 3. `is distinct from` la valeur cible — une ligne déjà juste n'est pas
--    réécrite. C'est ce qui rend la migration idempotente au sens strict : la
--    rejouer rapporte « 0 corrigé », et non « 11 réécrits à l'identique ».
--
-- `statut <> 'termine'` écarte l'archive : le GP des Pays-Bas ne figure pas dans
-- la liste, mais rien ne doit toucher l'horaire d'une course déjà courue.
do $$
declare
  corrigees integer;
begin
  with reference (slug, quali) as (
    values
      ('italie',      timestamptz '2026-09-05 14:00:00+00'), -- sam. 16h00 CEST (UTC+2)
      ('espagne',     timestamptz '2026-09-12 14:00:00+00'), -- sam. 16h00 CEST (UTC+2)
      ('azerbaidjan', timestamptz '2026-09-25 12:00:00+00'), -- ven. 16h00 AZT  (UTC+4) — course le SAMEDI
      ('malaisie',    timestamptz '2026-10-03 08:00:00+00'), -- sam. 16h00 MYT  (UTC+8)
      ('singapour',   timestamptz '2026-10-10 13:00:00+00'), -- sam. 21h00 SGT  (UTC+8) — nuit ; seul week-end sprint
      ('etats-unis',  timestamptz '2026-10-24 22:00:00+00'), -- sam. 17h00 CDT  (UTC−5)
      ('mexique',     timestamptz '2026-10-31 23:00:00+00'), -- sam. 17h00 CST  (UTC−6)
      ('bresil',      timestamptz '2026-11-14 18:00:00+00'), -- sam. 15h00 BRT  (UTC−3)
      ('las-vegas',   timestamptz '2026-11-21 04:00:00+00'), -- VEN. 20h00 PST  (UTC−8) — nuit
      ('qatar',       timestamptz '2026-11-28 18:00:00+00'), -- sam. 21h00 AST  (UTC+3) — nuit
      ('abu-dhabi',   timestamptz '2026-12-05 14:00:00+00')  -- sam. 18h00 GST  (UTC+4)
  )
  update public.grands_prix g
     set date_qualifications = r.quali
    from reference r
   where public.slug_gp(g.nom) = r.slug
     and g.statut is distinct from 'termine'
     and (
       g.date_qualifications is null
       or g.date_qualifications = g.date_course - interval '22 hours'
     )
     and g.date_qualifications is distinct from r.quali;

  get diagnostics corrigees = row_count;

  if corrigees = 0 then
    raise notice 'Horaires de qualifications : rien à corriger (migration déjà jouée, ou 19 pas encore jouée).';
  else
    raise notice 'Horaires de qualifications : % Grand(s) Prix corrigé(s).', corrigees;
  end if;
end
$$;


-- --  3. Le commentaire de colonne, qui décrivait le repli  ---------------------
--
-- La 11 documentait la colonne par « Repli du scraper si Unibet ne l'annonce
-- pas : date_course - 22h ». **Ce repli n'existe plus** (`0.57.0` du backend) :
-- quand Unibet se tait, la clé n'est pas écrite dans l'upsert et la valeur déjà
-- en base survit. Laisser l'ancienne phrase ferait de `\d+ grands_prix` la
-- dernière trace d'une règle retirée — et c'est le genre de trace qu'on relit
-- des mois plus tard en la croyant vraie.
comment on column public.grands_prix.date_qualifications is
  'Heure des qualifications, en UTC. Sert au déclenchement automatique du scraping, 2h après (règle 4.3). Écrite explicitement par la migration 20, puis remplacée par le programme d''Unibet dès qu''il le publie. JAMAIS dérivée de date_course : le repli date_course - 22h a été retiré en 0.57.0.';


-- --  4. Contrôle à l'œil  ------------------------------------------------------
--
-- À relire après exécution. **La colonne `ecart` est celle qui parle** : douze
-- fois « 22:00:00 » signifiait que tout était dérivé. Une colonne qui varie —
-- 22 h, 23 h, 24 h, 26 h — signifie que chaque Grand Prix porte sa propre heure.
--
-- Aucune valeur de référence n'est répétée ici : cette requête lit la table,
-- elle ne la vérifie pas contre une seconde copie de la liste. Deux listes
-- auraient divergé au premier horaire retouché.
select
  g.nom,
  g.statut,
  g.date_qualifications,
  g.date_course,
  g.date_course - g.date_qualifications as ecart,
  g.id_unibet like 'manuel-%' as ligne_manuelle_a_adopter
from public.grands_prix g
order by g.date_course;
