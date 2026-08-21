# Décisions

**Pourquoi** les choix ont été faits, pas comment ils fonctionnent — le *comment* vit dans
les documents techniques.

Format : la décision, la raison, les alternatives écartées, la conséquence.

---

## 1. Railway pour le backend

**Décision.** FastAPI sur Railway, plan gratuit, un seul processus.

**Raison.** Le projet a besoin d'un runtime **persistant** : le scraping Unibet doit
tourner sur horloge, et le job de résultats interroge OpenF1 toutes les cinq minutes
pendant trois heures après un départ. Railway déploie depuis GitHub sans configuration et
laisse tourner un `AsyncIOScheduler` attaché à la boucle de FastAPI.

**Écarté.**
- *Fonctions serverless (Vercel, Supabase Edge)* — pas de processus persistant. Il aurait
  fallu un cron externe et un état de progression en base, alors que la fenêtre horaire se
  calcule aujourd'hui **sans état conservé nulle part**.
- *`pg_cron` dans Supabase* — le scraping demande des appels HTTP sortants et du parsing
  JSON qu'on n'écrit pas raisonnablement en PL/pgSQL.

**Conséquence.** Le plan gratuit met le service en **veille**. Trois adaptations qui
découlent toutes de là : le cache *stale-while-revalidate* ; les `502/503/504` classés
« réseau » et non « serveur » ; et surtout **la fenêtre de rattrapage de 4 h** du job de
scraping — un déclenchement à l'heure pile serait manqué **définitivement** si le service
dort à cet instant.

**Conséquence à surveiller.** Les deux schedulers supposent **un seul processus**. À
plusieurs instances : `pg_try_advisory_lock` ou worker dédié.

---

## 2. `security definer` sur les fonctions RLS — contre la récursion PostgreSQL

**Décision.** Toutes les fonctions de lecture agrégée sont `security definer` et réservées
à `service_role`. `est_membre(uuid)` l'est aussi et sert dans les politiques elles-mêmes.

**Raison.** Deux problèmes distincts, une seule réponse.

**(a) La récursion.** La politique naturelle s'écrit « il existe une ligne dans
`membres_championnat` avec ce `championnat_id` et `profil_id = auth.uid()` ». Écrite telle
quelle dans une politique **de** `membres_championnat`, elle interroge la table qu'elle
protège : **PostgreSQL détecte la récursion et refuse la requête (`42P17`)**. Ce n'est pas
une lenteur, c'est un refus. `est_membre`, en `security definer`, lit sans repasser par les
politiques.

**(b) L'amputation silencieuse.** Une fonction paramétrée par un championnat lit forcément
les pronostics d'autrui. Sous l'identité de l'appelant, la RLS filtrerait les membres avec
qui il ne partage rien — **exactement ce qu'il faut protéger, mais qui rendrait un
classement silencieusement amputé au lieu d'un refus franc.**

**Écarté.**
- *Sous-requête littérale dans la politique* — `42P17`. **Ne jamais la réinsérer.**
- *Fonctions `security invoker`* — classement faux sans que rien ne le dise. **Un refus
  franc vaut mieux qu'un résultat silencieusement incomplet.**
- *Désactiver la RLS et tout faire passer par le backend* — elle protège l'autre chemin,
  celui du frontend qui lit directement Supabase (§3).

**Conséquence.** **L'autorisation est portée par la route**, qui vérifie l'appartenance
**avant** l'appel. `exiger_membre` est réutilisée à quatre endroits, jamais recopiée.

---

## 3. Deux chemins de données, arbitrés par la politique RLS

**Décision.** Écritures et agrégations par FastAPI ; lectures directes à Supabase là où une
politique RLS décrit exactement le cas.

**Raison.** Sur le plan gratuit, un aller-retour Railway peut coûter un réveil. **L'accueil
est le premier écran de l'app** : lui faire attendre ce délai pour son bloc principal
serait le pire endroit où le payer. Quand la RLS décrit déjà le cas, passer par Railway
n'ajoute **rien qu'un cold start**.

**Écarté.**
- *Tout par le backend* — cohérent, mais chaque écran paierait le réveil.
- *Tout en direct* — impossible : retrouver un championnat par son code alors qu'on n'en
  est pas membre est hors RLS par construction, et les agrégations seraient amputées (§2).

