# Base de données

Schéma PostgreSQL (Supabase), politiques RLS, fonctions et migrations.

> **Les migrations s'appliquent À LA MAIN dans le SQL Editor de Supabase**, dans
> l'ordre, une par une. Aucune CI ne les joue. Toutes sont idempotentes : les rejouer
> ne casse rien — mais **l'ordre compte**, voir §6.

---

## 1. Les neuf tables

```
auth.users
    │ 1─1 (cascade)
    ▼
public.profils ──────────┐
    │                    │
    │ (cree_par, SET NULL)
    ▼                    │
public.championnats      │
    │ 1─N (cascade)      │
    ▼                    │
public.membres_championnat ◄─┘

public.grands_prix
    │ 1─N (cascade)          1─1 (cascade, unique)
    ├──► public.cotes        └──► public.resultats_gp
    ├──► public.favoris
    └──► public.pronostics ──1─1(cascade)──► public.pronostic_podium
```

### `public.profils`

| Colonne | Type | Note |
|---|---|---|
| `id` | uuid PK | → `auth.users`, cascade |
| `pseudo` | text | **index unique sur `lower(pseudo)`** |
| `cree_le`, `modifie_le` | timestamptz | `modifie_le` par trigger |
| `couleur1` | text, défaut `#800111` | coque de la voiture |
| `couleur2` | text, défaut `#FFFFFF` | ailerons |
| `numero` | integer, **nullable** | 1 à 99 |
| `livree_mode` | text, défaut `perso` | `perso` \| `ecurie` |
| `livree_ecurie` | text, nullable | slug (`^[a-z0-9-]{2,32}$`) |
| `is_admin` | boolean, **not null** défaut `false` | affichage seul, voir §5 |
| `avatar_url` | text, **nullable** | URL publique Storage, jamais de base64 |
| `couleur_texte` | text, **nullable**, défaut `#FFFFFF` | numéro et pseudo peints sur la voiture |

Contraintes : `pseudo` 2–20 caractères ; `numero` entre 1 et 99 ; couleurs au format
`#RRGGBB` ; **couleurs distinctes à la casse près** ; `livree_ecurie` obligatoire si
`livree_mode = 'ecurie'` ; `couleur_texte` au format `#RRGGBB` ou `NULL`.

> ### `couleur_texte` a un défaut, et les lignes existantes valent quand même `NULL`
>
> Ce n'est pas une incohérence, c'est le point de la migration 18. **`NULL` ne veut pas
> dire « pas de couleur » mais « pas de choix »** : le frontend calcule alors l'encre qui
> contraste avec l'aplat sous le texte (`encreSur`), ce qu'il a toujours fait. Un
> `#FFFFFF` posé rétroactivement aurait rendu le numéro invisible sur les quatre teintes
> claires de la palette — blanc, argent, beige, jaune.
>
> D'où **deux instructions séparées** : `add column` sans `default` (PostgreSQL ne remplit
> alors rien), puis `alter column … set default`, qui ne vaut que pour les lignes à venir.
> Écrites en une seule, les deux effets seraient venus ensemble.
>
> `couleur_texte` **n'entre pas** dans la contrainte « deux couleurs distinctes » : celle-ci
> empêche une voiture monochrome, or le texte est posé SUR la carrosserie. Un numéro blanc
> sur une coque blanche est un défaut de contraste, mesuré et signalé par l'écran de
> profil, pas une voiture sans forme.

> **L'unicité du pseudo est un index sur `lower(pseudo)`, pas un `unique` nu.** Un UNIQUE
> ordinaire laisserait coexister « MaxV33 » et « maxv33 », que tout le monde lirait comme
> la même personne. **L'extension `citext` ferait le même travail** au prix d'une extension
> à gérer ; un index fonctionnel l'évite.

> **`numero` n'a AUCUNE contrainte d'unicité, et c'est délibéré.** Une voiture étant
> identique dans tous les championnats de son propriétaire, un numéro unique globalement
> voudrait dire **99 comptes maximum sur toute l'application**. L'unicité est indicative,
> jugée à l'affichage : le frontend avertit, il ne bloque jamais.

> **Deux colonnes de livrée plutôt qu'une nullable** : un membre qui essaie une livrée
> puis revient à ses couleurs garde son dernier choix d'écurie et le retrouve s'il
> rebascule.

> **`livree_ecurie` est contrainte par son FORMAT, jamais par une liste des onze écuries.**
> Une énumération en base figerait la grille — les onze voitures sont un actif du
> frontend qui se relit chaque saison.

> **`avatar_url` ne porte QUE l'URL** (migration 16). Une image de 2 Mo en base64 pèserait
> 2,7 Mo dans une colonne `text`, serait relue à chaque classement et traverserait le
> réseau à chaque affichage. La contrainte `profils_avatar_url_format` ne vérifie que la
> **forme** (`https://`, ≤ 512 caractères) : y coder l'URL du projet Supabase figerait la
> base sur un projet, et une restauration ailleurs refuserait toutes les photos
> existantes. **Le rattachement au projet se juge côté backend**, dans
> `app/api/stockage.py`, seul endroit qui connaisse `SUPABASE_URL` — voir §9.

### `public.championnats`

| Colonne | Type | Note |
|---|---|---|
| `id` | uuid PK | |
| `nom` | text | 2–40 caractères |
| `code_invitation` | text **unique** | `^[A-Z0-9]{6}$` |
| `cree_par` | uuid **nullable** | → `auth.users`, **`on delete set null`** |
| `cree_le` | timestamptz | |
| `photo_url` | text, **nullable** | URL publique Storage, mêmes règles qu'`avatar_url` |

> **`cree_par` est nullable et ne cascade pas.** Supprimer le compte du créateur ne doit
> pas emporter le championnat de tous les autres membres : il survit, sans créateur.
> **Conséquence assumée** : sur un championnat orphelin, la politique « Seul le createur
> supprime » ne vaut jamais vrai, donc plus personne ne peut le supprimer depuis le
> frontend. Il disparaîtra de lui-même au départ du dernier membre (§4).

### `public.membres_championnat`

PK `(championnat_id, profil_id)`, cascade sur les deux références, `rejoint_le`
(4ᵉ critère de départage). Index supplémentaire sur `profil_id` : la PK couvre les
recherches par championnat, mais « mes championnats » part du profil et balaierait
toute la table sans lui.

### `public.grands_prix`

| Colonne | Type | Note |
|---|---|---|
| `id_unibet` | text **unique** | **clé de rapprochement du scraper** |
| `nom` | text | orthographe changeante — jamais une clé |
| `date_course` | timestamptz, nullable | **en UTC** |
| `date_qualifications` | timestamptz, nullable | migration 11 — **écrite, jamais dérivée** (migration 20) |
| `statut` | text | `a_venir` \| `cotes_figees` \| `termine` |
| `statut_resultats` | text, nullable | migration 25 — `NULL` \| `provisoire` \| `definitif` |

> ### `statut_resultats` — provisoire, puis définitif à J+1 (migration 25, v`0.78.0`)
>
> | Valeur | Posée par | Sens |
> |---|---|---|
> | `NULL` | défaut | pas encore de résultats |
> | `provisoire` | le job, au premier calcul (`attribuer_points`) | points comptés, classement de l'arrivée |
> | `definitif` | `remplacer_verdicts`, 24 h après `date_course`, ou recalcul admin | OpenF1 relue, tous les verdicts réécrits |
>
> Contrainte `grands_prix_statut_resultats_valide`. La migration a marqué Pays-Bas,
> Italie et Espagne `definitif`, Azerbaïdjan `provisoire` (seulement s'il n'avait encore
> aucun statut : la rejouer ne rouvre pas un GP définitif). Règle métier : `metier.md` §4.

> **Le rapprochement se fait sur `id_unibet`, JAMAIS sur le nom.** Unibet écrit
> « GP Pays Bas » cette semaine et « GP Pays-Bas » la suivante.

> **`statut` est une contrainte `check`, pas un type `enum`.** Ajouter une valeur à un
> enum PostgreSQL est une migration à part entière.

> **`date_qualifications` est nullable, et pas seulement par prudence.** Unibet publie
> parfois un GP avant d'en annoncer le programme ; un `not null` obligerait le scraper à
> inventer une date ou à ne pas écrire la ligne — donc à faire disparaître le GP de
> l'accueil et du calendrier.

