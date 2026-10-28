-- =============================================================================
--  Migration 33 — Horaires du GP du Mexique 2026
-- =============================================================================
--
-- Symptôme : qualifications affichées 2 h trop tard, course 1 h trop tard.
-- Deux écarts différents : pas un fuseau, deux HEURES LOCALES fausses.
--
-- Le Mexique n'a plus d'heure d'été depuis 2022 : Mexico est à UTC−6 toute
-- l'année, et OpenF1 sert `gmt_offset = -06:00` pour ce week-end. La conversion
-- était juste ; ce sont les heures locales de départ qui ne l'étaient pas :
--
--   | Séance          | Posée par        | Heure posée        | Officielle         |
--   |-----------------|------------------|--------------------|--------------------|
--   | Qualifications  | migration 20     | sam. 17h00 = 23:00Z | sam. 15h00 = 21:00Z |
--   | Course          | migration 19     | dim. 15h00 = 21:00Z | dim. 14h00 = 20:00Z |
--
-- Sources : OpenF1 `/v1/sessions?year=2026&country_name=Mexico` (sessions
-- 11400 et 11404), calendrier officiel F1. La 19 disait son heure de course
-- « prévisionnelle » ; la 20 croyait au contraire l'heure des qualifications
-- relevée — elle ne l'était pas pour le Mexique.
--
-- **Le scraper ne réécrira pas l'erreur.** Il n'écrit `date_qualifications` que
-- si Unibet publie un événement de qualification (`resoudre_qualifications`) ;
-- sinon la clé est absente de l'upsert et la valeur d'ici survit. Il écrit
-- `date_course` depuis l'heure de départ d'Unibet, à l'ouverture de la page du
-- GP : une heure relevée chez le bookmaker, plus jamais la 15h00 devinée.
--
-- **Urgence** : `pronostics_fermes` ferme à `date_course`. À 21:00Z, les
-- pronostics seraient restés ouverts pendant la première heure de course.
--
-- Garde : seule une ligne du week-end portant EXACTEMENT l'instant faux est
-- touchée. Une heure qu'Unibet aurait déjà écrite n'est jamais remplacée.
-- Idempotente : rejouée, elle ne trouve plus rien à corriger.
-- =============================================================================

update public.grands_prix
   set date_qualifications = timestamptz '2026-10-31 21:00:00+00'
 where date_qualifications = timestamptz '2026-10-31 23:00:00+00'
   and date_course between timestamptz '2026-10-30 00:00:00+00'
                       and timestamptz '2026-11-03 00:00:00+00';

update public.grands_prix
   set date_course = timestamptz '2026-11-01 20:00:00+00'
 where date_course = timestamptz '2026-11-01 21:00:00+00';

do $$
begin
  if exists (
    select 1 from public.grands_prix
     where date_course = timestamptz '2026-11-01 21:00:00+00'
        or date_qualifications = timestamptz '2026-10-31 23:00:00+00'
  ) then
    raise exception 'GP du Mexique : un horaire faux subsiste';
  end if;
end
$$;
