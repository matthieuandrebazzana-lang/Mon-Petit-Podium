-- =============================================================================
-- Migration 19 — Les onze Grands Prix restants de la saison 2026
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, APRÈS les dix-huit
-- migrations précédentes. Elle suppose appliquées la 3 (`public.grands_prix`)
-- et la 11 (`date_qualifications`).
--
-- Elle ne remplace AUCUNE fonction existante : comme les migrations 11, 14, 15
-- et 17, elle ne peut pas entrer en conflit d'ordre avec une migration
-- antérieure rejouée par-dessus.
--
-- Elle touche aux DONNÉES et non au schéma — c'est le second cas après la 15.
-- Le GP des Pays-Bas n'est PAS inséré : il est déjà en base, scrapé et terminé.
--
--
-- ##  Trois écarts avec la demande, signalés (CLAUDE.md §6)
--
-- **1. `pays` et `ville` n'existent pas.** `public.grands_prix` porte `id`,
-- `id_unibet`, `nom`, `date_course`, `date_qualifications`, `statut` et
-- `cree_le` — rien d'autre. Le pays vit dans `GP_2026`
-- (`frontend/src/lib/calendrier2026.js`), la ville nulle part. Les deux sont
-- reportés en commentaire de la table de valeurs ci-dessous, à titre de repère
-- de relecture ; ils ne sont pas insérés, faute de colonne où les mettre.
-- Ajouter ces colonnes serait dupliquer une donnée dont le frontend est déjà le
-- propriétaire unique, et que le scraper ne saurait pas remplir.
--
-- **2. Les heures sont PRÉVISIONNELLES, pas exactes.** `calendrier2026.js` ne
-- porte que des dates nues, et son en-tête le dit : « l'heure de départ ne vient
-- jamais d'ici — seule la base la connaît ». Il n'y avait donc aucune heure
-- exacte à en tirer. Celles écrites ici suivent la convention des horaires
-- usuels de la Formule 1 — 15h00 locale, et leur heure habituelle pour les
-- courses de nuit — converties en UTC au fuseau réel de chaque circuit, DST
-- comprise. **Le scraper les écrasera par les horaires annoncés par Unibet dès
-- le premier passage** (`unibet._enregistrer`), ce qui est l'ordre voulu : une
-- prévision qui tient jusqu'à ce que la vraie donnée arrive.
--
-- **3. `id_unibet` est inventé, et c'est le point à surveiller.** La colonne est
-- `not null unique` et porte l'idempotence du scraper, qui se rapproche sur elle
-- et sur rien d'autre (`unibet._enregistrer`, upsert `on conflict id_unibet`).
-- Les identifiants Unibet des Grands Prix à venir n'existent pas encore : ils
-- sont attribués quand le bookmaker ouvre la page du GP suivant. Les lignes
-- posées ici portent donc un placeholder reconnaissable, `manuel-<slug>-2026`,
-- et **doivent être adoptées avant leur week-end** — voir la section 4.
--
--
-- ##  Ce que cette migration change à l'écran
--
-- Elle referme au passage le point de `roadmap.md` sur le bandeau « Grands Prix
-- restants » : `chargerGrandsPrixRestants` comptait les lignes en base, donc
-- une seule course. Il en comptera onze.
--
-- `chargerProchainGp` rendra le GP d'Italie au lieu de `null` : l'accueil
-- annonçait le prochain Grand Prix depuis une table qui n'en contenait plus.
--
-- **Conséquence à connaître sur le calendrier.** `etatDuGpSaison` ne déclare
-- « à venir » un GP absent de la base que parce qu'il n'a pas d'heure de départ
-- (`docs/calendrier.md` §6). Ces onze GP en ont désormais une — prévisionnelle.
-- Une carte peut donc passer à « Fermé » sur la foi d'une heure devinée, si le
-- départ réel est plus tardif que la convention. L'écart se referme dès le
-- premier scraping, qui écrit l'horaire d'Unibet.
--
-- La migration est idempotente, et elle l'est aussi APRÈS adoption : le garde-fou
-- de la section 3 se pose sur le slug du nom, pas sur `id_unibet` — sans quoi la
-- rejouer après qu'un identifiant a été adopté recréerait exactement le doublon
-- qu'elle cherche à éviter.
-- =============================================================================