> ### Depuis la migration 19, la table n'est plus alimentée par le seul scraper
>
> Les onze Grands Prix restants de 2026 y ont été posés à la main. Ils portent un
> `id_unibet` **inventé**, de la forme `manuel-<slug>-2026`, parce que l'identifiant réel
> n'existe pas tant qu'Unibet n'a pas ouvert la page du Grand Prix.
>
> **L'adoption est automatique depuis le backend `0.61.0`** : avant d'écrire, le scraper
> cherche une ligne au `id_unibet` en `manuel-` portant le **même nom** (slug insensible à
> la casse et aux accents) et lui fait porter le vrai identifiant, **sans toucher à son
> UUID** — cotes, pronostics et favoris restent attachés. Voir `scraper.md` §6.
>
> Sans ce mécanisme, le scraper ne reconnaissait pas la ligne (il se rapproche sur
> `id_unibet`, et sur rien d'autre) : il en insérait une **seconde**, et la base portait
> deux fois la même course. Le symptôme était discret — `enrichir` rapproche par slug et
> construit une `Map`, donc la dernière ligne servie l'emporte : le calendrier pouvait
> s'accrocher à celle qui n'a **pas** les cotes. Voir `bugs-connus.md` §31.
>
> `adopter_grand_prix` reste la voie des deux cas que l'automatique refuse — **deux lignes
> manuelles homonymes**, et **le doublon déjà constitué**. Elle renomme le placeholder s'il
> est seul, et résorbe le doublon si le scraper est arrivé le premier — **en refusant de
> supprimer une ligne à laquelle quoi que ce soit pend**, `on delete cascade` emportant
> sinon des cotes ou des pronostics sans bruit.
>
> **Les heures de COURSE posées par la 19 sont prévisionnelles** (15h00 locale, heure
> habituelle pour les courses de nuit, converties au fuseau réel du circuit). Le scraper
> les remplace au premier passage. Conséquence à connaître : une carte du calendrier peut
> passer à « Fermé » sur la foi d'une heure devinée, là où un GP absent de la base restait
> « à venir » (`calendrier.md` §6).

> ### Les heures de QUALIFICATIONS ne se dérivent plus (migration 20, backend `0.57.0`)
>
> La 19 les posait à `date_course − 22h` — l'ancien repli du scraper. **22 h est une
> constante, l'écart réel n'en est pas une** : 23 h sur huit week-ends de 2026, 22 h sur
> deux (Austin, Mexique), 24 h au Brésil, **26 h à Las Vegas** dont les qualifications se
> courent le vendredi soir. Neuf lignes sur onze portaient une heure fausse.
>
> Et le scraper la **réécrivait** à chaque passage, faute d'événement de qualification chez
> Unibet — c'est le régime normal, pas l'exception (`scraper.md` §5). Comme `seancesDuGp`
> préfère l'heure de la base à celle de `GP_2026`, la fiche du GP d'Italie annonçait des
> qualifications à **17h00** pour une heure réelle de **16h00** : une heure devinée
> chassait une heure relevée, et corriger la table statique seule n'y aurait rien changé.
>
> **Le repli est retiré du scraper.** Quand Unibet se tait, la clé n'est pas écrite dans
> l'upsert et la valeur de la 20 survit. `date_qualifications` reste nullable pour la
> raison ci-dessus, mais **une ligne neuve dont Unibet ne publie pas le programme n'a plus
> d'horaire du tout** — donc pas de figeage automatique. C'est l'écart signalé de
> `scraper.md` §5. Il ne touche plus les onze lignes de la 19, que l'adoption automatique
> fait maintenant reconnaître au scraper avec l'heure que la 20 leur a posée.

### `public.cotes`

`id`, `gp_id` (cascade), `marche` (slug), `libelle_marche` (libellé du bookmaker),
`pilote`, `valeur` (**integer > 0**), `id_outcome_unibet` (**not null**), `cree_le`.

> **`valeur` est déjà le nombre de points** — cote × 10 arrondie. **Rien en base ne
> stocke « 2,80 »** (voir `metier.md` §1).

> **`id_outcome_unibet` est `not null`, et c'est ce qui fait tenir l'idempotence.** Sous
> PostgreSQL, deux `NULL` sont distincts : un index unique sur une colonne nullable
> n'empêcherait plus rien. Une issue sans identifiant est **ignorée** plutôt qu'insérée.

Index : `cotes_gp_outcome_idx` **unique** sur `(gp_id, id_outcome_unibet)` — il porte
seul l'idempotence du scraper ; `cotes_gp_marche_idx` sur `(gp_id, marche)`.

> **`libelle_marche` est un ajout assumé.** Sans lui, l'interface reconstituerait un nom
> depuis le slug et afficherait « Ecurie vainqueur » au mieux, « Top x » au pire. Le
> bookmaker est la seule source légitime du nom d'un marché.

### `public.favoris`

PK `(profil_id, gp_id, id_outcome_unibet)`, cascade, `cree_le`.

> **Aucune clé étrangère vers `public.cotes`, et c'est délibéré.** Le scraper réécrit les
> cotes tant qu'elles ne sont pas figées ; une issue qu'Unibet retire ferait échouer son
> upsert, ou emporterait les favoris des joueurs par cascade. Le rapprochement se fait à
> la lecture — **un favori orphelin est servi sans points plutôt qu'effacé.**

### `public.pronostics`

`id`, `profil_id`, `gp_id`, `id_outcome_unibet`, `type` (`vainqueur`|`podium`|`bonus`),
`points_gagnes` (integer **nullable**, `>= 0`), `statut_evaluation` (migration 24),
`cree_le`, `modifie_le`.

**Trois index PARTIELS, pas un index unique sur `(profil_id, gp_id, type)`** — celui-ci
interdirait aussi d'avoir plus d'un bonus, alors que la règle en demande trois :

| Index | Portée |
|---|---|
| `pronostics_un_vainqueur_idx` | `where type = 'vainqueur'` |
| `pronostics_un_podium_idx` | `where type = 'podium'` |
| `pronostics_bonus_distincts_idx` | `(profil_id, gp_id, id_outcome_unibet) where type = 'bonus'` |

Le maximum de trois bonus **ne peut pas** s'écrire en `check` (la contrainte porte sur
plusieurs lignes) : c'est le trigger `pronostics_max_trois_bonus`.

> ### `points_gagnes` — trois états, et `NULL` ≠ `0`
>
> | Valeur | Sens |
> |---|---|
> | `NULL` | résultat inconnu, **ou marché que le calcul n'a pas su valider** |
> | `0` | pronostic raté |
> | `> 0` | pronostic réussi |
>
> **C'est la convention la plus structurante du projet, et elle est tenue partout.**
> Marquer « raté » un pronostic qu'on n'a pas su valider volerait le joueur en silence.
> `NULL` se voit dans les logs, s'affiche « en attente », et se rattrape par un second
> passage.

> ### `statut_evaluation` — ce que `NULL` ne disait pas (migration 24, v`0.77.0`)
>
> | Statut | `points_gagnes` | Posé par |
> |---|---|---|
> | `en_attente` (défaut) | `NULL` | défaut ; `attribuer_points` quand une donnée manque |
> | `non_evaluable` | `NULL` | `attribuer_points`, quand aucun évaluateur ne porte le marché |
> | `gagne` | `> 0` | **trigger** `pronostics_statut_derive` |
> | `perdu` | `0` | **trigger** `pronostics_statut_derive` |
>
> **`gagne` et `perdu` ne s'écrivent jamais, ils se dérivent** de `points_gagnes`, avant
> chaque insertion ou mise à jour. Des points remis à `NULL` (`?forcer=true`, migration 15
> rejouée) ramènent donc le statut à `en_attente` sans que le code appelant le sache. La
> contrainte `pronostics_statut_evaluation_coherent` refuse toute autre combinaison.
>
> **Servi aux écrans depuis la migration 25** : `pronostics_du_joueur` porte
> `statut_evaluation`, et `pronostics_du_championnat`, qui l'appelle pour chaque membre,
> en hérite **sans être remplacée** (aucun conflit avec la 18). Les lectures directes du
> web (`lib/profils.js`, `lib/pronostics.js`) sélectionnent la colonne elles-mêmes. Un
> `non_evaluable` s'affiche « Non évaluable », plus « en attente ».

