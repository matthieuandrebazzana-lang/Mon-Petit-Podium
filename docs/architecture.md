# Architecture

Comment le projet est construit, ce qui tourne où, et pourquoi.

---

## 1. Monorepo

```
MonPetitPodium/
├── frontend/          React + Vite + Tailwind 4 (PWA)  → Vercel
├── backend/           FastAPI (Python)                 → Railway
├── supabase/migrations/   17 fichiers SQL, appliqués à la main
├── assets/            planches SVG source (logo, drapeaux, tracés, voitures)
├── maquettes/         16 écrans HTML autonomes de la v1
└── docs/              cette documentation
```

`assets/` et `maquettes/` ne sont **jamais** servis en production : ce sont des sources
dont on extrait des composants React par script (voir `composants.md`).

## 2. Les trois couches

| Couche | Techno | Hébergement | Rôle |
|---|---|---|---|
| Frontend | React 19 + Vite 8 + Tailwind CSS 4 | Vercel | Interface, PWA installable sur iPhone |
| Backend | FastAPI + httpx + APScheduler | Railway | Scraping, calcul des points, cron jobs |
| Base | PostgreSQL | Supabase | Données + authentification |

**Cible : Safari iOS.** Toutes les décisions techniques (CSS, animations, SVG) s'y
arbitrent — pas sur Chromium.

---

## 3. Les deux chemins de données, et quand prendre lequel

C'est la décision d'architecture la plus structurante du projet. **Le frontend parle
à Supabase par deux chemins différents, délibérément.**

```
        ┌─────────────┐
        │  Frontend   │
        └──┬───────┬──┘
           │       │
    (A)    │       │    (B) lecture directe, sous RLS
  écriture │       └──────────────────────────┐
  + règles │                                  │
   métier  ▼                                  ▼
      ┌─────────┐   clé de service      ┌──────────┐
      │ FastAPI ├──────────────────────►│ Supabase │
      └─────────┘   (contourne la RLS)  └──────────┘
```

**(A) Par FastAPI** — toute écriture, et toute lecture qui agrège les données d'autrui :
classement, statistiques, calendrier d'un championnat, pronostics des membres.
Ces fonctions SQL sont `security definer` et réservées à `service_role` ; l'autorisation
est portée par la route, qui vérifie l'appartenance **avant** l'appel.

**(B) En direct à Supabase** — les lectures qu'une politique RLS décrit déjà exactement :
prochain GP, pronostics du joueur, pseudo, drapeau `is_admin`, numéros déjà pris.

> **Un même écran peut prendre les deux chemins pour la même donnée, selon qui la
> demande** — c'est le cas de l'écran de résultats depuis la `0.63.0`, et il illustre le
> critère mieux que n'importe quel exemple. Les pronostics **des membres d'un championnat**
> passent par (A) : la RLS les filtrerait silencieusement pour un appelant qui ne partage
> pas tous ses championnats avec eux. Les pronostics **de l'appelant lui-même**, quand il
> n'y a aucun championnat dans l'URL, passent par (B) : la politique « Pronostics visibles
> entre membres » ouvre son premier terme sur `profil_id = auth.uid()`, précisément pour
> qu'un joueur sans championnat puisse relire ce qu'il a joué. **Ce n'est pas la donnée qui
> décide du chemin, c'est la politique.**

**Le dépôt d'une photo emprunte les DEUX chemins, et c'est le critère appliqué tel quel.**
Le **fichier** — recadré, réduit et réencodé dans le navigateur depuis la version `0.51.0`
(`lib/image.js`) — va directement à Supabase Storage : les politiques de `storage.objects`
décrivent exactement le cas — le premier segment du chemin est l'identifiant du
propriétaire, comparé à `auth.uid()` — et faire transiter deux mégaoctets par le plan
gratuit de Railway n'ajouterait qu'un cold start. L'**URL**, elle, passe par FastAPI :
c'est une écriture en base, et c'est là que le backend vérifie qu'elle désigne bien notre
projet. Voir `database.md` §9.

**Le critère est la politique RLS, pas la commodité.** Si la RLS décrit le cas, on lit
en direct — passer par Railway n'ajouterait qu'un cold start. Si la RLS ne le décrit
pas (ou le décrirait de travers, en amputant silencieusement un classement), la route
FastAPI fait foi.