-- --  1. Le slug d'un Grand Prix, en SQL  --------------------------------------

-- Contrepartie de `slugCircuit` (`frontend/src/composants/TracesCircuits.jsx`),
-- et pour la même raison : Unibet écrit « GP Pays Bas » cette semaine et
-- « GP Pays-Bas » la suivante. Le nom n'est jamais une clé — mais son slug est
-- une empreinte stable, et c'est ce qu'il faut ici pour reconnaître un Grand
-- Prix déjà présent quelle qu'en soit l'orthographe.
--
-- Les accents sont ramenés par `translate` et non par `unaccent` : l'extension
-- n'est pas garantie active sur le projet, et une migration qui échoue sur un
-- `create extension` refusé ne s'exécute pas du tout. Les deux casses sont
-- portées dans la table de traduction, ce qui rend la fonction juste même sous
-- une collation où `lower()` ne descend pas les majuscules accentuées.
--
-- `immutable` : la fonction ne lit ni la base ni l'horloge, elle ne dépend que
-- de son argument. C'est ce qui permet de l'appeler dans le `not exists` de la
-- section 3 sans la faire réévaluer ligne à ligne.
create or replace function public.slug_gp(p_nom text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select nullif(
    trim(both '-' from
      regexp_replace(
        regexp_replace(
          -- Le préfixe « GP » est retiré EN TÊTE seulement : un « GP » au
          -- milieu d'un nom n'est pas un préfixe.
          regexp_replace(
            lower(
              translate(
                coalesce(p_nom, ''),
                'àáâãäåçèéêëìíîïñòóôõöùúûüýÿÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝ',
                'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUY'
              )
            ),
            '^gp[^a-z0-9]+', ''
          ),
          '[^a-z0-9]+', '-', 'g'
        ),
        '-{2,}', '-', 'g'
      )
    ),
    ''
  );
$$;

comment on function public.slug_gp(text) is
  'Empreinte stable du nom d''un GP (« GP Pays Bas » et « GP Pays-Bas » → « pays-bas »). Contrepartie SQL de slugCircuit. Ne remplace jamais id_unibet comme clé de rapprochement du scraper.';

-- Lecture seule et sans effet de bord, mais réservée au serveur : elle n'a
-- aucun usage côté client, et une fonction créée sans `revoke` est exécutable
-- par `public`, donc par `anon`.
revoke all on function public.slug_gp(text) from public;
grant execute on function public.slug_gp(text) to service_role;


-- --  2. Auto-épreuve du slug  --------------------------------------------------

-- La leçon de la migration 17 : le seul moment où l'on peut savoir qu'une
-- expression est juste, c'est en la jouant. `slug_gp` porte trois `regexp_replace`
-- imbriqués et une table de traduction de 54 caractères — exactement le genre de
-- construction qui paraît juste et ne l'est pas. Elle s'éprouve donc ici, sur les
-- cas qui comptent : accents, orthographe changeante, préfixe.
do $$
begin
  if public.slug_gp('GP Pays Bas')    is distinct from 'pays-bas'    then
    raise exception 'slug_gp : « GP Pays Bas » devrait donner « pays-bas », donne « % »', public.slug_gp('GP Pays Bas');
  end if;
  if public.slug_gp('GP Pays-Bas')    is distinct from 'pays-bas'    then
    raise exception 'slug_gp : « GP Pays-Bas » devrait donner « pays-bas », donne « % »', public.slug_gp('GP Pays-Bas');
  end if;
  if public.slug_gp('GP États-Unis')  is distinct from 'etats-unis'  then
    raise exception 'slug_gp : « GP États-Unis » devrait donner « etats-unis », donne « % »', public.slug_gp('GP États-Unis');
  end if;
  if public.slug_gp('GP Azerbaïdjan') is distinct from 'azerbaidjan' then
    raise exception 'slug_gp : « GP Azerbaïdjan » devrait donner « azerbaidjan », donne « % »', public.slug_gp('GP Azerbaïdjan');
  end if;
  if public.slug_gp('GP Brésil')      is distinct from 'bresil'      then
    raise exception 'slug_gp : « GP Brésil » devrait donner « bresil », donne « % »', public.slug_gp('GP Brésil');
  end if;
  if public.slug_gp('GP Abu Dhabi')   is distinct from 'abu-dhabi'   then
    raise exception 'slug_gp : « GP Abu Dhabi » devrait donner « abu-dhabi », donne « % »', public.slug_gp('GP Abu Dhabi');
  end if;

  raise notice 'slug_gp : les six cas d''épreuve passent.';
end
$$;


-- --  3. Les onze Grands Prix  --------------------------------------------------

-- Heures converties en UTC au fuseau réel du circuit, heure d'été comprise.
-- Deux bascules sont dans la fenêtre et ont été prises en compte : les
-- États-Unis passent à l'heure d'hiver le 1er novembre 2026 (Austin le 25
-- octobre est donc encore en CDT, UTC−5 ; Las Vegas le 21 novembre est en PST,
-- UTC−8), et l'Europe le 25 octobre (Monza et Madrid, en septembre, sont en
-- CEST, UTC+2). Le Mexique et le Brésil n'observent plus l'heure d'été.
--
-- `date_qualifications = date_course − 22h` : c'est `REPLI_QUALIFICATIONS`
-- (`app/scraper/unibet.py`), le repli que le scraper applique lui-même quand
-- Unibet n'annonce pas le programme, et que la migration 11 a déjà appliqué aux
-- lignes existantes. **Une seule règle, un seul propriétaire** — poser ici une
-- seconde convention en ferait deux à maintenir.
--
-- Ce repli place les qualifications le samedi après-midi pour une course le
-- dimanche après-midi. Les deux courses du samedi le placent le vendredi, ce qui
-- est le bon jour. Pour Las Vegas, couru le samedi à 22h locale, il tombe le
-- samedi à minuit locale : c'est deux heures après les qualifications réelles,
-- et donc dans la bonne nuit. Aucune de ces heures n'a vocation à survivre au
-- premier scraping.
insert into public.grands_prix (id_unibet, nom, date_course, date_qualifications, statut)
select
  v.id_unibet,
  v.nom,
  v.date_course,
  v.date_course - interval '22 hours',
  'a_venir'