### `public.pronostic_podium`

`pronostic_id` (PK, cascade), `pilote_1`, `pilote_2`, `points_gagnes`.
`check (pilote_1 <> pilote_2)`.

> **Aucun ordre entre les deux pilotes.** La validation demande « ces deux pilotes
> sont-ils sur le podium ? », jamais « lequel devant ». `pilote_1` et `pilote_2` ne sont
> que des emplacements — d'où le paiement à la **somme** des deux cotes (`metier.md` §2).

La redondance avec `pronostics.id_outcome_unibet` (qui porte `pilote_1`) est tenue par
**deux triggers, pas par une convention** : `pronostic_podium_coherent` refuse un détail
dont `pilote_1` diverge du parent, et `attribuer_points` dérive systématiquement
`points_gagnes` de la colonne parente. **Ne jamais l'écrire depuis le code applicatif.**

### `public.resultats_gp`

`id`, `gp_id` (**unique**, cascade), `recupere_le`, `donnees_brutes` (jsonb).

> **`donnees_brutes` n'est pas un cache de confort** : c'est ce qui permet de **rejouer
> le calcul sans rappeler OpenF1**, donc de corriger un validateur ou d'en ajouter un
> pour un marché resté à `NULL`, des semaines après la course.

Objet `{ session, session_result, drivers, race_control, laps, starting_grid, qualification,
pilotes }`. **`laps` est réduit au meilleur tour par pilote** — la réponse complète pèse
654 Ko par GP. **`qualification`** (v`0.77.0`) est le `session_result` des qualifications du
week-end, qui donne la pole : c'est **la seule clé que le job ajoute après coup** à une
ligne existante, quand elle manque (`scraper.md` §10).

**Depuis la migration 25, la ligne est remplacée une fois** : au calcul définitif, 24 h
après la course, par une relecture complète d'OpenF1 (`remplacer_verdicts`). Un recalcul
admin la remplace de nouveau seulement s'il est demandé avec `relire=true`.

---

## 2. RLS — le piège de la récursion, et sa sortie

**Toutes les tables ont la RLS activée.**

> ### `42P17` — la règle à ne jamais défaire
>
> Les politiques de lecture se formulent « il existe une ligne dans
> `membres_championnat` avec ce `championnat_id` et `profil_id = auth.uid()` ». Écrite
> telle quelle dans une politique **de** `membres_championnat`, la condition interroge la
> table que la politique protège : PostgreSQL détecte la récursion et **refuse la
> requête** (`42P17`). La politique de `championnats` tombe dans le même piège.
>
> **`public.est_membre(uuid)`, en `security definer`, casse la boucle** en lisant sans
> repasser par les politiques. La sémantique est exactement celle voulue ; seule
> l'écriture change. **Ne jamais réinsérer la sous-requête littérale dans ces politiques.**

| Table | Lecture | Écriture |
|---|---|---|
| `profils` | soi-même **ou** un membre d'un championnat partagé | son propre profil, **huit colonnes nommées** |
| `championnats` | ses membres (`est_membre`) | créateur seul modifie/supprime, **création hors RLS** |
| `membres_championnat` | entre membres | départ pour soi-même, **adhésion hors RLS** |
| `grands_prix`, `resultats_gp` | **tous, `anon` compris** | **aucune politique** |
| `cotes` | tout compte **connecté** | **aucune politique** |
| `favoris` | **strictement privés** | soi-même |
| `pronostics` | les siens, **ou** ceux d'un membre d'un championnat partagé **une fois la saisie fermée** | soi-même |
| `pronostic_podium` | via l'existence du pronostic parent | son auteur |
| `storage.objects` (2 compartiments) | **tous, `anon` compris** | le propriétaire du dossier (§9) |

> **Lecture publique des GP et des résultats** : ils sont affichés tels quels chez le
> bookmaker, et la landing doit pouvoir annoncer le prochain GP sans session — l'écran
> public de résultats en dépend de même. **Les cotes en ont été retirées** par la
> migration 21 : les trois écrans qui les lisent sont tous derrière `RouteProtegee`, et la
> grille des points d'un Grand Prix est du contenu de jeu. **Aucune politique d'écriture
> n'est créée** — sous RLS, ce qu'aucune politique n'autorise est refusé. Aucun droit
> d'écriture n'est accordé à `anon` ni `authenticated` non plus : double verrou.

> ### Ce que la RLS garde vraiment, et ce qu'elle ne garde pas
>
> **Toutes les écritures de l'application passent par FastAPI avec la clé de service**,
> qui contourne la RLS (`CLAUDE.md` §3.4) : le frontend n'appelle ni `.insert()`, ni
> `.update()`, ni `.upsert()`, ni `.delete()`. Les politiques d'écriture restantes sont
> donc du **second verrou**, jamais un chemin emprunté — et les politiques de LECTURE, à
> l'inverse, sont la seule chose qui sépare deux joueurs sur les quelques lectures que le
> frontend fait en direct.
>
> **Conséquence à ne jamais perdre de vue** : un audit RLS mesure ce qu'un porteur de la
> clé publique peut faire **en dehors** de l'app, avec un client Supabase à lui. Il ne
> mesure pas ce que l'app montre — cela, ce sont les routes et les fonctions
> `security definer` qui le décident.

> ### Deux politiques `select` sur une même table se combinent par OU
>
> C'est la mécanique qui rend les conflits d'ordre de la 21 silencieux (§6). Une politique
> permissive recréée **à côté** de la politique resserrée ne la remplace pas : elle la
> désarme. D'où la forme de chaque étape de la 21 — `drop policy if exists` sur
> **l'ancien nom** avant de créer le nouveau — et le bloc de contrôle final, qui lève si
> une seconde politique de lecture subsiste sur `public.profils`.

> ### La fenêtre de fermeture des pronostics vit dans la politique, pas dans l'app
>
> Depuis la migration 21, la politique de lecture de `public.pronostics` ajoute
> `public.pronostics_fermes(gp_id)` à la branche « co-membre » : sous RLS, on ne lit le
> pronostic d'un autre qu'**après** la fermeture de la saisie. `pronostic_podium` suit
> seule, sa politique ne testant que l'existence du parent.
>
> **Cela ne rend PAS les pronostics privés dans l'app**, et c'est un écart signalé : le
> tableau des résultats est servi par `pronostics_du_championnat`, `security definer`
> réservée à `service_role`, dont l'autorisation est portée par la route. La règle métier
> « visibles dès leur saisie » (`metier.md`, samedi soir → dimanche) reste donc en vigueur
> côté écran. Refermer vraiment demanderait de toucher à cette fonction et à sa route.

> **Les favoris sont privés parce que ce sont des brouillons.** Les laisser lire
> reviendrait à annoncer ses pronostics avant de les avoir saisis.

> **`pronostic_podium` NE REDIT PAS la condition** : sa politique ne teste que
> l'existence du parent, dont la sous-requête est elle-même filtrée. Écrire la règle
> deux fois créerait deux textes à maintenir en parallèle.

---

## 3. Les fonctions

### Réservées à `service_role` (révoquées pour `public`, `anon`, `authenticated`)

| Fonction | Rôle |
|---|---|
| `creer_championnat(nom, code, createur)` | championnat **+** son créateur, une transaction |
| `mes_championnats(profil)` | championnats + effectif + photo, une requête |
| `quitter_championnat(profil, championnat)` | retrait **+** effacement conditionnel, atomiques |
| `enregistrer_pronostics(...)` | efface le jeu précédent et écrit le nouveau, une transaction |
| `pronostics_du_joueur(profil, gp)` | pronostics rapprochés des cotes (`left join`) |
| `pronostics_du_championnat(championnat, gp)` | tous les membres, voiture et total |
| `attribuer_points(gp, jsonb)` | **la fonction la plus sensible du projet** — calcul provisoire |
| `remplacer_verdicts(gp, jsonb, donnees, statut)` | calcul définitif et recalcul admin : **remplace** résultats et verdicts, une transaction (migration 25) |
| `classement_du_championnat(championnat)` | classement trié et rangé, avatars compris |
| `stats_du_profil(profil, saison)` | les quatre chiffres de la grille 2×2 |
| `calendrier_du_championnat(championnat, profil, saison)` | une ligne par GP |
| `classement_du_grand_prix(gp)` | classement de la course |
| `slug_gp(nom)` | `immutable` — empreinte stable d'un nom de GP (migration 19) |
| `adopter_grand_prix(placeholder, id_unibet)` | fait porter son vrai identifiant à une ligne posée à la main |