**Conséquence pratique** : l'accueil est le premier écran de l'app. Il lit en direct
précisément pour ne pas attendre le réveil de Railway sur son bloc principal.

---

## 4. Les deux clés Supabase — ne jamais les confondre

| Clé | Où | Usage |
|---|---|---|
| **anon** | frontend **et** backend | Valider le jeton de l'appelant. Soumise à la RLS. |
| **service_role** | backend **uniquement** | Lectures et écritures. **Contourne la RLS.** |

La clé de service ne doit **jamais** quitter le serveur et n'a donc aucun équivalent
`VITE_`. Elle contourne la RLS, ce qui est voulu : retrouver un championnat par son
code alors qu'on n'en est pas encore membre est impossible sous RLS.

**L'autorisation est alors portée par le code des routes**, qui ne travaille jamais
qu'avec l'identifiant issu du jeton vérifié — **le corps de la requête ne dit jamais
qui est l'appelant**.

Le jeton est validé en le présentant à Supabase (`/auth/v1/user`) plutôt que vérifié
localement : aucun secret de signature à gérer. Un cache de 60 s évite un aller-retour
par appel.

---

## 5. Variables d'environnement

**Aucune valeur n'est écrite ici.** Seulement les noms et ce qu'ils font.

### Backend (Railway)

| Variable | Sans elle |
|---|---|
| `SUPABASE_URL` | `503` sur les routes métier ; **les deux schedulers ne démarrent pas** |
| `SUPABASE_ANON_KEY` | idem |
| `SUPABASE_SERVICE_ROLE_KEY` | idem |
| `ADMIN_SECRET` | les trois routes d'administration **en `curl`** refusent tout le monde (`503`). `POST /admin/action`, elle, n'en dépend pas |
| `ENVIRONMENT` | vaut `development`, donc `/docs` reste public |
| `FRONTEND_URL` | non bloquante — l'origine Vercel est la valeur par défaut |
| `CORS_ORIGINS` | origines supplémentaires, séparées par des virgules |

Le service **démarre sans les clés Supabase** : `/health` doit rester joignable pour
diagnostiquer. Il journalise un avertissement et répond `503` sur les routes concernées.

### Frontend (Vercel)

| Variable | Sans elle |
|---|---|
| `VITE_SUPABASE_URL` | écran « configuration manquante » |
| `VITE_SUPABASE_ANON_KEY` | idem |
| `VITE_API_URL` | retombe sur `http://localhost:8000` |

> **Les trois sont PUBLIQUES PAR CONCEPTION, et c'est ce qui rend la liste vérifiable.**
> Vite remplace `import.meta.env.VITE_*` par sa valeur littérale **à la construction** :
> tout ce qui porte ce préfixe part en clair dans le bundle JavaScript, lisible par
> quiconque ouvre les outils de développement. La règle n'est donc pas « protéger les
> `VITE_` », c'est **« aucune valeur secrète ne porte ce préfixe »**.
>
> `VITE_SUPABASE_ANON_KEY` est faite pour être exposée — c'est la **RLS** qui protège,
> jamais l'obscurité de la clé ; `VITE_SUPABASE_URL` et `VITE_API_URL` sont deux adresses
> publiques. Le corollaire est le seul point à retenir : **la RLS n'est pas un complément
> de cette clé, elle en est la contrepartie.** Une table sans politique est publique.

> **`VITE_ADMIN_SECRET` a existé et n'existe plus** (retirée à la version `0.64.0`). Le
> secret partait en clair dans le bundle, ce qui vidait de sa substance le garde des trois
> routes d'administration. Les actions déclenchées depuis l'application passent désormais
> par **`POST /admin/action`**, fermée par le jeton du membre et une relecture de
> `is_admin` en base ; `ADMIN_SECRET` reste sur Railway pour le `curl` et **ne quitte plus
> jamais le serveur**. Voir `decisions.md` §22. **Ne pas la recréer** : la variable est
> encore définie dans le projet Vercel au moment où ces lignes sont écrites, et elle y est
> désormais sans effet — la retirer est un geste à faire à la main.

---

## 6. CORS