**Conséquence.** **Le critère est la politique RLS, jamais la commodité.** Une route qui
servirait un cas déjà couvert par la RLS serait du code mort ; une lecture directe d'une
donnée qu'aucune politique ne décrit serait un trou.

---

## 4. Les points sont des entiers — cote × 10

**Décision.** `cotes.valeur` est un `integer` valant `round(cote × 10)`. **Rien en base ne
stocke une cote.**

> **Le multiplicateur était 100 jusqu'à la v0.44.0** ; il vaut 10 depuis la v0.45.0.
> **Rien d'autre de cette décision ne change** : le raisonnement porte sur le fait que la
> base stocke un entier de points, jamais sur la valeur du facteur. Les points déjà
> calculés n'ont pas été convertis mais remis à `NULL`, et les cotes effacées pour être
> rescrapées — migration 15, voir `database.md` §6.

**Raison.** Trois à la fois.

1. **C'est la règle du jeu, pas un détail d'implémentation.** Une cote de 2,80 rapporte
   28 points : le nombre affiché **est** la donnée.
2. **Aucun flottant, donc aucune somme approximative.** Un total de saison est une somme
   d'entiers exacte.
3. **Cela rend la règle « ne jamais afficher de cote brute » structurellement tenable** :
   il n'y a **rien à afficher**. Un frontend ne peut pas écrire « ×2,80 » par mégarde.

**Écarté.**
- *`numeric(4,2)`* — exact aussi, mais laisserait la cote disponible à l'affichage, donc la
  règle serait une convention à faire respecter à la main.
- *Conversion à l'affichage* — la question « quel arrondi ? » se reposerait à chaque écran.

**Conséquence.** `lib/format.js` est le **seul** endroit qui habille un nombre de points.
Des tests vérifient qu'aucun « ×N » ne sort des écrans.

**Une exception, et elle porte un autre nom** : `points_fia` (25, 18, 15…) s'écrit
« 25 pts FIA » et **jamais** via `formaterPoints` — les confondre ferait lire le classement
F1 comme un classement de pronostics.

*Cross-contrôle rassurant* : Unibet expose un champ `sort` valant exactement
`round(price × 100)` — zéro écart sur 44 cotes. Il confirme l'arrondi, **pas l'échelle** :
il vaut dix fois les points depuis la v0.45.0.

---

## 5. Scraping à qualifications + 2 h

**Décision.** Le scraping se déclenche **deux heures après les qualifications**, et fige
alors les cotes.

**Raison.** **Pour capter les pénalités.** Les commissaires rendent leurs décisions dans
les heures qui suivent les qualifications ; une grille de départ n'est définitive
qu'ensuite. Scraper avant, c'est enregistrer les cotes d'une grille qui va changer.

Figer garantit ensuite que **tous les joueurs pronostiquent avec exactement les mêmes
cotes** : personne n'est avantagé par le moment où il ouvre l'app.

**Écarté.**
- *Scraper en continu jusqu'au départ* — les cotes bougeraient sous les pronostics déjà
  saisis. Un joueur du samedi soir et un joueur du dimanche matin ne joueraient pas au même
  jeu.
- *Figer juste avant le départ* — la fenêtre de pronostic serait réduite à quelques heures.
- *Un horaire fixe (« samedi 18 h »)* — les GP se courent sur tous les fuseaux.

**Conséquences.**

**(a) Il faut connaître l'heure des qualifications.** D'où `date_qualifications`, et le
repli `date_course − 22 h` quand Unibet ne l'annonce pas — **journalisé à chaque fois**,
pour que le repli ne devienne pas le régime normal sans qu'on s'en aperçoive.

**(b) La DERNIÈRE qualification l'emporte.** Un week-end sprint en compte deux ; retenir la
première ferait figer **un jour trop tôt**.

**(c) `?figer=false` est indispensable.** Sans lui, le premier essai de la saison — passé un
mardi — figerait des cotes de mardi. **C'est arrivé** (voir `bugs-connus.md` §11).

**(d) Le statut seul ne suffit plus à ouvrir les pronostics.** Un `curl` avance le statut,
il n'avance pas l'heure des qualifications : `cotesArretees` exige les deux.

---

## 6. Migrations Supabase appliquées à la main

