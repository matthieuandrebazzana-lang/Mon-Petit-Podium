-- =============================================================================
-- Étape 11 — Date des qualifications, pour le déclenchement automatique du scraper
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI,
-- APRÈS les dix migrations précédentes. Elle ne crée AUCUNE table : une colonne,
-- un index partiel.
--
-- Elle suppose appliquée la 3, qui crée `public.grands_prix`. Elle ne touche à
-- aucune fonction, donc elle ne peut pas entrer en conflit d'ordre avec une
-- migration antérieure rejouée par-dessus — contrairement aux pièges déjà
-- documentés (« rejouer la 7 après la 8 », « rejouer la 5 après la 10 »).
--
-- La migration est idempotente : la rejouer ne casse rien et ne touche à
-- aucune donnée.
-- =============================================================================


-- --  1. La colonne  -----------------------------------------------------------

-- Règle 4.3 : les cotes se scrapent le samedi, **2h après les qualifications**.
-- Jusqu'ici cet horaire n'existait nulle part en base, et le déclenchement était
-- donc forcément manuel. C'est cette colonne qui le rend automatisable.
--
-- **Nullable, et ce n'est pas une facilité.** Unibet publie parfois un Grand
-- Prix avant d'en annoncer le programme (le CLAUDE.md le note dès l'étape 4 pour
-- `date_course`). Un `not null` obligerait alors le scraper à inventer une date
-- pour pouvoir écrire la ligne, ou à ne pas écrire la ligne du tout — c'est-à-dire
-- à faire disparaître le Grand Prix de l'accueil et du calendrier. Une colonne
-- vide se voit et se corrige ; un Grand Prix manquant se voit aussi, mais trop
-- tard.
--
-- En pratique le scraper la remplit toujours : à défaut d'événement
-- « Qualifications » chez Unibet, il retient `date_course - 22h` et le
-- journalise. Le NULL reste donc l'état d'un GP dont on ne connaît même pas
-- l'heure de course.
alter table public.grands_prix
  add column if not exists date_qualifications timestamptz;

comment on column public.grands_prix.date_qualifications is
  'Heure des qualifications, en UTC. Sert au déclenchement automatique du scraping, 2h après (règle 4.3). Repli du scraper si Unibet ne l''annonce pas : date_course - 22h.';


-- --  2. L'index qui sert le job horaire  --------------------------------------

-- Le job du scraper lit, toutes les heures, « les Grands Prix encore à venir
-- dont les qualifications sont passées ». L'index est **partiel** sur le seul
-- statut interrogé : un GP figé ou terminé ne repasse jamais dans cette boucle,
-- et les lignes correspondantes n'ont donc rien à faire dans l'index. Il se vide
-- de lui-même à mesure que la saison avance, exactement comme
-- `pronostics_a_calculer_idx` de l'étape 6.
--
-- La table restera petite (une vingtaine de lignes par saison) : cet index n'est
-- pas là pour la performance mais pour que la requête du job soit servie sans
-- balayage, une fois par heure, pendant toute la saison.
create index if not exists grands_prix_qualifs_a_venir_idx
  on public.grands_prix (date_qualifications)
  where statut = 'a_venir';


-- --  3. Reprise de l'existant  ------------------------------------------------

-- Les Grands Prix déjà en base ont été scrapés avant l'existence de la colonne.
-- Sans reprise, ils ne seraient jamais figés automatiquement : le job ne
-- retiendrait que les GP re-scrapés depuis. On leur applique le même repli que
-- le scraper — `date_course - 22h` — ce qui place les qualifications le samedi
-- après-midi pour une course le dimanche après-midi.
--
-- Le filtre `date_qualifications is null` rend l'opération idempotente **et**
-- non destructive : un horaire déjà connu (annoncé par Unibet, ou corrigé à la
-- main) n'est jamais réécrit par ce repli.
do $$
declare
  reprises integer;
begin
  update public.grands_prix
     set date_qualifications = date_course - interval '22 hours'
   where date_qualifications is null
     and date_course is not null
     and statut = 'a_venir';

  get diagnostics reprises = row_count;

  if reprises > 0 then
    raise notice 'Reprise : % Grand(s) Prix ont reçu une date de qualifications par défaut (date_course - 22h).', reprises;
  end if;
end
$$;