Le `CORSMiddleware` est monté **au niveau de l'application**, jamais route par route :
il couvre tout, y compris les préflights `OPTIONS` et les routes qui n'existent pas encore.

Deux origines sont **garanties quelle que soit la configuration** : la production Vercel
(constante `ORIGINE_PRODUCTION` dans `config.py`) et le serveur de dev Vite
(`localhost:5173` et `127.0.0.1:5173`). `FRONTEND_URL` **ajoute** une origine, elle n'en
retire jamais.

`FRONTEND_URL` et `CORS_ORIGINS` sont typées `str` et non `list[str]` : pydantic-settings
exigerait du JSON strict sur un champ complexe et **planterait au démarrage** sur une
valeur simple. La barre oblique finale est retirée automatiquement — l'en-tête `Origin`
n'en comporte jamais.

La liste des origines chargées est journalisée au démarrage.

---

## 7. Journalisation

**`logging.getLogger("uvicorn.error")` — jamais `getLogger(__name__)`.** Sous Railway,
c'est le seul logger doté d'un handler ; les autres écrivent dans le vide.

`api/journal.py` porte le décorateur `journaliser_echecs(domaine, contexte)` posé sur
chaque handler :

- les `HTTPException` traversent **intactes** (404, 409, 423, 401, 503) — ce sont des
  réponses voulues, pas des pannes ;
- tout le reste passe par **`echec_lisible(contexte, erreur)`** : journalisé **avec sa
  trace**, message Supabase, code PostgreSQL et statut HTTP — puis rendu en `422`
  **en français**.

> **Le `422` est un choix de TRANSPORT, jamais de sémantique.** Ces erreurs ne sont pas des
> erreurs de validation : ce statut est retenu parce que `lib/api.js` affiche déjà tel quel
> un `detail` de type chaîne, et qu'il ne se confond ni avec le `503` d'une configuration
> absente ni avec le `500` d'un plantage non capturé.

> **`echec_lisible` s'appelle depuis un bloc `except`** — `logger.exception` n'a de trace à
> joindre que là.

> **Le contexte doit nommer la ROUTE, jamais l'un de ses usages.** Il part tel quel dans le
> message rendu à l'appelant. `PATCH /profils/moi` a porté « Enregistrement de ta voiture »
> jusqu'à la version `0.51.0` alors qu'il sert aussi le numéro, la livrée **et** la photo :
> une photo refusée par la base s'annonçait donc comme un échec de voiture, et envoyait
> chercher la cause du côté des couleurs. **Un contexte qui nomme la mauvaise chose est pire
> qu'un contexte vague** — c'est ce qui a fait manquer le défaut de `bugs-connus.md` §18
> pendant toute une version. Il vaut désormais « Enregistrement de ton profil ».

`lib/api.js` garde un garde-fou par-dessus, et **ce n'est pas un doublon** : il protège
contre ce qui ne vient **pas** de notre backend — page d'erreur Railway, proxy qui
s'interpose, ancienne version encore déployée. `SIGNATURE_TECHNIQUE` reconnaît des
signatures franches (code PostgreSQL, `Traceback`, `does not exist`, `Bad Gateway`) et non
« est-ce du français ? », question à laquelle une expression régulière ne sait pas répondre.

> **`functools.wraps` est obligatoire dans ce décorateur.** FastAPI lit la signature du
> handler pour construire ses dépendances, et `inspect.signature` suit `__wrapped__`.
> Sans lui, la route recevrait `(*args, **kwargs)` et **perdrait
> `Depends(utilisateur_courant)` ou son en-tête `X-Admin-Secret`** : elle s'ouvrirait aux
> appels anonymes. Des tests couvrent précisément ce cas.

Depuis la v0.9.0, **les messages techniques ne quittent plus le serveur** : l'appelant
reçoit un contexte en français, les logs Railway reçoivent message, code PostgreSQL,
statut HTTP et trace complète. **Conséquence pour le diagnostic : une panne ne se lit
plus à l'écran, il faut ouvrir les logs Railway.**

---

## 8. Les deux schedulers

Démarrés dans le `lifespan` de FastAPI (`AsyncIOScheduler`) : aucun processus ni thread
supplémentaire, ce qui compte sur le plan gratuit.