> **Pourquoi `security definer` + `service_role` sur les fonctions de lecture agrégée.**
> Paramétrées par un championnat ou un profil, elles lisent forcément les pronostics
> d'autrui. Sous l'identité de l'appelant, la politique RLS filtrerait les membres avec
> qui il ne partage rien — exactement ce qu'il faut protéger, mais qui rendrait un
> classement **silencieusement amputé** au lieu d'un refus franc. **L'autorisation est
> donc portée par la route, qui vérifie l'appartenance AVANT l'appel.**

> **`creer_championnat` est atomique pour une raison précise** : deux appels REST séparés
> laisseraient, en cas d'échec du second, un championnat sans aucun membre — invisible de
> tous, y compris de son créateur, et impossible à rejoindre.

> **`attribuer_points` n'écrit QUE les pronostics dont `points_gagnes` est encore `NULL`.**
> C'est la base qui porte l'idempotence, pas le code appelant : appelée dix fois avec des
> valeurs différentes, elle n'attribue rien deux fois. Depuis la migration 24, une entrée
> sans points porte un `statut` (`en_attente` ou `non_evaluable`), posé lui aussi sur un
> pronostic encore à `NULL` seulement ; elle rend `attribues`, `restants` (`en_attente`) et
> `non_evaluables`. Ouverte à `authenticated`, elle
> laisserait n'importe qui s'attribuer le score de son choix.

> **`remplacer_verdicts` fait l'inverse, et c'est son rôle** (migration 25). Elle reçoit
> le verdict de chaque pronostic du GP et, **dans la transaction de l'appel** : remplace
> `resultats_gp` si `p_donnees` est fourni, réécrit `points_gagnes` et
> `statut_evaluation` de **tous** les pronostics du GP (un pronostic absent de la liste
> repart `en_attente`), resynchronise `pronostic_podium`, puis pose `statut = 'termine'`
> et `statut_resultats`. Un échec n'écrit rien : jamais de GP « tout en attente » entre
> deux appels, le défaut de l'ancien `?forcer=true`. Réservée à `service_role`. Rend
> `modifies`, `attribues`, `restants`, `non_evaluables`.

> **`slug_gp` ne remplace JAMAIS `id_unibet` comme clé de rapprochement.** Elle sert à
> reconnaître un Grand Prix **déjà présent** malgré une orthographe changeante — c'est le
> garde-fou d'idempotence de la migration 19, et rien d'autre. Le scraper, lui, continue
> de se rapprocher sur `id_unibet` seul : un slug est une empreinte, pas une identité, et
> deux Grands Prix pourraient un jour la partager.

### Ouvertes

| Fonction | Portée |
|---|---|
| `est_membre(uuid)` | `security definer` — casse la récursion RLS |
| `pseudo_disponible(text)` | **appelable sans être connecté** |
| `cotes_du_grand_prix(uuid)` | `security invoker` — lit sous les politiques publiques |
| `pronostics_fermes(uuid)` | `security invoker`, `authenticated` |
| `livree_par_indice(integer)` | `immutable`, les dix livrées initiales |
| `nom_de_photo_valide(text)` | `immutable` — **la seule que `authenticated` doive exécuter** (migration 22) |

> **`nom_de_photo_valide` est la seule fonction ouverte à `authenticated`, et c'est
> structurel.** Toutes les autres sont révoquées pour lui. Celle-ci est appelée depuis une
> expression de politique RLS sur `storage.objects`, et une politique est évaluée **avec les
> droits de l'appelant** : un `revoke` pour `authenticated` ferait échouer tout dépôt de
> photo en `42501` au lieu de le filtrer. Elle ne lit aucune table et ne rend qu'un booléen.

> **`pseudo_disponible` révèle qu'un pseudo est pris, sans dire par qui.** C'est le
> compromis normal d'un champ de pseudo, ceux-ci étant de toute façon affichés dans les
> classements. **À ne jamais transposer aux emails.** Si l'appel échoue, la réponse est
> « disponible » et l'inscription continue — la garantie reste l'index en base.

### Triggers

| Trigger | Sur | Rôle |
|---|---|---|
| `on_auth_user_created` | `auth.users` | crée le profil **et sa livrée initiale** |
| `profils_modifie_le`, `pronostics_modifie_le` | | horodatage |
| `membres_championnat_supprime_vide` | `membres_championnat` | supprime un championnat vidé |
| `pronostics_max_trois_bonus` | `pronostics` | maximum de 3 bonus |
| `pronostic_podium_coherent` | `pronostic_podium` | invariant `pilote_1` = parent |

> **`gerer_nouvel_utilisateur` a deux comportements distincts, délibérément :**
> un **pseudo choisi explicitement** n'est jamais remplacé en douce — s'il est pris,
> l'inscription entière échoue (renommer discrètement quelqu'un serait pire qu'un refus) ;
> **aucun pseudo transmis** (Google, Apple) → `pilote-xxxxxxxxxx` fabriqué avec
> incrémentation. Une inscription OAuth ne doit jamais échouer pour cette raison.
>
> Le message « Ce pseudo est déjà pris » repose sur le fait que **ce trigger est le seul
> posé sur `auth.users`** — en ajouter un autre obligera à revoir la traduction dans
> `lib/erreurs.js`.

> **`membres_championnat_supprime_vide` — quatre points à ne pas défaire :**
> `security definer` (le dernier membre n'est pas toujours le créateur, la politique
> l'empêcherait d'effacer la ligne) ; **`after`, jamais `before`** (un `before` compterait
> les membres avant le retrait, le dernier départ trouverait toujours quelqu'un) ;
> `for each row` (une suppression peut porter sur plusieurs championnats) ; **aucun garde
> `pg_trigger_depth()`** — la récursion s'arrête d'elle-même.

---

## 4. Conventions de nommage

- **Tout en français, en minuscules, avec des underscores.**
- Tables au pluriel (`profils`, `cotes`), sauf `pronostic_podium` — une ligne de détail
  pour un pronostic, jamais une collection.
- Clés étrangères : `<table_au_singulier>_id` (`gp_id`, `profil_id`, `championnat_id`).
- Horodatages : `cree_le`, `modifie_le`, `rejoint_le`, `recupere_le`.
- Fonctions : verbe à l'infinitif pour une action (`creer_championnat`,
  `attribuer_points`), nom de ce qui est rendu pour une lecture (`mes_championnats`,
  `classement_du_championnat`).
- Index : `<table>_<colonnes>_idx`, suffixé du critère pour un index partiel
  (`pronostics_a_calculer_idx`).
- Contraintes : `<table>_<ce_qu_elle_garantit>` (`profils_couleurs_distinctes`).

---

## 5. `is_admin` décide d'un affichage, jamais d'un droit

Trois raisons le rendent **structurellement incapable** de garder quoi que ce soit :

1. `POST /scraper/declencher` ne le connaît pas — elle est fermée par `X-Admin-Secret`.
2. **Le secret voyage en clair dans le bundle** (`architecture.md` §5).
3. **La politique « Chacun modifie son profil » porte sur la LIGNE, pas sur la colonne** :
   un membre pouvait écrire son propre `is_admin` via un client Supabase. Sans conséquence —
   il aurait vu deux boutons, et rien de plus, tant qu'il n'a pas le secret.

Le premier administrateur se désigne **à la main** — un `update` qui promouvrait
« le plus ancien compte » se tromperait de personne après une restauration :

```sql
update public.profils set is_admin = true where pseudo = '<ton pseudo>';
```

