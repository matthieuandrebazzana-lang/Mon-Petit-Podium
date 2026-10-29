-- =============================================================================
--  Migration 34 — Week-end du GP du Brésil 2026
-- =============================================================================
--
-- Symptôme : week-end affiché du 13 au 15 novembre, EL1 à 11h30 locale.
-- Réalité : le GP se court du 6 au 8 novembre, EL1 à 12h30 locale.
--
-- Le Brésil n'a plus d'heure d'été depuis 2019 : São Paulo est à UTC−3 toute
-- l'année, et OpenF1 sert `gmt_offset = -03:00` pour ce week-end. Comme pour le
-- Mexique (migration 33), la conversion était juste ; c'est la DATE du week-end
-- qui était fausse, et l'heure de départ posée par la 19 :
--
--   | Séance          | Posée par    | Instant posé                 | Officiel                     |
--   |-----------------|--------------|------------------------------|------------------------------|
--   | Qualifications  | migration 20 | sam. 14 nov. 15h00 = 18:00Z  | sam. 7 nov. 15h00 = 18:00Z   |
--   | Course          | migration 19 | dim. 15 nov. 15h00 = 18:00Z  | dim. 8 nov. 14h00 = 17:00Z   |
--
-- Les essais libres ne sont pas en base : ils ne vivent que dans `GP_2026`
-- (web) et `FichesGrandPrix` (iOS), corrigées dans le même commit.
--
-- Sources : OpenF1 `/v1/sessions?meeting_key=1299` (sessions 11408 et 11412,
-- vérifiées le 2026-10-29), calendrier officiel formula1.com.
--
-- **Le scraper ne réécrira pas l'erreur.** Il n'écrit `date_qualifications` que
-- si Unibet publie un événement de qualification (`resoudre_qualifications`) ;
-- sinon la clé est absente de l'upsert et la valeur d'ici survit. Il écrit
-- `date_course` depuis l'heure de départ d'Unibet : une heure relevée chez le
-- bookmaker, jamais la date de la 19.
--
-- **Gravité** : `pronostics_fermes` ferme à `date_course`. Au 15 novembre, les
-- pronostics seraient restés ouverts une semaine après l'arrivée, et le gel des
-- cotes comme le job de résultats seraient partis une semaine trop tard.
--
-- Garde : seule la ligne du Brésil portant EXACTEMENT l'instant faux est
-- touchée — chaque colonne indépendamment, car le scraper a pu corriger
-- `date_course` sans toucher aux qualifications. Une heure qu'Unibet aurait
-- déjà écrite n'est jamais remplacée. Idempotente : rejouée, elle ne trouve
-- plus rien à corriger. Aucun autre Grand Prix n'est touché.
-- =============================================================================

update public.grands_prix
   set date_qualifications = timestamptz '2026-11-07 18:00:00+00'
 where date_qualifications = timestamptz '2026-11-14 18:00:00+00'
   and (id_unibet = 'manuel-bresil-2026'
        or public.slug_gp(nom) in ('bresil', 'sao-paulo'));

update public.grands_prix
   set date_course = timestamptz '2026-11-08 17:00:00+00'
 where date_course = timestamptz '2026-11-15 18:00:00+00'
   and (id_unibet = 'manuel-bresil-2026'
        or public.slug_gp(nom) in ('bresil', 'sao-paulo'));

do $$
begin
  if exists (
    select 1 from public.grands_prix
     where (id_unibet = 'manuel-bresil-2026'
            or public.slug_gp(nom) in ('bresil', 'sao-paulo'))
       and (date_course = timestamptz '2026-11-15 18:00:00+00'
            or date_qualifications = timestamptz '2026-11-14 18:00:00+00')
  ) then
    raise exception 'GP du Brésil : un horaire faux subsiste';
  end if;
end
$$;