| Job | Intervalle | Premier tour | Détail |
|---|---|---|---|
| `jobs/scraper.py` | 1 h | +2 min | voir `scraper.md` |
| `jobs/resultats.py` | 5 min | +30 s | départ +1h30, fenêtre 3 h |

Ils ne démarrent **pas** sans configuration Supabase : ils journaliseraient une panne
toutes les cinq minutes en noyant les logs.

> **Les deux supposent UN SEUL PROCESSUS.** C'est le cas sur le plan gratuit de Railway.
> À plusieurs instances, deux schedulers de chaque tourneraient en parallèle : la base
> empêche la double attribution des points, mais **ni les appels OpenF1 ni les appels
> Unibet en double**. Remède : `pg_try_advisory_lock` dans les deux `surveiller()`, ou
> un worker dédié.

---

## 9. Cold start Railway

Le plan gratuit met le service en veille. Deux conséquences assumées :

1. **Cache *stale-while-revalidate*** en `localStorage` (`lib/useDonnees.js`) — l'app
   affiche immédiatement ce qu'elle savait, puis se met à jour.
2. **`502`, `503` et `504` sont classés « réseau » et non « serveur »** dans
   `lib/erreurs.js` : c'est exactement ce que rend un service endormi, « Connexion au
   serveur en cours » est alors la description juste, et réessayer marche.

> **La clé de cache porte toujours l'identifiant du compte.** Deux personnes qui se
> relaient sur le même téléphone ne doivent jamais voir les données de l'autre, fût-ce
> une fraction de seconde.

---

## 10. Routage frontend

`react-router-dom`, trois groupes dans `App.jsx` :

- **public** — `/`, `/inscription`, `/connexion`, `/mot-de-passe-oublie`
- **protégé** — tout le reste
- **hors des deux** — `/nouveau-mot-de-passe` (un lien de réinitialisation ouvre une
  session, donc l'utilisateur est techniquement connecté sans avoir le droit d'entrer
  dans l'app) et `/grands-prix/:gpId/resultats` (le classement d'une course est public,
  mais un membre connecté ne doit pas être renvoyé sur son accueil).

Tant que la session initiale n'est pas résolue, les gardes affichent l'écran d'attente :
rediriger pendant ce laps ferait clignoter la connexion à chaque lancement.

`frontend/vercel.json` réécrit toutes les URL vers `index.html`, sans quoi un lien
profond renverrait un 404 avant l'installation du service worker.

---

## 11. PWA

`vite-plugin-pwa` génère le manifeste (`manifest.webmanifest`) **et injecte lui-même**
le `<link rel="manifest">`.

> **Il n'y a pas de `public/manifest.json`, et il ne faut pas en créer un.** Un fichier
> posé là serait copié dans `dist` sans être lié par rien ; le lier ferait cohabiter deux
> manifestes, là où la spécification n'en admet qu'un. Les icônes, le nom et le nom court
> se déclarent dans le bloc `manifest` de **`frontend/vite.config.js`**.

Icônes : `npm run icones` regénère les quatre PNG depuis `assets/logo-05.svg` via
`frontend/scripts/generer-icones.mjs`. **Le script est le livrable, pas les PNG.**
Elles sont rendues **à fond perdu et sans canal alpha** — iOS applique son propre masque
arrondi et rend en noir la transparence d'une `apple-touch-icon`. Garder l'arrondi du
dessin donnerait un arrondi dans un arrondi, avec des coins noirs.

> **Une quatrième icône `maskable` est générée, et ce n'est pas un ajout gratuit.** Android
> découpe une icône `maskable` dans un cercle ou un squircle et peut manger **les 10 % de
> chaque bord** ; une icône `purpose: "any"` est au contraire posée **dans une pastille
> blanche** au lieu d'être servie bord à bord. Le fond couvre donc tout le carré, et le
> dessin est ramené à **80 % autour du centre** — un tracé qui tenait dans le carré tient
> alors forcément dans les 80 % centraux, sans qu'on ait à mesurer sa boîte englobante.

`density` est passée à `sharp` proportionnellement à la taille : sans elle, le SVG est
rastérisé à 72 ppp puis agrandi, et les 512 sortent floues. Le script **échoue franchement**
si la planche change de structure, plutôt que d'écrire une icône vide.