> ### La troisième raison a été refermée par la migration 21 — par le DROIT, pas par la RLS
>
> La RLS de PostgreSQL ne sait pas filtrer par colonne. Le **droit de colonne**, lui, le
> sait, et il est antérieur à toute politique. Un droit `update` de TABLE valant pour
> toutes les colonnes — **y compris celles ajoutées ensuite** —, le resserrer demande de
> le retirer puis de le redonner colonne par colonne :
>
> ```sql
> revoke insert, update, delete on public.profils from anon, authenticated;
> grant update (pseudo, couleur1, couleur2, numero,
>               livree_mode, livree_ecurie, avatar_url, couleur_texte)
>   on public.profils to authenticated;
> ```
>
> Ce sont exactement les huit champs que `PATCH /profils/moi` accepte. `id`, `cree_le`,
> `modifie_le` et `is_admin` en sont exclues. **`modifie_le` reste écrite par son
> trigger** : un droit de colonne porte sur les colonnes NOMMÉES par l'ordre `update`,
> jamais sur ce qu'un trigger pose dans `NEW`.
>
> **Piège à connaître : toute colonne ajoutée à `profils` après la 21 naîtra
> non-modifiable depuis un client.** C'est sans effet sur l'app — elle écrit avec la clé
> de service — mais une migration qui ajoute un champ de voiture devra penser à son
> `grant update (…)`.

> ### Ce que la 21 n'a PAS refermé : `is_admin` reste LISIBLE par les co-membres
>
> La lecture des profils est désormais bornée à soi-même et aux membres d'un championnat
> partagé (§2), donc un inconnu ne voit plus rien. Mais un co-membre lit toujours la
> colonne. La fermer demanderait `revoke select (is_admin)`, qui fermerait du même coup la
> lecture de **sa propre** ligne — donc `lib/profils.js chargerEstAdmin`, donc la section
> Administration. Le correctif complet est une ligne de SQL et une ligne de frontend :
> exposer son propre drapeau par une fonction `security definer` sans paramètre.

Le jour où `is_admin` doit vraiment garder quelque chose : une route backend qui exige le
**jeton** du membre — **pas un contrôle applicatif de plus**.

---

## 6. Les vingt-cinq migrations

| # | Fichier | Ce qu'elle fait | Dépend de |
|---|---|---|---|
| 1 | `20260809191018_profils_pseudo_unique` | `profils`, unicité, trigger d'inscription | — |
| 2 | `20260810163435_championnats` | `championnats`, `membres_championnat`, `est_membre` | — |
| 3 | `20260813174500_grands_prix_cotes` | `grands_prix`, `cotes` | — |
| 4 | `20260813182331_createur_nullable_championnat_vide` | `cree_par` nullable, trigger de suppression | 2 |
| 5 | `20260813183636_favoris_pronostics` | `favoris`, `pronostics`, `pronostic_podium` | 2, 3, 4 |
| 6 | `20260813205200_resultats_points` | `points_gagnes`, `resultats_gp`, `attribuer_points` | 3, 5 |
| 7 | `20260814103000_classement_championnat` | `classement_du_championnat` | 2, 5, 6 |
| 8 | `20260814162200_profil_voiture_stats` | voiture sur `profils`, `stats_du_profil` | 1, 5, 6, 7 |
| 9 | `20260814183000_livree_automatique` | livrée initiale à l'inscription | 1, 8 |
| 10 | `20260814213000_calendrier_championnat` | `calendrier_du_championnat` | 3, 5, 6, 8 |
| 11 | `20260816120000_date_qualifications` | `date_qualifications` | 3 |
| 12 | `20260819124500_livree_ecurie` | `livree_mode`, `livree_ecurie` | 1, 8, 10 |
| 13 | `20260820120000_calendrier_date_qualifications` | ajoute le champ au calendrier | 10, 11 |
| 14 | `20260820150000_profil_is_admin` | `is_admin` | 1 |
| 15 | `20260821143000_points_diviseur_10` | remise à zéro des points (diviseur 10) | 3, 5, 6 |
| 16 | `20260821180000_photos_profil_championnat` | `avatar_url`, `photo_url`, 2 compartiments Storage | 1, 2, 12 |
| 17 | `20260822120000_photos_contrainte_regex` | **corrige les deux `check` de la 16, incompilables** | 16 |
| 18 | `20260823120000_couleur_texte_voiture` | `couleur_texte` sur `profils`, servie au classement et aux pronostics | 1, 16 |
| 19 | `20260826120000_calendrier_2026_grands_prix` | **insère les 11 GP restants de 2026**, `slug_gp`, `adopter_grand_prix` | 3, 11 |
| 20 | `20260826180000_qualifications_horaires_2026` | **corrige les horaires de qualifications de la 19**, qui les dérivait de `date_course` | 3, 11, **19** |
| 21 | `20260827_audit_rls` | **audit RLS** : lecture des profils bornée, `is_admin` non modifiable, fenêtre de fermeture sur les pronostics, deux politiques `insert` retirées, cotes réservées aux connectés | 1, 2, 3, 5, 8, 12, 14 |
| 22 | `20260913_storage_rls_extension` | **contrainte d'extension sur les dépôts** : `nom_de_photo_valide`, et les quatre politiques `insert`/`update` de Storage amendées par `alter policy` | **16** |
| 23 | `20260918_fermeture_au_depart` | **retire la marge de cinq minutes** : `pronostics_fermes` ferme à `date_course`, plus à `date_course − 5 min` | **5** |
| 24 | `20260926120000_statut_evaluation` | **`statut_evaluation`** sur `pronostics`, trigger de dérivation, `attribuer_points` qui écrit `non_evaluable` / `en_attente`. **À appliquer avant le backend `0.77.0`** | 5, **6** |
| 25 | `20260926200000_resultats_provisoires` | **`grands_prix.statut_resultats`**, les quatre GP courus marqués, **`remplacer_verdicts`**, `pronostics_du_joueur` qui sert `statut_evaluation`. **À appliquer avant le backend `0.78.0`** | 3, 6, **24** |

### Le piège d'ordre — la seule chose à surveiller

**Les migrations sont idempotentes chacune pour elle-même, PAS dans le désordre.**
Plusieurs `create or replace function` la même fonction : rejouer une migration
**antérieure** par-dessus restaure sa version d'avant.