**Décision.** Les quatorze fichiers SQL sont joués **un par un dans le SQL Editor**. Aucune
CI, aucun `supabase db push` automatique.

**Raison.** **La clé anonyme ne peut pas toucher au schéma `auth`**, et plusieurs migrations
posent un trigger sur `auth.users` ou lisent cette table. Automatiser demanderait de faire
circuler un jeton d'administration de projet — un secret bien plus puissant que la clé de
service, pour un projet qui déploie quelques fois par semaine.

**Écarté.**
- *Supabase CLI en CI* — le jeton ci-dessus, et une CI qui peut réécrire le schéma de
  production.
- *Migrations jouées par le backend au démarrage* — une migration jouée par un service qui
  redémarre tout seul est une migration qu'on ne contrôle pas.

**Conséquences.**

**(a) Toutes les migrations sont idempotentes** (`if not exists`, `create or replace`,
blocs `do $$` qui vérifient l'existence d'une contrainte). Les rejouer ne casse rien.

**(b) Mais PAS dans le désordre.** Plusieurs `create or replace` la même fonction : rejouer
une migration **antérieure** restaure sa version d'avant. **Le tableau des conflits d'ordre
est dans `database.md` §6** — c'est la seule chose à surveiller.

**(c) Un décalage code / base est possible.** D'où la règle des **valeurs par défaut sur
tout nouveau champ d'un modèle Pydantic** : un backend déployé avant sa migration perd un
champ au lieu de rendre `500` sur toute la réponse.

**(d) Elles ne se vérifient pas toutes seules.** Les onze premières ont été jouées contre un
PostgreSQL jetable ; **les 12, 13 et 14 ne l'ont pas été** (voir `roadmap.md`).

---

## 7. OpenF1 pour les résultats

**Décision.** `api.openf1.org` comme source des résultats de course.

**Raison.** Gratuite, sans clé, et **elle publie en UTC** — ce qui en a fait la source
autorisée pour trancher le fuseau d'Unibet. Elle expose tout ce dont la validation a
besoin : classement, abandons, safety car, meilleur tour, grille de départ.

**Écarté.**
- *API officielle F1* — pas d'accès public documenté.
- *Ergast / jolpica* — ne donne ni `race_control` ni les tours, donc ni safety car ni
  meilleur tour.
- *Scraper les résultats sur Unibet* — le bookmaker n'est pas une source de résultats, et
  ce serait un second scraper à maintenir.

**Conséquences.**

**(a) On interroge par `session_key`, jamais par `meeting_key`** — un *meeting* est un
week-end entier, et sa réponse mélange cinq sessions.

**(b) Le rapprochement GP ↔ course se fait sur la DATE**, jamais sur le nom (« GP Pays Bas »
contre « Dutch Grand Prix »), avec un refus au-delà de 36 h d'écart : **mieux vaut ne pas
noter un GP que le noter sur les résultats d'un autre.**

**(c) Le rapprochement des NOMS de pilotes est le point le plus fragile.** Cinq clés par
pilote, plus des alias. **Une clé revendiquée par deux pilotes est retirée** plutôt
qu'attribuée au premier venu.

**(d) `donnees_brutes` est conservé** — pour rejouer un calcul **sans rappeler l'API**, des
semaines après la course, quand un validateur manquant est enfin écrit.

**(e) 3 requêtes/seconde maximum**, `429` au-delà. Une récupération en enchaîne six.

---

## 8. `NULL` et `0` ne se confondent jamais

**Décision.** `points_gagnes` a trois états : `NULL` (inconnu **ou non validé**), `0`
(raté), `> 0` (réussi).

**Raison.** **Marquer « raté » un pronostic qu'on n'a pas su valider volerait le joueur en
silence, et rien à l'écran ne permettrait de s'en apercevoir.** Les marchés Unibet varient
d'un GP à l'autre : ce cas n'est pas une hypothèse d'école, et seules trois des neuf
familles reconnues ont été confrontées à de vrais libellés.

`NULL` se **voit** dans les logs, s'affiche « en attente », et se **rattrape** par un
second passage — le JSON brut étant conservé, il suffit d'écrire le validateur manquant.

**Écarté.** *Tout mettre à 0 par défaut* — le score serait faux et personne ne le saurait.