from (values
  -- id_unibet placeholder     | nom               | départ (UTC)                         -- pays / ville, hors schéma (écart 1) + heure locale
  ('manuel-italie-2026',       'GP Italie',        timestamptz '2026-09-06 13:00:00+00'), -- Italie      / Monza              — dim. 15h00 CEST  (UTC+2)
  ('manuel-espagne-2026',      'GP Espagne',       timestamptz '2026-09-13 13:00:00+00'), -- Espagne     / Madrid             — dim. 15h00 CEST  (UTC+2)
  ('manuel-azerbaidjan-2026',  'GP Azerbaïdjan',   timestamptz '2026-09-26 11:00:00+00'), -- Azerbaïdjan / Bakou              — sam. 15h00 AZT   (UTC+4)
  ('manuel-malaisie-2026',     'GP Malaisie',      timestamptz '2026-10-04 07:00:00+00'), -- Malaisie    / Sepang             — dim. 15h00 MYT   (UTC+8)
  ('manuel-singapour-2026',    'GP Singapour',     timestamptz '2026-10-11 12:00:00+00'), -- Singapour   / Singapour          — dim. 20h00 SGT   (UTC+8) — course de nuit
  ('manuel-etats-unis-2026',   'GP États-Unis',    timestamptz '2026-10-25 20:00:00+00'), -- États-Unis  / Austin             — dim. 15h00 CDT   (UTC−5)
  ('manuel-mexique-2026',      'GP Mexique',       timestamptz '2026-11-01 21:00:00+00'), -- Mexique     / Hermanos Rodríguez — dim. 15h00 CST   (UTC−6)
  ('manuel-bresil-2026',       'GP Brésil',        timestamptz '2026-11-15 18:00:00+00'), -- Brésil      / Interlagos         — dim. 15h00 BRT   (UTC−3)
  ('manuel-las-vegas-2026',    'GP Las Vegas',     timestamptz '2026-11-22 06:00:00+00'), -- États-Unis  / Las Vegas          — sam. 22h00 PST   (UTC−8) — course de nuit, dimanche en UTC
  ('manuel-qatar-2026',        'GP Qatar',         timestamptz '2026-11-29 17:00:00+00'), -- Qatar       / Lusail             — dim. 20h00 AST   (UTC+3) — course de nuit
  ('manuel-abu-dhabi-2026',    'GP Abu Dhabi',     timestamptz '2026-12-06 13:00:00+00')  -- Abu Dhabi   / Yas Marina         — dim. 17h00 GST   (UTC+4)
) as v (id_unibet, nom, date_course)