---

## 12. Les routes

Convention : nom de domaine au **pluriel**, sous-chemin **`/moi`** pour ce qui appartient à
l'appelant, **verbe explicite** pour ce qui n'est pas un CRUD (`/rejoindre`, `/quitter`,
`/declencher`), préfixe **`/jobs/`** pour les déclenchements d'administration.

| Route | Auth | Comportement |
|---|---|---|
| `GET /health` | — | version, environnement |
| `POST /championnats` | jeton | `201`. Code tiré de `secrets`, 5 tentatives sur collision (`23505`), puis échec franc |
| `GET /championnats/moi` | jeton | + effectif, **prochain GP** (une seule lecture pour toute la liste), **position** (rang, points, points du leader), plafonnée à **`LIMITE_CLASSEMENTS = 12`** |
| `POST /championnats/rejoindre` | jeton | code normalisé. `404` inconnu, `409` déjà membre — **par la clé primaire**, pas par une lecture préalable |
| `GET /championnats/{id}/classement` | jeton + **membre** | |
| `GET /championnats/{id}/calendrier` | jeton + **membre** | `?saison=`. **Le profil vient du jeton, jamais de l'URL** |
| `PATCH /championnats/{id}` | jeton + **créateur** | photo seule. `403` si l'appelant n'est pas le créateur |
| `DELETE /championnats/{id}/quitter` | jeton | **`204`**, ou `404` si non membre |
| `GET /profils/{id}` | jeton | ouvert à tout connecté (aligné sur la RLS) |
| `GET /profils/{id}/stats` | jeton + **championnat partagé** | `403` — **rendu AVANT de lire le profil visé** |
| `PATCH /profils/moi` | jeton | partiel, photo comprise. **Aucun identifiant dans le chemin** |
| `GET /grands-prix/{id}/cotes` | **publique** | groupées par marché |
| `GET /scraper/cotes` | **publique** | toutes les cotes en base |
| `POST /grands-prix/{id}/favoris` | jeton | bascule → `{favori: bool}` |
| `GET /grands-prix/{id}/favoris` | jeton | enrichis, dans l'ordre d'épinglage |
| `POST /grands-prix/{id}/pronostics` | jeton | remplace le jeu complet. **`423`** si fermé |
| `GET /grands-prix/{id}/pronostics/championnat/{cid}` | jeton + **membre** | `403` **vérifié avant l'existence du GP** |
| `GET /grands-prix/{id}/resultats` | **mixte** | classement public ; `?championnat_id=` exige jeton **et** appartenance |
| `POST /admin/action` | jeton + **`is_admin` en base** | une route pour toutes les actions de l'app. `403` si le drapeau est faux |
| `POST /scraper/declencher` | `X-Admin-Secret` | **`202`, asynchrone**. `?figer=false`. Réservée au `curl` |
| `POST /jobs/resultats/{id}` | `X-Admin-Secret` | **synchrone**, compte rendu complet. `425` si non publiés. Réservée au `curl` |
| `POST /jobs/resultats/{id}/test` | `X-Admin-Secret` | **banc d'essai, n'écrit rien** |

> **Trois routeurs se partagent le préfixe `/grands-prix/{id}`** — `scraper` porte
> `/cotes`, `pronostics` porte `/favoris` et `/pronostics`, `resultats` porte
> `/resultats`. **Les chemins ne se recouvrent pas** : deux handlers sur un même chemin et
> c'est le premier routeur monté qui gagne, **sans le moindre avertissement**.

**`utilisateur_optionnel`** sert les routes mixtes : en-tête absent ⇒ `None`, en-tête
**présent mais invalide** ⇒ `401`. Accepter en silence un jeton expiré servirait la partie
publique à quelqu'un qui se croit connecté.

**`exiger_membre`** est réutilisée à quatre endroits, jamais recopiée. **`exiger_secret`**
vérifie le secret **avant** la configuration Supabase — répondre « Supabase n'est pas
configuré » à qui n'a pas le bon secret lui apprendrait quelque chose pour rien.