**Conséquence.** La convention se propage à toute la chaîne : `meilleure_cote` vaut `NULL`
et non `0` pour qui n'a rien réussi ; `mes_points` vaut `NULL` sur un GP non jugé ; un
total ignore les non-jugés au lieu de les compter zéro ; l'interface distingue « Aucun
prono », « Pronos pas encore validés » et « 0 pts ».

**Corollaire** : `attribuer_points` n'écrit **que** les `NULL` — c'est la base qui porte
l'idempotence, et **le `0` d'un raté n'est jamais réécrit**.

---

## 9. Le calendrier de la saison vit côté frontend

**Décision.** `lib/calendrier2026.js` porte les douze GP. La base ne garde que ce qu'elle
seule sait.

**Raison.** **Unibet n'expose jamais que le GP suivant** : `public.grands_prix` n'en
contient qu'un. Un calendrier lu en base afficherait une course au milieu d'une saison qui
en compte douze. **Le calendrier de la F1 est une donnée publique et stable — il n'a pas à
être découvert chez un bookmaker.**

**Écarté.**
- *Une table `calendrier` en base* — une migration par correction de date, et une donnée
  publique traitée comme un secret.
- *Une seconde source (API de calendrier)* — une dépendance de plus pour douze lignes.

**Conséquences.** **Les douze cartes s'affichent quoi qu'il arrive** — Railway endormi, base
vide, appel en échec : l'écran reste plein, seuls les états manquent. C'est l'inverse d'un
écran de liste ordinaire. Et **la table est à mettre à jour chaque saison**, avec les
drapeaux et les tracés, les trois devant porter les mêmes slugs.

---

## 10. Une source unique par question

**Décision.** Toute question à laquelle plusieurs endroits doivent répondre **de la même
façon** a exactement **un** propriétaire.

| Question | Propriétaire |
|---|---|
| Combien vaut ce pronostic ? | `lib/format.js` |
| De quelle couleur est cette écurie ? | `lib/ecuries.js` |
| Que porte cette voiture ? | `livreeDuMembre` |
| Quel est l'état de ce GP ? | `ETATS_GP` |
| Les cotes sont-elles arrêtées ? | `cotesArretees` |
| Où va ce bouton de retour ? | `origineRetour` |
| La barre s'affiche-t-elle ici ? | `lib/navigation.js` |
| Quelle encre sur cet aplat ? | `tonalites` / `encreSurAplat` |

**Raison.** **Deux textes écrits séparément divergent au premier ajustement, et le symptôme
est toujours discret** : un GP qui change d'état en passant d'un onglet à l'autre, un membre
en livrée Ferrari au classement et à ses couleurs sur la piste, un bloc amber recevant du
texte blanc parce qu'un écran l'a écrit de mémoire.

**Écarté.** *La duplication « pour découpler »* — les deux copies ne sont pas découplées,
elles sont **d'accord par accident**.