-- **Le garde-fou porte sur le SLUG, jamais sur `id_unibet`.** Un `on conflict
-- (id_unibet) do nothing` paraîtrait suffire et serait le piège : une fois la
-- ligne adoptée (section 4), son `id_unibet` n'est plus le placeholder, la
-- clause ne trouverait plus de conflit et la migration rejouée réinsérerait le
-- doublon qu'elle est faite pour éviter. Le slug, lui, survit à l'adoption
-- comme au changement d'orthographe qu'Unibet apporte au premier scraping.
--
-- C'est aussi ce qui protège le GP des Pays-Bas si son nom devait figurer ici un
-- jour, et ce qui rend la migration sûre pour un GP découvert par le scraper
-- avant qu'elle ne soit jouée.
where not exists (
  select 1
  from public.grands_prix g
  where public.slug_gp(g.nom) = public.slug_gp(v.nom)
);


-- --  4. L'adoption d'une ligne manuelle  ---------------------------------------

-- **Le geste à ne pas oublier, une fois par Grand Prix.**
--
-- Le scraper se rapproche sur `id_unibet` et sur rien d'autre. Tant qu'une ligne
-- porte son placeholder, le vrai Grand Prix publié par Unibet ne la reconnaît
-- pas : il s'insère à côté, et la base porte deux lignes pour la même course.
-- Le symptôme serait discret — `enrichir` (`calendrier2026.js`) rapproche par
-- slug et construit une `Map`, donc la dernière ligne servie l'emporte : le
-- calendrier pourrait s'accrocher à la ligne manuelle, celle qui n'a **pas** les
-- cotes, et afficher « à venir » un Grand Prix pronosticable.
--
-- Cette fonction referme les deux cas :
--
--   - **le placeholder est encore seul** → son `id_unibet` est remplacé par le
--     vrai. Le prochain scraping met à jour la ligne au lieu d'en créer une, et
--     tout ce qui pend à `gp_id` (cotes, pronostics) reste attaché ;
--   - **le scraper est arrivé le premier** → les deux lignes coexistent. La
--     ligne du scraper est gardée, elle seule porte les cotes ; la ligne
--     manuelle est supprimée, mais **seulement si rien n'y pend**. Un
--     `delete` aveugle emporterait en cascade des cotes ou des pronostics
--     (`on delete cascade`, migrations 3 et 5) : mieux vaut un doublon visible
--     qu'un pronostic effacé sans bruit.
--
-- Usage, à jouer dans le SQL Editor le vendredi ou le samedi matin du week-end
-- visé — c'est-à-dire AVANT l'instant de déclenchement du job, faute de quoi le
-- Grand Prix ne sera pas figé automatiquement (`app/jobs/scraper.py` : le
-- déclenchement s'ouvre à `date_qualifications + 2h` et se referme 4h plus tard) :
--
--     select public.adopter_grand_prix('manuel-italie-2026', 'p59405525');
--
-- Le second argument se lit dans le journal du scraper, qui écrit le nom et
-- l'identifiant Unibet de chaque Grand Prix rencontré (`unibet.py`, ligne
-- « % (%) »), ou dans l'URL de la page du Grand Prix chez le bookmaker.
--
-- Idempotente : rejouer une adoption déjà faite ne touche à rien et le dit.
create or replace function public.adopter_grand_prix(
  p_placeholder text,
  p_id_unibet   text
)
returns text
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  l_manuel   uuid;
  l_reel     uuid;
  l_attaches integer;