> **`exiger_admin` est le garde des actions venues de l'application** (version `0.64.0`).
> Il enchaîne `utilisateur_courant` puis relit `profils.is_admin` **en base**, avec la clé
> de service : le jeton dit *qui* appelle et rien d'autre. Ligne absente, colonne absente,
> base non migrée ⇒ **`403`** ; Supabase injoignable ⇒ **`503`**, jamais `403` — « tu n'es
> pas administrateur » serait faux et enverrait chercher la cause du côté des droits.
>
> **Ce garde vaut ce que vaut le droit de colonne sur `is_admin`.** Sans la migration
> `20260827_audit_rls.sql` §2, un membre écrit son propre drapeau depuis les outils de
> développement et franchit la porte. La migration n'est pas un complément de la route,
> elle en est **la moitié**.

> **`POST /admin/action` porte UNE route pour toutes les actions**, et c'est délibéré : le
> garde est la seule chose que ces actions ont en commun, et c'est justement lui qu'on ne
> veut écrire qu'une fois. Une action s'ajoute dans le registre `_EXECUTANTS`, sans
> nouvelle surface à protéger — donc sans risque d'oublier le garde sur la quatrième.
> **Le travail n'y est pas réécrit** : `lancer_scraping` et `traiter_grand_prix` sont les
> fonctions qu'appellent déjà les routes au secret. Un même déclenchement doit avoir le
> même effet, qu'il vienne d'un bouton ou d'un `curl`.
>
> Le statut rendu est `200` et non `202`, y compris pour le scraper : c'est le champ
> `statut` du corps qui distingue `lance` (accepté, compte rendu dans les logs) de
> `traite` (fait). Un `202` sur une route dont une action sur deux est synchrone mentirait
> une fois sur deux.

> **`PATCH /championnats/{id}` refuse en `403`, jamais en `404`.** Le championnat existe,
> l'appelant en est peut-être membre : lui répondre « il n'existe pas » serait faux. Le
> créateur est vérifié **par la route**, à partir de l'identifiant du jeton — la politique
> RLS dit la même chose, mais le backend écrit avec la clé de service, qui la contourne.

> **`LIMITE_CLASSEMENTS = 12`** — rien ne borne le nombre d'adhésions. Au-delà, les cartes
> suivantes s'affichent **sans rang** plutôt que d'allonger indéfiniment la route la plus
> sollicitée de l'app. L'ordre venant de `mes_championnats`, ce sont toujours les mêmes qui
> le portent.

> **L'échec d'une lecture secondaire n'emporte jamais la principale.** Un classement en
> panne fait perdre son rang à une carte, pas la liste ; une lecture de GP en échec laisse
> `prochain_gp` à `null`. **Une liste vide serait un cul-de-sac.** La panne part dans les
> logs avec sa cause.

Helpers PostgREST dans `supabase_client.py` : `selectionner`, `inserer`, `upserter`
(`on conflict … do update`), `mettre_a_jour` (PATCH), `supprimer`, `rpc`.

---

## 13. Authentification

Supabase Auth. `frontend/src/lib/supabase.js` lit `VITE_SUPABASE_URL` et
`VITE_SUPABASE_ANON_KEY`.

> **Si l'une manque, le client vaut `null` au lieu de lever au chargement du module** :
> l'app affiche un message explicite plutôt qu'une page blanche, seul échec vraiment
> illisible sur mobile.

Session persistée en `localStorage`, rafraîchissement automatique, **`detectSessionInUrl`**
et flux **PKCE** — indispensables au retour de Google, d'Apple et des liens envoyés par
email.

**`lib/erreurs.js` est le SEUL point de traduction** de ce qui remonte de
`supabase.auth.*` : reconnaissance par `code` d'abord, repli par expression régulière sur
le message anglais. **Cas particulier traité** : quand la confirmation par email est
active, une inscription sur une adresse déjà prise **réussit en apparence** et renvoie un
utilisateur sans identité — Supabase protège ainsi la liste de ses inscrits. Sans le test
`emailDejaInscrit`, l'utilisateur attendrait indéfiniment un email qui n'arrivera jamais.

Le hook `useIdentiteCourante` relit le pseudo **et la photo** en base à chaque montage,
dans une seule requête — voir `composants.md` §5.