**Conséquence.** Certains modules sont partagés entre deux calculs pourtant différents.
Les deux calendriers **calculent** leur état différemment (ils n'ont pas les mêmes données)
mais **lisent la même table de libellés et de couleurs** : c'est ce qui doit être commun,
et rien de plus.

---

## 11. Les palettes hors thème, à périmètre borné

**Décision.** Quatre familles de couleurs vivent hors du design system : 20 couleurs de
voiture, 11 teintes d'écurie, 13 drapeaux, 6 aplats de bloc.

**Raison.** La palette compte **sept couleurs**. Dix livrées distinctes, onze écuries ou
douze drapeaux n'en sortiraient pas — et les y forcer donnerait des voitures
indistinguables ou des drapeaux faux.

**Écarté.** *Étendre le design system* — le rouge de la marque cesserait d'être le rouge de
la marque.

**Conséquence.** **Le périmètre est la contrepartie, et il est strict** : ces couleurs ne
peignent **que** l'objet qu'elles décrivent — jamais un fond d'écran, un bouton ou un texte
d'interface. Des tests vérifient le cloisonnement. Quatre des aplats de bloc reprennent
d'ailleurs le design system plutôt que d'inventer un ton de plus.

---

## 12. Le contraste se mesure, il ne se choisit pas

**Décision.** Chaque encre posée sur une surface est **calculée**, jamais écrite par
l'écran.

**Raison.** **Les valeurs prescrites à l'œil se sont révélées fausses plus souvent que
justes** :

| Prescrit | Mesuré | Retenu |
|---|---|---|
| Voile de drapeau à 0,30 | blanc à **2,11:1** | dérivé, 0,42 minimum |
| Rang à 30 % d'opacité | **1,6:1** sur le bordeaux | 80 % (3,20:1 au pire) |
| Icône ambre sur pastille pâle | **2,2:1** | aplat plein + encre calculée |
| `texte-doux` sur beige | **2,0:1** | marron `secondaire` (9,4:1) |
| Bande blanche à 85 % | vert à **3,45:1** | opaque |

**Écarté.** *Faire confiance à l'œil* — sur un fond beige texturé, il se trompe
systématiquement dans le même sens.

**Conséquence.** `tonalites`, `encreSurAplat`, `encreSurBlanc`, `encreSur` et
`voileNecessaire` **portent l'arbitrage une fois pour toutes**. Un aplat ou un drapeau
ajouté demain reçoit la bonne réponse sans que personne ne refasse le calcul.

**Corollaire mesuré** : l'amber n'existe **que comme aplat**, jamais comme encre.

---

## 13. Un pronostic compte dans tous les championnats

**Décision.** Un joueur remplit **un** pronostic par GP, qui compte dans **tous** ses
championnats. Le championnat dit **qui** classer, pas quels pronostics compter.

**Raison.** C'est le modèle mental juste : on pronostique **une course**, pas « une course
dans un championnat ». Cloisonner obligerait à ressaisir les mêmes pronostics autant de
fois qu'on a de championnats.

**Écarté.** *Des pronostics par championnat* — insupportable à la saisie, et il faudrait
décider ce qui arrive aux pronostics quand on rejoint un championnat en cours de saison.

**Conséquence, et c'est le point délicat.** Le `TODO` initial demandait d'effacer les
pronostics d'un membre qui quitte un championnat. **Les effacer au départ d'un seul
détruirait son classement dans les autres.** Ils ne sont donc effacés que **lorsqu'il ne
lui reste aucune adhésion** — l'intention (aucun pronostic orphelin ne survit) sans le
dommage collatéral.

---

## 14. Le drapeau `is_admin` décide d'un affichage, jamais d'un droit

**Décision.** `is_admin` conditionne l'affichage de la section d'administration. Les routes
restent fermées par `X-Admin-Secret`.

**Raison.** Le garde existait déjà, à temps constant, avec « variable absente ⇒ route
fermée ». Y ajouter une vérification de drapeau **lu côté client** n'aurait rien renforcé.

**Écarté.** *Une route qui exige le jeton et vérifie `is_admin` en base* — c'est la bonne
réponse le jour où ce sera nécessaire, et **le secret ne quitterait alors jamais Railway**.
Ce n'est pas un ajustement de l'écran mais une réécriture de la route.

**Conséquence assumée, et il faut la connaître.** **Le secret voyage en clair dans le
bundle** : Vite inline les `VITE_*` à la construction. Quiconque ouvre les outils de
développement le lit, administrateur ou non. Et la politique « Chacun modifie son profil »
porte sur la **ligne**, pas sur la colonne : un membre peut écrire son propre `is_admin`.

**Ce que cela protège encore** : un passant qui ne lit pas le bundle, et les autres origines
(le CORS n'autorise que les nôtres). **Ce que cela ne protège plus** : un déclenchement de
scraper par quelqu'un de déterminé.

---

## 15. Le mode admin est un état de session

**Décision.** `modeAdminActif` vit en `useState` dans `AuthContexte`. **Il repart éteint à
chaque rechargement.**

**Raison.** C'est une préférence d'affichage valable le temps qu'on regarde. Le persister
lui donnerait le défaut documenté sur `pseudo` et `is_admin` — **une valeur qui survit à ce
qu'elle décrit** — et un mode de vérification demande un geste explicite.

**Conséquence, et c'est ce qu'il ne faut pas défaire.** Le contexte expose **`modeAdmin`**,
la conjonction `estAdmin && modeAdminActif`, **nommée une fois plutôt que recopiée**.

> **Une conjonction qu'on recopie finit par être écrite à moitié, et la moitié qui saute est
> toujours la même** — le mode, parce qu'il est le terme récent. On obtiendrait une surface
> visible interrupteur éteint, c'est-à-dire le défaut même que ce mode existe pour
> supprimer.

`MonProfil.jsx` est le **seul** endroit qui lise `estAdmin` et non `modeAdmin` — la section
doit rester visible pour pouvoir rallumer l'interrupteur. **Un commentaire le dit à son
point de montage**, sans quoi la prochaine session l'« alignerait » sur les autres.

### 15 bis. Le mode prévisualisation ment à l'écran, jamais en base

**Décision (version `0.44.0`).** Un second interrupteur, **subordonné au premier**, fait
voir à l'administrateur l'application comme si les cotes du Grand Prix étaient déjà figées.
`modePrevisualisationActif` vit en `useState` dans `AuthContexte`, exactement comme
`modeAdminActif`, et le contexte expose la conjonction des **trois** termes sous le nom
`modePrevisualisation`.

**Raison.** Vérifier l'écran des pronostics avant les qualifications demandait jusqu'ici
d'écrire en base — `update … set statut = 'cotes_figees'` — c'est-à-dire de casser la donnée
pour regarder l'interface. C'est très exactement l'accident du GP des Pays-Bas
(`bugs-connus.md` §4). Le mode déplace la question de la base vers l'affichage.

**Ce qu'il ne touche pas, et c'est sa définition** : aucune écriture, aucune route, aucun
statut. Les autres membres ne voient rien de différent, et le job automatique du samedi
continue de figer les cotes à son heure.

> **Il ne lève qu'une condition : `cotesArretees`.** C'est la seule fonction du projet qui
> lise le statut `cotes_figees`. Les trois surfaces qui portent un bouton de pronostics
> écrivent donc `cotesArretees(gp) || previsualisation` — et **rien d'autre**. En
> particulier `etat.cle === "ouvert"` reste entier : il se lit dans les données, pas dans le
> statut, et ouvrir un tableau de cotes vide ne montrerait rien de ce que le mode existe
> pour montrer.

**Le drapeau descend par prop dans `BlocProchainGp` et `CarteGpSaison`**, jamais par
`useAuth`. Le premier est exporté nommément pour être rendu hors navigateur, sans
`AuthProvider` : `useAuth` lève dès qu'il ne trouve pas de contexte, et l'appeler là rendrait
ce rendu impossible. Les écrans, eux, vivent dans le contexte et le lisent.

**Une marque à l'écran est la contrepartie obligatoire.** La pastille
« Prévisualisation » (`BandeauPrevisualisation.jsx`) est montée dans `App.jsx`, hors de
`<Routes>`, pour la raison structurelle de `NavBarre` — `Ecran` porte un `transform`, qui
ferait de lui le bloc conteneur de tout `position: fixed` posé dessous. Sans elle, un
administrateur qui a allumé l'interrupteur trois écrans plus tôt conclurait de bonne foi que
le job du samedi a tourné : **c'est le seul défaut qu'un mode de vérification puisse
avoir.**

**Éteindre le mode admin éteint aussi la prévisualisation, en état brut.** La conjonction
suffirait à la neutraliser, mais l'interrupteur resterait allumé sous la surface et se
rallumerait tout seul au prochain « Mode admin actif ». Un interrupteur qu'on n'a pas touché
et qui revient allumé est un interrupteur auquel on cesse de se fier.

---

## 16. Ne pas supprimer le code qui redevient utile

**Décision.** Le code remplacé mais éprouvé reste en place, **simplement non monté**.

| Gardé | Redevient utile quand |
|---|---|
| `BoutonsOAuth` (`OAUTH_ACTIF = false`) | les clés OAuth sont renseignées |
| `Onglets` | Unibet ouvre dix marchés |
| `ApercusApp` | les vraies captures existent |
| `TraceCircuit` | une vignette de 20 × 32 px est nécessaire |
| `chargerGrandsPrixRestants` | le calendrier complet est en base |

**Raison.** Ce code est **déjà écrit, déjà vérifié**. Le supprimer et le réécrire plus tard
coûte davantage, et la deuxième version n'aurait pas les mêmes tests.

**Écarté.** *Supprimer et compter sur `git`* — personne ne va chercher dans l'historique un
composant dont il ignore qu'il a existé.

**Conséquence.** **Aucun coût de bundle** : le code n'étant plus importé, l'arbre est
secoué et les chaînes concernées sont **absentes du bundle de production** — vérifié.

**Une règle de mise en œuvre** : le retour anticipé d'un composant désactivé se place
**après les hooks**, jamais avant. React interdit un `return` qui court-circuiterait
`useState`.

---

## 17. Un réglage sans effet quitte le DOM

**Décision (version `0.46.0`).** Sous un skin d'écurie, **Coque et Ailerons ne sont pas
grisés : ils n'existent plus**. Ils partent par un repli
(`frontend/src/composants/Repli.jsx`) puis sont démontés.

**Raison.** Une livrée d'écurie a ses couleurs. Les deux sélecteurs ne peignent alors plus
rien — ni l'aperçu, ni la vue piste, ni le classement. Les laisser grisés en garderait le
pire : deux arrêts de tabulation et deux libellés lus par un lecteur d'écran, pour des
commandes dont l'effet est nul. **Un réglage sans effet est pire absent que présent-inerte,
parce qu'inerte il demande encore qu'on comprenne pourquoi.**

**Ce que la décision retourne.** La version `0.40.0` avait tranché l'inverse, et son motif
était bon : un membre qui essaie un skin doit voir vers quoi il revient. Ce service est
désormais rendu par **la case « Ma livrée » du sélecteur de skin**, qui montre les deux
couleurs en diagonale. La question a changé de propriétaire, elle n'est pas restée sans
réponse — c'est la condition sans laquelle ce retournement n'aurait pas été fait.

**L'ordre des quatre rangées suit la portée de chacune** : Numéro (s'écrit sur le museau
quelle que soit la livrée), Skin (commande les deux suivantes), Coque, Ailerons. Un
contrôle est posé **juste au-dessus de ce qu'il gouverne** ; posé en dessous, il faudrait
un libellé pour dire ce qu'il commande.

**Pourquoi ça s'anime, et c'est la seule raison retenue.** Retirer deux rangées à l'image
suivante fait perdre à la carte quatre-vingt-dix pixels d'un coup : l'avertissement de
numéro et le bouton d'enregistrement sautent **sous le doigt**. C'est le cas « changement
brutal » — pas de la décoration. Le repli emprunte le `grid-template-rows: 0fr → 1fr` de
l'accordéon, qui anime une hauteur inconnue sans jamais la mesurer en JavaScript.

> **`.t-repli` n'est pas un fork de `.t-acc`, et le sélecteur distinct est obligatoire.**
> Les règles de l'accordéon emploient un combinateur de **descendance**
> (`.t-acc[data-open="true"] .t-acc-panel`). Un `.t-acc` ouvert enveloppant les deux
> `SelecteurCouleur` — qui sont eux-mêmes des `.t-acc` — **ouvrirait leurs grilles de
> couleurs avec le sien**. `.t-repli` reprend donc les trois jetons `--acc-expand`,
> `--acc-collapse` et `--acc-ease` **sans en créer un seul**, et ses propres règles
> descendent en enfant **direct**.

**La durée du démontage est lue dans la feuille compilée** (`dureeCss("--acc-collapse")`),
jamais recopiée en constante JavaScript. Deux valeurs écrites séparément divergent au
premier ajustement, et le symptôme serait discret : des enfants retirés une image trop tôt,
c'est-à-dire un repli qui se termine par le saut qu'il existait pour supprimer.

**« Ma livrée » est le défaut, et il l'était déjà** : `livree_mode text not null default
'perso'` depuis la migration 12 (`20260819124500_livree_ecurie.sql`), et `livreeDuMembre`
rend `perso` pour toute ligne qui ne dit pas autre chose. **Aucune migration n'a été
nécessaire** — un nouveau joueur voit « Ma livrée » sélectionné, Coque et Ailerons
visibles, sans avoir rien choisi.

---

## 18. Deux listes d'aplats, pas une seule élargie

**Version `0.48.0`.** Les six teintes de championnat sont une **liste séparée**
(`COULEURS_CHAMPIONNAT`) et non six entrées de plus dans `COULEURS_BLOC`.

**Ce sont deux questions, et elles n'ont pas la même contrainte.** La couleur d'un marché
est un **repère fixe** — rouge = vainqueur, bleu = podium, vert = écurie — que rien ne
doit faire bouger. La couleur d'un championnat sert à **distinguer des championnats entre
eux**, et elle peut changer de palette sans que personne ne perde ses repères. Une liste
unique aurait lié les deux : retoucher les cartes de l'accueil aurait déplacé la couleur
des en-têtes de marché, ou obligé à un sous-ensemble nommé, c'est-à-dire à la même
séparation mais implicite.

**Ce que la palette sombre a réellement acheté, et c'est mesuré.** Les six teintes tiennent
le blanc de **10,35:1** (tomate séchée) à **18,12:1** (minuit). Les aplats clairs qu'elles
remplacent étaient le point faible du calcul de contraste depuis l'origine : le terracotta
`#C4622D` ne valait que 4,41:1 sous le damier, l'encre secondaire à 70 % y tombait à
2,79:1, et l'amber `#E8A020` basculait carrément sur l'encre foncée. Sur les six nouvelles,
**le pire cas de l'encre secondaire est 4,97:1** (terreau, sous le damier et sous la lueur)
et le rang à 80 % ne descend jamais sous 5,92:1. Le commentaire de `tonalites` qui
défendait le plancher de 80 % **reste vrai et reste utile** : il protège l'aplat clair du
jour où il reviendrait, et il documente pourquoi 30 % était faux.

**L'attribution n'a pas bougé, et c'est délibéré.** `couleurChampionnat` puise toujours par
**empreinte de l'identifiant**, pas par rang dans une liste — voir le commentaire de
`lib/couleurs.js`. Le prix reste le même : avec six teintes, deux championnats d'une même
liste peuvent tomber sur la même. La demande de la version `0.48.0` parle de « couleurs
tournantes » couvrant « jusqu'à six championnats distincts », ce qu'un modulo sur le rang
garantirait. Il **casserait toujours l'écran de détail**, atteint par lien direct, qui ne
connaît aucune liste et ne saurait pas quelle couleur peindre ; et deux membres du même
championnat le verraient de deux couleurs différentes. Reconnaître un championnat à sa
couleur d'un écran à l'autre reste ce qui a le plus de valeur.

---

## 19. La vue piste ne garantit plus le non-chevauchement, elle le mesure

**Version `0.49.0`.** L'ancien placement partait des **scores** : il groupait les ex æquo,
posait chaque groupe proportionnellement à ses points, puis **relâchait les écarts en deux
passes** — une descendante depuis le leader, une montante pour rattraper ce qui débordait
en bas — et réduisait toutes les voitures du même facteur jusqu'à ce que la garantie tienne.

**Le prix était que la hauteur d'une voiture ne disait plus tout à fait ses points.** Dès
que deux scores voisins se rencontraient, la relaxation les écartait : la position affichée
devenait un compromis entre le score et la place disponible. Et la réduction était
**globale** — un seul groupe serré rapetissait toutes les voitures de l'écran, y compris
celles qui avaient la place.

Le nouveau système sépare les deux questions.

| Question | Qui répond | Ce qui en dépend |
|---|---|---|
| à quelle hauteur ? | **le score, seul** | rien d'autre |
| de quelle taille, et à quelle abscisse ? | **la géométrie** | la hauteur, déjà fixée |

La passe 1 tend l'échelle sur `max` et `min` — la zone de jeu est donc **toujours
intégralement occupée**, et une hauteur se relit en points sans correction. La passe 2
regarde ce qui se chevauche **à l'écran**, sans jamais consulter un score, et ne réduit que
les voitures concernées.

**Deux conséquences assumées.**

La première : un groupe peut réunir des **scores différents**, et ses voitures gardent
alors des hauteurs différentes. Le résultat est un escalier en travers de la piste plutôt
qu'une rangée alignée — c'est exact, et c'est ce que la règle « une hauteur, un score »
impose.

La seconde : la légende de droite a disparu. Elle chiffrait **un groupe**, ce qui n'a plus
de sens dès qu'un groupe est géométrique, et elle occupait les 104px de marge que les
voitures utilisent désormais d'un kerb à l'autre. **Le score est passé sous chaque
voiture** — ce qui en dit plus qu'avant, un nombre par personne au lieu d'un par égalité.
Il s'efface quand la voiture a touché son plancher de taille : les cellules sont alors plus
étroites qu'un nombre à trois chiffres, et vingt scores côte à côte ne feraient pas vingt
nombres mais une bavure. La liste `sr-only` de l'écran, elle, les donne tous.