| Si vous rejouez… | …vous perdez | Remède |
|---|---|---|
| **1** après **9** | la livrée automatique à l'inscription | rejouer 9 |
| **7** après **8** ou **12** | les champs de voiture au classement | rejouer 8 puis 12 |
| **5** après **10** ou **12** | voiture + total au tableau des résultats | rejouer 10 puis 12 |
| **8** ou **10** après **12** | la livrée d'écurie | rejouer 12 |
| **10** après **13** | `date_qualifications` au calendrier | rejouer 13 |
| **2**, **8**, **10** ou **12** après **16** | les photos aux cartes, classements et résultats | rejouer 16 |
| **16** après **17** | l'enregistrement de toute photo, de nouveau refusé en `2201B` | rejouer 17 |
| **2**, **8**, **10**, **12** ou **16** après **18** | la couleur de texte au classement et aux résultats | rejouer 18 |
| **19** après **20** | les onze horaires de qualifications, redevenus `date_course − 22h` | rejouer 20 |
| **1**, **8** ou **12** après **21** | la lecture des profils, de nouveau ouverte à toute l'application | rejouer 21 |
| **5** après **21** | la fenêtre de fermeture sur la lecture des pronostics | rejouer 21 |
| **2** après **21** | l'adhésion et la création de championnat, de nouveau libres | rejouer 21 |
| **3** après **21** | les cotes, de nouveau lisibles sans session | rejouer 21 |
| **16** après **22** | la contrainte d'extension sur les dépôts de photos | rejouer 22 |
| **5** après **23** | la marge de cinq minutes, restaurée en base seule | rejouer 23 |
| **6** après **24** | l'écriture de `non_evaluable` par `attribuer_points` (le trigger garde `gagne` / `perdu` / `en_attente` cohérents) | rejouer 24 |
| **5** ou **6** après **25** | `statut_evaluation` dans les pronostics servis (un `non_evaluable` redevient « en attente » à l'écran) | rejouer 25 |

**La 18 remplace `classement_du_championnat` et `pronostics_du_championnat`**, comme la 12
et la 16 avant elle, et pour la même raison : la couleur choisie doit atteindre les écrans
où *quelqu'un d'autre* voit la voiture. La perdre ne casse rien — le frontend retombe sur
l'encre calculée — mais le réglage cesse d'être visible ailleurs que sur son propre profil.

**Les migrations 11, 14, 15, 17, 19, 20, 21 et 22 ne remplacent aucune fonction** : elles ne
peuvent pas entrer en conflit d'ordre sur une *fonction*. **La 23, elle, en remplace une**
— `pronostics_fermes`, celle de la 5 — et son piège est le plus discret du tableau : la 5
rejouée derrière elle reposerait la marge de cinq minutes **en base seulement**. Le
frontend afficherait alors les pronostics ouverts et la route les accepterait pendant les
cinq dernières minutes, mais l'écriture serait refusée en `PT423`. D'où le bloc de
contrôle final de la 23, qui relit le corps de la fonction et **lève** s'il y trouve
encore un `interval`. La 22 en **crée** une
(`nom_de_photo_valide`), ce qui n'est pas la même chose : personne d'autre ne la remplace. La 17 ne remplace que deux
contraintes `check`, et il faut donc la rejouer si l'on rejoue la 16 — qui reposerait les
contraintes fautives.

> ### La 20 introduit un conflit d'ordre d'un genre nouveau : sur des DONNÉES
> Les huit pièges du tableau portent tous sur une fonction remplacée. Celui de la 20 porte
> sur une **valeur** : la 19 insère `date_course − 22h`, la 20 corrige. **Rejouer la 19
> après la 20 ne réinsère rien** — son garde-fou sur le slug l'en empêche — donc les
> horaires survivent. Le piège n'existe que si la 19 est jouée pour la **première** fois
> après la 20, c'est-à-dire sur une base neuve où l'on aurait inversé les deux. La 20 ne
> trouverait alors rien à corriger, et la 19 poserait les heures dérivées derrière elle.
>
> **La 19 n'a pas été réécrite pour autant**, et c'est la règle du §7 : les migrations sont
> historiques. La correction vit dans la 20, qui la porte seule et le dit dans son en-tête.

> ### La 21 en introduit un troisième genre : sur des POLITIQUES
> Les huit premiers pièges portent sur une fonction remplacée, celui de la 20 sur une
> valeur. Ceux de la 21 portent sur des **politiques RLS**, et ils sont d'une nature plus
> traître : **deux politiques `select` permissives sur une même table se combinent par
> OU**. Une politique permissive recréée par la 1, la 8, la 12, la 2, la 3 ou la 5 ne
> remplace donc pas celle de la 21 — elle la **désarme**, en la laissant en place. Aucune
> erreur, aucune ligne manquante, rien à voir dans les logs : la lecture redevient
> simplement ouverte.
>
> D'où deux garde-fous dans la 21. Chaque étape commence par `drop policy if exists` sur
> **l'ancien nom** avant de créer le nouveau, ce qui rend le rejeu de la 21 réparateur. Et
> son bloc de contrôle final **lève** si une seconde politique de lecture subsiste sur
> `public.profils` : c'est le seul moyen de découvrir l'état, une politique de trop ne se
> signalant par rien d'autre.

> ### La 22 en introduit un quatrième genre : sur une expression de POLITIQUE
> Ceux de la 21 portent sur l'**existence** d'une politique ; celui de la 22 porte sur
> l'**expression** de quatre politiques qu'elle ne possède pas. Elle les amende par
> `alter policy` — ce qui préserve leur nom, leur verbe, leurs rôles et le `using` des deux
> `update` — mais PostgreSQL **ne sait pas ajouter un terme** à une expression de politique :
> le `with check` est réécrit en entier, les deux termes de la 16 recopiés.
>
> D'où le piège : **rejouer la 16 après la 22** repose les quatre politiques dans leur version
> sans contrainte de nom. Aucune erreur, aucune ligne manquante — les dépôts redeviennent
> simplement libres sur le nom du fichier. C'est la contrepartie assumée d'`alter policy`, et
> le remède est celui de la 17 : rejouer la 22 derrière. Son bloc de contrôle final **lève**
> si l'un des quatre `with check` a perdu le terme, ou si l'un des deux `using` a disparu.

> ### La 17 répare un défaut que la 16 ne pouvait pas voir
>
> La 16 écrivait `check (colonne ~ '^https://[^[:space:]]{10,505}$')`. **PostgreSQL
> plafonne un compteur `{m,n}` à 255** (`RE_DUP_MAX`) : l'expression n'est pas compilable,
> et toute écriture d'URL de photo retombait en `2201B`. La contrainte avait pourtant été
> ACCEPTÉE à la création — un `check` n'est évalué qu'à l'écriture, et les colonnes étaient
> vides. Résultat : **aucune photo n'a jamais pu être enregistrée** entre la 16 et la 17
> (`bugs-connus.md` §18).
>
> La 17 sort la borne de longueur de l'expression (`char_length(...) between 18 and 513`),
> ce qui rend la sémantique inchangée à la lettre, et **s'éprouve elle-même** sur une URL
> jetable dans un bloc `do $$` final. Toute migration qui pose un `check` non trivial doit
> désormais faire de même : c'est le seul moment où l'on peut savoir, en la jouant, qu'elle
> est compilable.

> **La 16 est la seule qui SUPPRIME une fonction avant de la recréer.** `mes_championnats`
> déclare un `returns table (…)`, et PostgreSQL refuse de remplacer une fonction dont le
> type de retour change (`42P13`) — ajouter `photo_url` au tableau EST un changement de
> type. D'où un `drop function if exists` suivi d'un `create`, et surtout **les `revoke`
> et le `grant` reposés juste après** : `drop` emporte les droits avec la fonction, et une
> fonction recréée est exécutable par `public` par défaut. Les oublier l'ouvrirait à
> `anon`, donc à quiconque détient la clé publique du frontend.
>
> Elle remplace par ailleurs `classement_du_championnat` et `pronostics_du_championnat`,
> comme la 12 avant elle. Rejouer la 2, la 8, la 10 ou la 12 par-dessus fait disparaître
> les photos des cartes, des classements et du tableau des résultats — sans rien casser
> d'autre, le frontend retombant sur les initiales.

> **La 15 est la seule qui touche aux DONNÉES et non au schéma.** Elle vide
> `public.cotes`, repasse à `NULL` les deux colonnes `points_gagnes` et rouvre les GP
> `cotes_figees` — le multiplicateur des points est passé de 100 à 10 (`metier.md` §1),
> et tout ce qui avait été calculé l'avait été sur l'ancienne échelle. **Elle n'a rien
> converti** : diviser par dix une seconde fois par mégarde ne se verrait pas. Chacune
> de ses trois opérations est un retour à un état, donc rejouable telle quelle.
>
> **Après l'avoir jouée, déclencher un scraping** : sans cotes, aucun GP n'est
> pronosticable.

> **La 19 est la seconde qui touche aux DONNÉES et non au schéma**, après la 15 — et la
> première qui en ajoute. Elle insère les onze Grands Prix restants de 2026, que le
> scraper n'aurait rencontrés qu'un par un, la veille de chacun : Unibet n'expose jamais
> que le Grand Prix suivant (`calendrier.md` §1). Elle referme au passage le point de
> `roadmap.md` sur le bandeau « Grands Prix restants », qui comptait les lignes en base et
> n'en trouvait qu'une.
>
> **Son idempotence ne repose PAS sur `id_unibet`.** Un `on conflict (id_unibet) do
> nothing` aurait été le piège exact : une fois la ligne adoptée, son identifiant n'est
> plus le placeholder, la clause ne trouverait plus de conflit et la migration rejouée
> réinsérerait le doublon qu'elle existe pour éviter. Le garde-fou porte donc sur
> `public.slug_gp(nom)` — une empreinte qui survit à l'adoption **comme** au changement
> d'orthographe qu'Unibet apporte au premier scraping.
>
> `slug_gp` est la contrepartie SQL de `slugCircuit`, et s'éprouve elle-même sur six cas
> dans un bloc `do $$` — la leçon de la 17. Elle ramène les accents par `translate` et non
> par `unaccent` : l'extension n'est pas garantie active, et une migration qui échoue sur
> un `create extension` refusé ne s'exécute pas du tout.

### Non éprouvées sur un PostgreSQL jetable

> **La 24 non plus** : ni démon Docker ni PostgreSQL local au moment de son écriture. Son
> bloc de contrôle final lève si le trigger manque ou si une ligne a un statut incohérent
> avec ses points. **À surveiller au premier passage dans le SQL Editor.**

Les migrations **12, 13 et 14** n'ont pas été jouées contre un Docker (démon indisponible
au moment de leur écriture), contrairement aux onze premières. La 13 a été comparée ligne
à ligne à la 10 : trois lignes de différence, toutes attendues. **À surveiller au premier
passage dans le SQL Editor.**