begin
  if coalesce(trim(p_placeholder), '') = '' or coalesce(trim(p_id_unibet), '') = '' then
    raise exception 'adopter_grand_prix : les deux arguments sont obligatoires.';
  end if;

  if p_placeholder = p_id_unibet then
    raise exception 'adopter_grand_prix : le placeholder et l''identifiant Unibet sont identiques (« % »).', p_placeholder;
  end if;

  select id into l_manuel from public.grands_prix where id_unibet = p_placeholder;
  select id into l_reel   from public.grands_prix where id_unibet = p_id_unibet;

  -- Rien à adopter, et rien d'anormal : l'adoption a déjà eu lieu.
  if l_manuel is null and l_reel is not null then
    return format('Déjà adopté : « %s » porte l''identifiant Unibet « %s ».', p_id_unibet, p_id_unibet);
  end if;

  if l_manuel is null then
    raise exception 'adopter_grand_prix : aucune ligne ne porte le placeholder « % ».', p_placeholder;
  end if;

  -- Cas simple : le placeholder est seul, il prend le vrai identifiant.
  if l_reel is null then
    update public.grands_prix
       set id_unibet = p_id_unibet
     where id = l_manuel;

    return format('Adopté : la ligne manuelle « %s » porte désormais « %s ». Le prochain scraping la mettra à jour.', p_placeholder, p_id_unibet);
  end if;

  -- Cas du doublon : le scraper est arrivé avant l'adoption. On garde SA ligne,
  -- qui porte les cotes, et on retire la nôtre — si et seulement si elle est
  -- vide. Les quatre tables filles de `grands_prix` sont comptées, aucune n'est
  -- supposée vide d'avance.
  select
      (select count(*) from public.cotes       where gp_id = l_manuel)
    + (select count(*) from public.pronostics  where gp_id = l_manuel)
    + (select count(*) from public.favoris     where gp_id = l_manuel)
    + (select count(*) from public.resultats_gp where gp_id = l_manuel)
  into l_attaches;

  if l_attaches > 0 then
    raise exception
      'adopter_grand_prix : « % » et « % » désignent le même Grand Prix, mais % ligne(s) pendent à la ligne manuelle. Elle n''est pas supprimée — la supprimer les emporterait en cascade. À reprendre à la main.',
      p_placeholder, p_id_unibet, l_attaches;
  end if;

  delete from public.grands_prix where id = l_manuel;

  return format('Doublon résorbé : la ligne manuelle « %s » était vide et a été supprimée. La ligne du scraper « %s » est conservée.', p_placeholder, p_id_unibet);
end
$$;

comment on function public.adopter_grand_prix(text, text) is
  'Fait porter à une ligne posée à la main le vrai id_unibet, pour que le scraper la mette à jour au lieu d''en créer une seconde. Résorbe le doublon si le scraper est arrivé le premier, et seulement si la ligne manuelle est vide.';

revoke all on function public.adopter_grand_prix(text, text) from public;
grant execute on function public.adopter_grand_prix(text, text) to service_role;


-- --  5. Compte rendu  ----------------------------------------------------------

do $$
declare
  poses    integer;
  restants integer;
begin
  select count(*) into poses
    from public.grands_prix
   where id_unibet like 'manuel-%-2026';

  select count(*) into restants
    from public.grands_prix
   where statut <> 'termine';

  raise notice 'Grands Prix portant encore un placeholder : % — à adopter un par un avant leur week-end (section 4).', poses;
  raise notice 'Grands Prix non terminés en base : %.', restants;
end
$$;