> ### La 19 et la 20 l'ont été, sur PostgreSQL 16
> Le démon Docker était disponible cette fois. Les deux migrations ont été jouées sur une
> base jetable, contre un harnais réduit aux colonnes qu'elles touchent — **pas le schéma
> de la 3**, ce que ce contrôle ne remplace donc pas. Six choses ont été vérifiées :
>
> - la 19 s'exécute, ses six cas d'épreuve de `slug_gp` passent, elle insère onze lignes ;
> - **rejouée, elle en insère zéro** — le garde-fou sur le slug tient ;
> - la 20 corrige **neuf** lignes (Austin et le Mexique portaient déjà la bonne heure), et
>   rejouée n'en corrige plus aucune ;
> - une heure qu'Unibet aurait annoncée entre-temps n'est **jamais** réécrite ;
> - une ligne déjà **adoptée** — dont l'`id_unibet` n'est plus le placeholder — est bien
>   retrouvée et corrigée, ce qui était l'objet du rapprochement par slug ;
> - les onze instants finaux **concordent au caractère près** avec
>   `GP_2026.seances.qualifications`, croisés par script et non relus à l'œil.

> ### La 21 l'a été aussi, sur PostgreSQL 16
> Contre un harnais réduit aux neuf tables, à `est_membre`, à `pronostics_fermes` et aux
> politiques telles qu'elles étaient **avant** elle — pas le schéma complet, ce que ce
> contrôle ne remplace donc pas. Trois utilisateurs : Alice et Bruno dans un championnat
> commun, Chloé seule dans le sien. Onze épreuves de comportement, toutes passées :
>
> - Alice lit `profils` et voit **Alice et Bruno**, jamais Chloé ; Chloé ne voit qu'elle ;
> - Alice écrivant son propre `is_admin` est refusée (`42501`), celui de Bruno aussi ;
> - Alice écrivant sa `couleur1` passe — le `grant` par colonne n'a rien cassé ;
> - des deux pronostics de Bruno, Alice ne voit que celui du **GP fermé** ;
> - Bruno relit ses deux pronostics, GP ouvert compris ;
> - `pronostic_podium` suit la même fenêtre **sans que sa politique soit touchée** ;
> - Alice ne peut ni s'ajouter au championnat de Chloé, ni créer un championnat en direct ;
> - `anon` est refusé sur `cotes` et servi sur `grands_prix` ;
> - **rejouée, la 21 ne change plus rien** ;
> - la 12 rejouée par-dessus fait bien réapparaître **deux** politiques de lecture — le
>   piège du genre nouveau, reproduit — et **rejouer la 21 le répare** ;
> - une politique parasite ajoutée à la main fait bien **lever** le bloc de contrôle.

> ### La 22 l'a été aussi, sur PostgreSQL 16
> Contre un harnais réduit à `storage.objects`, `storage.foldername`, `auth.uid()`,
> `public.championnats` et **les sept politiques de la 16** — pas le schéma `storage` complet,
> ce que ce contrôle ne remplace donc pas. Dix épreuves, toutes passées :
>
> - les trois noms légitimes se déposent (`avatar.jpg`, `avatar.png` d'avant la `0.51.0`,
>   `photo.jpg`), les sept mauvais sont refusés par la RLS (`page.html`, `x.svg`, `x.js`,
>   `avatar.jpg.svg`, dossier d'autrui, `photo.html`, championnat d'autrui) ;
> - l'**`upsert` normal fonctionne**, ce qui prouve que le `using` a survécu à
>   l'`alter policy` — toute la méthode repose là-dessus ;
> - renommer sa propre photo en `.html` est refusé par le `with check` ;
> - **réparer** un `legacy.html` en `avatar.jpg` fonctionne : c'est pourquoi le motif n'est
>   pas dans le `using` ;
> - écraser la photo d'un autre reste refusé — la garde du §28 est intacte ;
> - supprimer sa propre photo fonctionne : `delete` n'est pas touchée ;
> - **trois rejeux d'affilée** ne changent rien, dépôts compris ;
> - le garde-fou d'absence lève un message clair si la 16 n'a pas été jouée ;
> - l'état dégradé du piège ci-dessus est **reproduit**, détecté par le bloc de contrôle, et
>   **réparé par un rejeu de la 22**.
>
> **Le harnais a d'abord menti.** Sa première version omettait les politiques `select` et
> `delete` de la 16, et *tous* les `update` ressortaient refusés — l'`upsert` légitime
> compris. La cause n'était pas la migration : **un `update` dont le `where` lit une colonne
> applique aussi les politiques `select`**. Sans politique de lecture, la ligne est
> introuvable et le `with check` n'est jamais atteint. À retenir pour le prochain harnais RLS.

---

## 7. Pièges connus

> **La comparaison d'instant se calcule en Python, en UTC, pas en SQL.** Un `now`
> interprété par PostgreSQL dépendrait du fuseau de la session. Le suffixe `Z` est
> préféré à `+00:00`, dont le `+` se confond avec une espace une fois la requête encodée.

> **`nullslast` / `nullsFirst: false` n'est jamais cosmétique.** PostgreSQL place les
> `NULL` en tête : sans cette clause, un GP dont l'horaire n'est pas annoncé passerait
> devant la course de dimanche.

> **La saison est l'année civile du GP, lue en UTC** (`at time zone 'UTC'` explicite),
> sans quoi le résultat dépendrait du fuseau de la session.

> **Un commentaire périmé subsiste dans la migration 3** : il annonce que `date_course`
> est convertie depuis l'heure de Paris. C'est faux depuis la v0.40.0 (voir
> `bugs-connus.md`). Les migrations sont historiques et ne sont pas réécrites.

> **`row_number` vs `rank`** — le classement de saison emploie `row_number` (les quatre
> critères départagent toujours) ; le classement d'**un** GP emploie `rank`, parce qu'il
> n'a aucun critère de départage : avant le départ, tout le monde est à zéro et
> `row_number` inventerait un premier et un dernier.

> **`left join lateral`, jamais un `group by`** dans les classements : un membre qui n'a
> jamais pronostiqué doit apparaître avec 0 point, pas disparaître de la liste.

> **`meilleure_cote` vaut `NULL`, jamais `0`**, pour qui n'a rien réussi. Le tri, lui,
> ramène le `NULL` à `0`.

---

## 8. Codes d'erreur — les reconnaître dans les logs

Depuis la v0.9.0 ils ne quittent plus le serveur : **il faut ouvrir les logs Railway.**

| Code | Sens | Cause typique |
|---|---|---|
| `42P01` | relation inexistante | **migration non appliquée** |
| `42703` | colonne inexistante | migration partiellement appliquée, ou rejouée dans le désordre |
| `42883` | fonction inexistante | migration non appliquée |
| `42501` | droits insuffisants | fonction `service_role` appelée sous une autre identité |
| `42P17` | **récursion de politique** | sous-requête littérale réinsérée dans une politique RLS (§2) |
| `23505` | violation d'unicité | collision de code d'invitation, ou favori déjà épinglé |
| `23503` | violation de clé étrangère | référence vers une ligne supprimée |

**Codes applicatifs levés par les fonctions SQL :**

| Code | Levé par | Sens |
|---|---|---|
| `PT423` | `enregistrer_pronostics` | pronostics **fermés** — la vérification qui fait foi |
| `PT403` | `enregistrer_pronostics` | plus de **trois bonus** |

> **`23505` sur la bascule d'un favori n'est PAS une erreur** : c'est l'état demandé,
> atteint par un appel concurrent. La bascule est une suppression puis, si rien n'a été
> supprimé, une insertion — **c'est la base qui tranche**, jamais une lecture préalable qui
> laisserait deux appuis rapprochés retomber du même côté.

> **`PT423` prouve que le refus est atomique** : la fonction commence par effacer le jeu
> précédent, et lève ensuite si la fermeture est passée — **la transaction annule le
> `delete`**. Un test le vérifie explicitement.

---

## 9. Supabase Storage — deux compartiments, et où vit l'autorisation

Migrations 16 et **22**. Les images ne sont **jamais** en base : `profils.avatar_url` et
`championnats.photo_url` ne portent que des URL publiques (§1).

| Compartiment | Chemin d'un objet | Qui écrit |
|---|---|---|
| `avatars` | `{profil_id}/avatar.{ext}` | le profil lui-même (`auth.uid()`) |
| `championnats` | `{championnat_id}/photo.{ext}` | le **créateur** du championnat |

`{ext}` n'est pas libre depuis la migration 22 : `jpg`, `jpeg`, `png` ou `webp`, et le nom qui
la précède est borné lui aussi (voir ci-dessous).

Les deux sont **publics**, plafonnés à **2 Mo**, et n'acceptent que `image/jpeg`,
`image/png` et `image/webp`.

> **Depuis la version `0.51.0`, l'extension déposée est toujours `jpg`.** Le fichier choisi
> dans la photothèque n'est plus celui qui part : il est recadré, ramené à 800 px de côté
> et réencodé en JPEG 0,85 par `frontend/src/lib/image.js`. Les trois types restent
> déclarés sur le compartiment — c'est lui qui garde, et une photo posée avant cette
> version porte encore son extension d'origine — mais le plafond de 2 Mo n'est plus jamais
> approché : une photo d'iPhone de quatre mégaoctets en pèse moins de deux cents kilo-octets
> une fois traitée. Le frontend, lui, plafonne le **choix** à 5 Mo, ce qui ne mesure pas la
> même chose (`docs/composants.md` §5).

> **Le premier segment du chemin EST l'autorisation.** La politique compare
> `(storage.foldername(name))[1]` à `auth.uid()` pour un avatar, et remonte à
> `championnats.cree_par` pour une photo de championnat. Personne ne peut donc écrire dans
> le dossier d'un autre, quel que soit le client utilisé — c'est la base qui refuse, pas le
> code de l'écran. **Aucune récursion à craindre** ici : la sous-requête porte sur
> `public.championnats`, pas sur `storage.objects` que la politique protège (§2).

> ### Le dossier dit « à qui », l'extension dit « quoi » (migration 22)
>
> Le contrôle du dossier ci-dessus ne qualifie que le **propriétaire**. Jusqu'à la migration
> 22, tout ce qui suivait était libre : `avatars/{son propre id}/page.html` était déposable.
> La liste `allowed_mime_types` n'y changeait rien — **elle porte sur l'en-tête
> `Content-Type` annoncé, jamais sur le nom ni sur les octets**.
>
> Les quatre politiques d'écriture — `insert` et `update` des deux compartiments — portent
> donc un troisième terme, `public.nom_de_photo_valide(name)` : le **dernier segment** du
> chemin doit valoir `^[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|webp)$`, casse ignorée. Pas de `/`,
> pas de `%`, pas de point hors extension. **`svg` est exclu comme les autres** : c'est la
> seule image qui porte du script, et les deux compartiments sont publics.
>
> **Le motif a deux propriétaires par nécessité** : cette fonction et `NOM_DE_FICHIER` dans
> `backend/app/api/stockage.py`. Deux moteurs de regex, un seul motif — ils doivent bouger
> ensemble, et le bloc de contrôle de la 22 rejoue les échantillons du test backend pour que
> la dérive se voie.
>
> **`select` et `delete` ne sont PAS filtrées, et il faut que ce soit ainsi.** Un objet déjà
> déposé doit rester **lisible** — sinon une photo d'avant la 22 disparaîtrait des écrans — et
> surtout **effaçable** : `delete` est le seul geste qui répare un objet mal nommé déjà en
> place. Un contrôle de nom sur un retrait protégerait le déchet, pas les joueurs. Le motif
> n'est pas davantage dans le `using` des `update`, pour la même raison : il aurait rendu un
> objet mal nommé impossible à écraser. Voir `bugs-connus.md` §32.

> **Trois politiques d'écriture par compartiment, et il en faut bien trois** : `insert`
> pose la première photo, `update` écrase la suivante — le chemin est stable —, `delete`
> sert au bouton « Supprimer la photo ». Sous RLS, ce qu'aucune politique n'autorise est
> refusé : en oublier une fermerait silencieusement un des trois gestes.

> **Compartiments publics, et c'est un arbitrage.** Une photo de profil s'affiche sur la
> carte d'un autre joueur, dans un classement partagé, sur la piste. Un compartiment privé
> obligerait à signer une URL par image et par affichage, donc un aller-retour réseau par
> vignette d'un classement de douze. Même raisonnement que la lecture publique des GP et
> des cotes (§2).

> **Ce que le compartiment garde, et ce qu'il ne garde pas.** `allowed_mime_types` et
> `file_size_limit` sont les **seules** défenses côté serveur sur le fichier lui-même : le
> backend ne le voit jamais passer (`architecture.md` §3). Mais `allowed_mime_types` lit
> l'en-tête annoncé — on peut déposer du HTML étiqueté `image/jpeg`. Ce n'est pas une faille,
> parce que **c'est ce même type annoncé qui sera servi** : le navigateur reçoit du HTML
> étiqueté `image/jpeg`, ce qu'il n'exécute pas. Le raisonnement doit passer par là, sinon on
> conclut juste par hasard.

> **Le plafond et la liste des types vivent dans le COMPARTIMENT, pas dans le client.**
> `frontend/src/lib/stockage.js` fait la même vérification, mais pour dire non tout de
> suite — 2 Mo montés sur un réseau mobile avant d'être refusés seraient 2 Mo perdus. Le
> `heic` d'un iPhone n'est pas dans la liste et n'a pas à y être : Safari convertit en JPEG
> à la sélection d'un fichier.

> ### L'URL enregistrée en base est vérifiée par le backend, et il faut que ce soit là
>
> Le chemin d'écriture est celui de `docs/architecture.md` §3 : **le fichier va
> directement à Supabase** (la RLS Storage décrit exactement le cas), **l'URL passe par
> FastAPI** (c'est une écriture en base). `app/api/stockage.py` confronte alors l'URL reçue
> à `SUPABASE_URL` : elle doit désigner **notre** projet, **le bon compartiment**, **le
> dossier de l'appelant** (backend `0.58.0`) et — depuis le backend `0.62.0` — **un nom de
> fichier d'image**, le même motif que celui de la migration 22.
>
> **Ce troisième point est celui qui manquait**, et son absence était une faille d'IDOR :
> la règle du dossier ci-dessus garde le DÉPÔT du fichier, pas l'écriture de l'URL en base,
> qui passe par la clé de service et contourne donc la RLS. Chacun pouvait enregistrer
> comme sienne la photo déposée par un autre. Voir `bugs-connus.md` §28.
>
> Sans cette vérification, une URL libre en base deviendrait un **pixel espion posé sur
> l'écran des autres joueurs** — sa photo s'affiche au classement, sur la piste, au résumé
> d'un Grand Prix, et chaque affichage révélerait l'IP et le `User-Agent` de ces joueurs au
> serveur choisi par l'auteur de l'URL. L'app est ouverte au public : ce n'est pas une
> hypothèse d'école.
>
> **Sans `SUPABASE_URL`, tout est refusé** (`503`) plutôt que tout accepté. Le service
> démarre sans les clés pour garder `/health` joignable (`architecture.md` §5) ; dans cet
> état, laisser passer serait l'inverse du sens du doute voulu ici.

> **Le chemin d'un objet est stable, donc son URL publique aussi** — et c'est ce qui oblige
> à un horodatage. Sans le `?v=…` que `lib/stockage.js` ajoute, remplacer sa photo ne
> changerait **rien** : ni le navigateur, ni le CDN de Supabase, ni la colonne en base. Le
> paramètre périme le cache et fait changer la colonne, deux effets pour un.

> **Changer de format laisse un orphelin, et c'est traité.** Remplacer un PNG par un JPEG
> écrit `photo.jpg` **à côté** de `photo.png` : la base ne pointe plus que sur le nouveau,
> l'ancien resterait indéfiniment. `lib/stockage.js` efface les autres extensions **après**
> le dépôt — effacer d'abord laisserait quelqu'un sans photo si l'envoi échouait ensuite.
