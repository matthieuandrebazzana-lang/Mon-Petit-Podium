# Bugs connus et résolus

Un bug par section : **symptôme**, **cause réelle**, **correctif**, **ce qu'il ne faut pas
refaire**.

> **Ce document contient surtout des bugs RÉSOLUS**, et c'est délibéré : ceux dont la cause
> n'était pas celle qu'on croyait sont les plus coûteux à redécouvrir. Les défauts encore
> ouverts sont marqués **⚠️ OUVERT**.

---

## 1. `position: relative` bat `sticky` par ordre d'émission dans `@layer utilities`

**Symptôme.** Sur le tableau des cotes, l'en-tête « ECURIE VAINQUEUR » recouvrait Ferrari
et Mercedes **dès le chargement**, sans qu'on ait défilé.

**Cause réelle.** Un `sticky` non défilé ne recouvre rien : il reste dans le flux. Le
défaut était ailleurs. L'en-tête portait
`section-collante rounded-carte shadow-carte relative`. Les deux classes de position ont
**la même spécificité (0,1,0)** et vivent dans la **même couche** `utilities` : c'est donc
**l'ordre d'émission dans la feuille compilée** qui tranche, jamais l'ordre écrit dans
l'attribut `class`.

Vérifié sur le CSS de production : `.section-collante` était émis à l'octet 10216,
`.relative` à 10482. **`position: relative` gagnait.**

Et un élément *relatif* n'ignore pas son `top` — **il s'en décale**. L'en-tête était donc
poussé vers le bas de `--entete-hauteur`, soit **~107 px** sur un iPhone à encoche : pile
la hauteur de la première rangée de widgets, qu'il venait recouvrir en permanence. Le
`z-index: 20` s'appliquait normalement, d'où un recouvrement franc.

**Correctif, en deux temps.** `relative` retiré du JSX (redondant : `sticky` établit déjà
le bloc conteneur) **et** `.section-collante` sortie de `@utility` pour devenir une règle
**hors de toute couche** — elle l'emporte alors sur toutes les règles empilées.

**Ne pas refaire.** Le second point seul aurait réparé l'écran jusqu'à ce que quelqu'un
remette `relative`. **Devant un comportement de mise en page inexplicable, regarder le CSS
compilé** (`grep -o '\.ma-classe{[^}]*}' dist/assets/*.css`), pas le JSX.

---

## 2. `gap` inerte sous `display: block` hors couche Tailwind

**Symptôme.** Les douze cartes de l'onglet Calendrier se touchaient. Plus tard : les cartes
de championnat collées à « Créer un championnat » sur l'accueil.

**Cause réelle.** Le `gap-3` était **bien écrit** — et c'est précisément ce qui rendait le
défaut illisible : **la classe était là, elle ne s'appliquait pas.**

`.t-stagger-line` pose `display: block`, déclaré **hors de toute couche Tailwind**. Une
règle non affectée à une couche l'emporte sur **toutes** les règles empilées, quelle que
soit leur spécificité : `.flex` vit dans `@layer utilities`, elle perd. Le `<Bloc>` restait
en `display: block`, **où `gap` n'a aucun effet**.

**Correctif.** Le conteneur flex passe **à l'intérieur** du bloc. **Rien n'est touché à
`index.css`** : déplacer `.t-stagger-line` dans une couche changerait la précédence de
toutes les transitions de l'app d'un coup, pour réparer une gouttière.

**Ne pas refaire.** **Jamais de `flex`, `gap` ou `justify-*` sur un `<Bloc>`.** Trois
occurrences ont été corrigées (accueil, liste des championnats, championnat). La même
mécanique vaut pour `.t-skel-bar`, qui peint sa couleur hors couche — d'où le style **en
ligne** obligatoire pour la battre.

**Variante attrapée par un aperçu rendu** : la même cause avait laissé l'**icône du logo
calée à gauche** sur la page publique. Le `flex flex-col items-center` était bien écrit, sur
un `Bloc`.

---

## 3. `viewBox` prescrites fausses — cinq fois

**Symptôme.** Dessins décentrés, rognés, ou flottant dans du vide.

**Cause réelle.** Les tranches arithmétiques d'une planche supposent que les dessins sont
jointifs, de même taille et régulièrement espacés. **Ils ne le sont jamais.**

| Planche | Prescrit | Réel |
|---|---|---|
| `flags.svg` | 6 tranches de 463 | hauteurs de 305 à 417, non jointives |
| `logo.svg` | `0 0 133.55 120` / `0 121 …` | 2ᵉ logo à y=154,50, 38 unités de vide horizontal |
| `matti.svg` | 4179,74 / 11 = 379,98 | 124 unités de vide sous chaque tuile |
| `VOITUREs_am.svg` | moitiés (0–391, 391–782) | 29,39–317,48 et 459,01–747,10 |
| `voiture.svg` | — | ~2× la largeur du dessin en marge vide |

**Correctif.** **Les vraies boîtes englobantes**, mesurées en échantillonnant les courbes
de Bézier. **Aucune coordonnée n'est réécrite : c'est le cadrage qui bouge.**

**Ne pas refaire.** **Toujours mesurer, jamais diviser.** Et **ne pas serrer chaque
cadrage indépendamment** quand les dessins vivent dans le même système de coordonnées :
leurs tailles relatives sont voulues. Les icônes de la barre partagent un carré de 74
unités **centré sur chaque boîte** — les serrer les ramènerait toutes à la même taille
apparente.

*Effet de bord du dernier cas* : la `viewBox` de `voiture.svg` portait tant de vide qu'à
hauteur CSS égale la nouvelle voiture paraissait plus grande. **Deux appelants ont dû être
ajustés** (vue piste 56×68 → 29×59, résultats `w-[28px]` → `w-[17px]`).

---

## 4. Double conversion UTC de `date_course` — deux heures d'avance

**Symptôme.** Le widget de l'accueil annonçait 13 h pour un départ à 15 h.

**Cause réelle.** Le champ `start` d'Unibet est **déjà en UTC**. Le scraper le lisait
**comme de l'heure de Paris**, le convertissait une seconde fois, et enregistrait deux
heures trop tôt. La conclusion contraire, posée à l'étape 4, était **fausse** — OpenF1,
source autorisée en UTC, concorde à la minute près sur les quatre séances du week-end.

> **Ce n'était PAS un défaut d'affichage.** `date_course` gouverne la fermeture des
> pronostics (départ − 5 min) et le job de résultats (départ + 1h30, fenêtre 3 h). Avec
> deux heures d'avance, les pronostics se fermaient à 12h55 pour une course à 15h00, et le
> job interrogeait OpenF1 de 12h30 à 15h30 — **il épuisait sa fenêtre pendant que la course
> se courait.**

**Correctif.** `FUSEAU_UNIBET = ZoneInfo("UTC")`, avec le relevé des quatre séances en
commentaire.

**Ne pas refaire.** **Deux commentaires PÉRIMÉS annoncent encore la conversion depuis
Paris** : celui de la migration 3 (`grands_prix.date_course`) et celui de `tzdata` dans
`requirements.txt`. Les migrations sont historiques et ne sont pas réécrites — **s'y fier
referait le bug**. La vérité est dans `app/scraper/unibet.py` et dans `scraper.md` §4.

⚠️ **La ligne du GP des Pays-Bas est encore fausse en base** — voir §11.

---

## 5. `chargerProchainGp` filtrait sur `a_venir` seul

**Symptôme.** Dès que le job du samedi figeait les cotes, l'accueil annonçait le GP de la
semaine **précédente** — « Dernier GP », bouton « Voir les résultats » — **pendant tout le
week-end de course**, c'est-à-dire précisément quand il faut pronostiquer.

**Cause réelle.** La lecture filtrait `.eq("statut", "a_venir")`. Un GP figé quitte cette
liste : la lecture ne trouvait plus rien et `chargerAccueilGp` retombait sur
`chargerDernierGpCouru`.

**Correctif.** Retenir les **deux statuts non courus**, `a_venir` **et** `cotes_figees` —
le filtre qu'appliquaient déjà `GET /championnats/moi` et `chargerGrandsPrixRestants`.

**Ne pas refaire.** Le défaut a été découvert en voulant conditionner le bouton à
`cotes_figees` : dans un bloc qui ne pouvait afficher que des GP `a_venir`, la condition
aurait donné du **code mort**. **Trois lectures doivent dire la même chose** sur les
statuts non courus.

---

## 6. Les modèles Pydantic filtraient `livree_mode` et `livree_ecurie`

**Symptôme.** Aucun skin d'écurie ne s'affichait — ni sur la piste, ni au classement, ni
au tableau des résultats.

**Cause réelle.** La migration 12 faisait bien servir les deux colonnes par
`classement_du_championnat` et `pronostics_du_championnat`, et `livreeDuMembre` savait les
lire. **Entre les deux, les modèles Pydantic ne les déclaraient pas.** Le `response_model`
de FastAPI **ne laisse passer que les champs du modèle** : les colonnes étaient filtrées
**avant d'atteindre le client**. `livreeDuMembre` retombait sur `perso`, son repli
volontaire, et **aucun skin n'a jamais pu s'afficher.**

**Correctif.** Champs ajoutés à `LigneClassement` et au modèle des membres, **avec des
valeurs par défaut** — sinon un backend déployé avant la migration rendrait **toute** la
réponse en `500`.

**Ne pas refaire.** **Une colonne ajoutée en base ne suffit pas** : la chaîne complète est
`migration → fonction SQL → COLONNES_* → modèle Pydantic → frontend`. Le maillon Pydantic
échoue **silencieusement**. Même piège : `is_admin` (traité au moment de l'ajout).

*Effet de bord* : les lignes déjà en `localStorage` avaient été écrites par le backend qui
filtrait. La clé de cache a dû être **versionnée** (`classement:{profil}:v2:{championnat}`),
le marqueur placé **après** l'identifiant du compte pour que `oublierCachePrefixe`
continue de tout balayer.

---

## 7. Transition sur `transform` alors que Tailwind 4 compile vers `translate`

**Symptôme.** Aucun — **et c'est le pire**. Le pouce de l'interrupteur aurait sauté d'un
bout à l'autre de sa piste, **et le JSX aurait eu exactement la même tête.**

**Cause réelle.** La règle transitionnait `transform`. Or **Tailwind 4 compile
`translate-x-*` vers la propriété indépendante `translate`** :
`.translate-x-\[18px\]{--tw-translate-x:18px;translate:var(--tw-translate-x) var(--tw-translate-y)}`.
La transition ne portait donc **sur rien du tout**.

**Correctif.** Transitionner `translate`. Les deux propriétés se composent aussi bien sur
le GPU — c'est le **nom** qui devait suivre l'utilitaire.

**Ne pas refaire.** Un test **lit la règle de l'utilitaire dans le CSS compilé**, en extrait
la propriété réellement écrite, et vérifie que c'est bien celle qui est transitionnée.
Éprouvé dans les deux sens.

---

## 8. `setDonnees` n'écrit pas le cache — les couleurs qui réapparaissent

**Symptôme.** Enregistrer une couleur la posait sur la vue piste, mais **revenir sur le
profil ressortait l'ancienne**.

**Cause réelle — DEUX causes, et les corriger toutes les deux était nécessaire.**

1. **`setDonnees` ne touche que l'état React.** `useDonnees` relit le `localStorage` **au
   montage**, dans l'initialiseur de `useState` : le cache gardait la version d'avant, et
   c'est **lui** qui était servi au retour.
2. **L'état de saisie ne suivait jamais le serveur.** L'effet s'écrivait
   `setCouleur1((actuelle) => actuelle ?? profil.couleur1)` : il n'initialisait qu'une
   fois. Le garde-fou était voulu — sans lui, la revalidation effacerait une couleur en
   cours de choix — mais il **figeait aussi la valeur périmée du cache définitivement**.

**Correctif.** `remplacer(valeur)` ajouté à `useDonnees` (état **et** cache). Un drapeau
`edite` remplace le `??` : tant que le membre n'a rien touché, la saisie suit le profil
servi ; dès qu'il touche à quelque chose, elle se fige.

**Ne pas refaire.** **`setDonnees` ne sert qu'aux mises à jour optimistes que la réponse
serveur confirmera de toute façon.** Toute écriture durable passe par `remplacer`.

*Troisième défaut trouvé en rendant l'écran avec la feuille compilée* : le numéro était lu
dans `saisie` et non dans le repli `saisie ?? saisieDepuis(profil)`. **Tout ce que l'écran
lit passe désormais par `voiture`, jamais par `saisie`.**

---

## 9. Le pseudo de l'accueil venait du jeton, pas de la base

**Symptôme.** Renommer quelqu'un dans `public.profils` ne changeait rien à l'écran, quel
que soit le nombre de rechargements.

**Cause réelle.** `useAuth().pseudo` lit `user_metadata.pseudo`, **une copie déposée à
l'inscription** qui vit dans le jeton. Elle n'est réécrite que par `auth.updateUser` : un
`update` SQL ou un trigger la laissent intacte. **Et une session Supabase se rafraîchit
indéfiniment.**

**Correctif.** `chargerIdentite` + `useIdentiteCourante` (nommés `chargerPseudo` et
`usePseudoCourant` jusqu'à la version `0.52.0`), qui lisent la base **à chaque montage**,
**sans cache**, avec **repli sur le jeton**.

**Ne pas refaire.** `AuthContexte.jsx` documente désormais que son `pseudo` est une copie
figée. Le défaut était borné à l'accueil — vérifié : `pseudo` n'est déstructuré de
`useAuth()` **qu'à un seul endroit**.

---

## 10. Exclusion croisée filtrée par `id_outcome_unibet`

**Symptôme.** Un pilote choisi comme vainqueur restait proposé aux emplacements du podium.

**Cause réelle.** Le filtre portait sur `id_outcome_unibet`. **Un même pilote ne porte pas
le même identifiant selon le marché** — Antonelli vaut `o701093319` au marché « Vainqueur »
et `o701094802` au marché « Podium » du **même GP**. Le filtre marchait entre les deux
emplacements du podium (tirés du même marché), et **n'excluait donc jamais le vainqueur** :
il donnait l'illusion de fonctionner.

**Correctif.** Comparer sur le **libellé** normalisé (`clePilote`).

**Ne pas refaire.** **`id_outcome_unibet` n'identifie jamais une personne, seulement une
issue.** Un test démontre qu'un filtre par identifiant laisse les trois pilotes.

---

## 11. ⚠️ OUVERT — GP des Pays-Bas figé prématurément, et sa date fausse

**Symptôme.** `statut = 'cotes_figees'` sur `33b835cc-5c17-40f7-a41f-3e95fc14885a` alors
que les qualifications sont annoncées au **22 août 2026 à 12h00 UTC** — le job ne se
déclenche qu'à qualifs + 2 h.

**Cause réelle.** Un `POST /scraper/declencher` passé à la main **sans `?figer=false`**.
C'est le piège que le paramètre a précisément été créé pour éviter. `date_course` est
fausse en plus (§4).

**Correctif du symptôme visible : déjà fait.** Les trois surfaces exigent désormais
`cotesArretees` (statut **et** qualifications passées) : aucun bouton ne s'affiche avant
l'heure.

**La DONNÉE reste à corriger.** Le job du samedi ne la refigera pas — il ne traite que les
GP en `a_venir` :

```sql
update public.grands_prix set statut = 'a_venir'
 where id = '33b835cc-5c17-40f7-a41f-3e95fc14885a' and statut = 'cotes_figees';
```

Puis `POST /scraper/declencher?figer=false`, qui réécrit `date_course` et
`date_qualifications` **même pour un GP figé** — les deux se remettent d'aplomb en une fois.

**Ne pas refaire.** **Tout essai de scraper d'ici là doit porter `?figer=false`.**

---

## 12. ⚠️ OUVERT — Bandeau « Grands Prix restants » figé à 12

**Symptôme.** L'accueil affichera « 12 Grands Prix restants » même après le GP des Pays-Bas.

**Cause réelle.** `chargerGrandsPrixRestants` comptait les lignes de `public.grands_prix` —
c'est-à-dire **une seule course**, Unibet n'exposant que le GP suivant. La constante
`GP_RESTANTS = 12` a été posée pour avoir un nombre juste plutôt qu'un nombre faux.

**Correctif disponible.** `lib/calendrier2026.js` existe maintenant, et l'onglet Calendrier
en tire déjà un décompte **qui exclut les courses terminées**. Il suffit de compter
`GP_2026` filtré par `etatDuGpSaison`.

**Ne pas refaire.** **Sans cela, les deux écrans se contrediront dès la première course
courue.** `chargerGrandsPrixRestants` reste en place — elle redevient la bonne réponse le
jour où le calendrier complet est en base.

---

## 13. Le voile calculé démasque une déclaration incomplète

**Symptôme.** Aucun — **le calcul de contraste a fait son travail**, et c'est pour cela que
le cas est ici.

**Cause réelle potentielle.** `voileNecessaire` dérive l'opacité de la **bande la plus
claire** déclarée dans `couleurs`. Tant que les États-Unis et le Brésil étaient déclarés
`complexe` avec une seule dominante (`#B22234`, `#009C3B`), le calcul concluait qu'aucun
voile — ou presque — n'était nécessaire. **Le dessin, lui, peint treize bandes blanches** :
servi sous l'ancienne déclaration, il aurait porté du texte blanc sur du blanc pur.

**Correctif.** `couleurs` porte **toutes** les teintes que le SVG peint. Le voile s'est
ajusté seul : 0,00 → 0,45.

**Ne pas refaire.** **Toute forme peinte par le SVG doit avoir sa teinte dans `couleurs`.**
Un test compare les deux tables forme par forme.

*Corollaire mesuré* : la règle n'est pas « une bande blanche ⇒ un voile », c'est **« le
calcul tranche »**. Le vert du Brésil est assez clair pour demander 0,05 alors qu'il n'a
aucune bande blanche. Un test éprouvait initialement la mauvaise règle et échouait sur le
Brésil — **c'est l'assertion qui était fausse, pas le code.**

---

## 14. `window.Container` — un garde toujours faux

**Symptôme.** Un test d'effet visuel (Liquid Glass, retiré) retombait **en permanence** sur
son repli, librairie chargée ou non, **sans que rien ne le signale**.

**Cause réelle — deux, indépendantes.**

1. `Container` et `Button` sont des déclarations `class` au premier niveau d'un script
   classique : elles créent une liaison dans l'environnement **lexical** global, **jamais
   une propriété de l'objet global** — seuls `var` et les déclarations de fonction le font.
   Un garde `window.Container` est donc **faux en permanence**.
2. Vite hisse le script de module dans le `<head>` ; les scripts de la librairie vivent en
   fin de `<body>`. Tous différés, **React rend avant que `Container` existe**.

**Correctif (si l'effet est retenté).** `typeof Container !== "undefined"` — une référence
nue lèverait `ReferenceError`. Et attendre `window.load`, seul signal qui suit tous les
scripts différés **et qui est émis même quand l'un d'eux échoue**.

**Ne pas refaire.** Le code a été **retiré**, pas neutralisé. La réserve qui reste :
`Container.pageSnapshot` est **statique et capturé une seule fois** — le verre aurait
réfracté l'écran du premier montage.

---

## 15. `git revert` bloqué par un commit intercalé

**Symptôme.** Le `git revert` annoncé pour retirer le test Liquid Glass se serait arrêté en
conflit.

**Cause réelle.** Le commit n'était plus en tête : une version (drapeaux SVG) avait atterri
par-dessus, et les deux touchaient **les deux mêmes fichiers** (`CLAUDE.md`,
`package.json`). Résoudre à la main aurait risqué d'emporter la version intercalée.

**Correctif.** Restauration **ciblée** :
`git checkout <commit>^ -- <fichiers précis>`, suppression des fichiers ajoutés, puis
reprise à la main de la version et du CLAUDE.md. Vérifié : la version intercalée ne
touchait aucun des fichiers restaurés.

**Ne pas refaire.** **Avant un `revert`, vérifier le recouvrement** avec ce qui a atterri
depuis. Sans recouvrement, la restauration ciblée est plus sûre.

---

## 16. Le rendu HTML seul ne suffit pas — six fois

**Symptôme.** Six défauts sont passés à travers les contrôles textuels et n'ont été trouvés
qu'en **rendant l'écran avec la feuille CSS compilée**.

| # | Défaut |
|---|---|
| 1 | Numéro lu dans `saisie` au lieu du repli — première image sans numéro |
| 2 | Icône du logo calée à gauche (`items-center` sur un `Bloc`, §2) |
| 3 | Légendes de la vue piste se recouvrant dès que les voitures se resserrent |
| 4 | Interlignage `0.85` : les chiffres ronds débordaient (le « 1 » ne le montrait pas) |
| 5 | Transition sur `transform` au lieu de `translate` (§7) |
| 6 | `gap` inerte sur un `Bloc` (§2) |

**Ne pas refaire.** **Un rendu HTML vérifie la structure et le contenu, jamais la mise en
page.** Deux classes de défauts lui échappent par construction : les règles CSS qui ne
s'appliquent pas (§1, §2, §7) et tout ce qui tient à la géométrie (§3, §4).

**Le réflexe** : rendre l'écran avec la vraie feuille compilée, à 390 px de large, et
regarder. C'est ce qui a attrapé les six.

---

## 17. Ordre de peinture perdu à l'extraction — Mercedes et Alpine barrées de gris

**Symptôme.** Sur les deux seules livrées venues de `VOITUREs_am.svg`, un **aplat gris
sombre** (`#3C3C3B`) couvrait les deux tiers arrière de la voiture. Alpine y perdait tout
son rose, Mercedes son modelé gris clair et ses accents turquoise autour du cockpit.

**Cause réelle — ce n'était PAS une collision de classes CSS.** L'hypothèse naturelle est
que deux planches inlinées dans le même document se disputent leurs `.cls-N`. Elle est
fausse ici, et elle ne peut pas être vraie : **le frontend ne contient ni une seule classe
`cls-N`, ni une seule balise `<style>`** — la règle 3 d'extraction (`composants.md` §4) les
a toutes converties en attributs `fill` dès l'origine. Un `grep` de trois secondes le dit.

Le vrai défaut est l'**ordre de peinture**. Dans la planche, le polygone `#3C3C3B` — le
fond plat, qui doit rester **sous** la carrosserie — est le **premier élément du
document**, pour les deux voitures. Le découpage l'avait recopié au rang 13 (Mercedes) et
16 (Alpine) : mêmes formes, mêmes couleurs, même cadrage, **mais peint par-dessus**.

Un contrôle forme par forme le confirmait sans ambiguïté : 21 formes pour Mercedes,
24 pour Alpine, **exactement les mêmes des deux côtés, dans un ordre différent**. Et
les neuf livrées de `voitures_ecuries.svg` étaient, elles, dans le bon ordre — Cadillac
ouvre bien son fragment par son `#3C3C3B`.

**Correctif.** Les deux fragments **régénérés par script** depuis la planche, en ordre de
document. Aucune coordonnée réécrite ; seule la séquence change. Le rendu du fragment JSX
et celui de la planche cadrée sont désormais superposables.

**Ne pas refaire.**

- **Devant une zone de couleur fausse dans un SVG extrait, comparer l'ORDRE avant les
  couleurs.** Les couleurs étaient justes au code hexadécimal près, et les chemins exacts
  au caractère près : les deux contrôles habituels passaient.
- **Un SVG n'a pas de `z-index`.** L'ordre de document est le seul empilement qui existe ;
  le déplacer est une modification du dessin, pas une mise en forme.
- **Le contrôle qui attrape ce défaut est le rendu comparé** — fragment extrait contre
  planche cadrée, côte à côte. Un décompte des formes ou des `fill` ne le voit pas :
  ils sont identiques.

---

## 18. Les photos ne s'enregistraient PAS — une contrainte `check` incompilable

**Symptôme.** Deux symptômes en apparence sans rapport, livrés ensemble par la version
`0.50.0` :

- au profil, choisir une photo affichait **« Enregistrement de ta voiture : impossible
  pour le moment »** — un message qui parle de la voiture alors qu'on vient de toucher à
  une photo ;
- au championnat, la photo choisie à la création **n'apparaissait nulle part** : ni sur la
  carte d'accueil, ni dans la liste des championnats, ni dans l'en-tête de l'écran du
  championnat. Et **sans le moindre message**.

**Cause réelle — une seule, en base, pour les deux.** La migration 16 posait sur
`profils.avatar_url` et `championnats.photo_url` la même contrainte :

```sql
check (colonne is null or colonne ~ '^https://[^[:space:]]{10,505}$')
```

**Le moteur d'expressions régulières de PostgreSQL plafonne un compteur de répétition
`{m,n}` à 255** (`RE_DUP_MAX`). `{10,505}` dépasse ce plafond : l'expression n'est pas
compilable. Toute écriture d'une URL de photo retombait donc en

```
ERROR 2201B: invalid regular expression: invalid repetition count(s)
```

et **aucune photo n'a jamais pu être enregistrée depuis l'origine de la fonctionnalité.**
Vérifié sur la base de production le 22/08/2026, sur les deux colonnes.

**Ce qui n'était PAS en cause, et qu'on a écarté un par un.** Le diagnostic a été fait
contre la base réelle, pas par lecture — c'est ce qui l'a rendu court :

| Soupçon | Verdict |
|---|---|
| Migration 16 non appliquée | **Non.** Les deux colonnes existent (`select=photo_url` rend `[]` et non `42703`) |
| Compartiments Storage absents | **Non.** `avatars` et `championnats` rendent `NoSuchKey`, un compartiment inconnu rend `NoSuchBucket` |
| Politiques `storage.objects` trop strictes | **Non.** Les deux dépôts réussissent en `200` |
| `mes_championnats` en retard sur la migration | **Non.** `GET /championnats/moi` sert bien `photo_url` |
| La route `PATCH` ou son autorisation | **Non.** `url_de_photo_valide` passe, et le `403` créateur ne se déclenche pas |

Tout marchait **sauf** l'écriture de la colonne.

**Deux amplificateurs, et ce sont eux qui ont fait durer le défaut une version entière.**

1. **Le contexte du décorateur nommait la mauvaise chose.** `PATCH /profils/moi` sert la
   voiture, le numéro, la livrée **et** la photo, mais `journaliser_echecs` portait
   « Enregistrement de ta voiture ». Un échec de photo s'annonçait donc comme un échec de
   voiture, et envoyait chercher la cause du côté des couleurs. **Un contexte qui nomme la
   mauvaise chose est pire qu'un contexte vague.**
2. **L'échec de la photo d'un championnat était avalé en silence.** `attacherPhoto`
   rendait `undefined` dans tous les cas, par application de la règle « l'échec d'une
   opération secondaire n'emporte jamais la principale ». La règle est bonne ; sa mise en
   œuvre ne l'était pas. **Ne pas bloquer sur un échec n'autorise pas à le taire.**

**Correctif (version `0.51.0`).**

- **Migration 17** — la borne de longueur sort de l'expression régulière et devient un
  `char_length` : `~ '^https://[^[:space:]]+$' and char_length(...) between 18 and 513`.
  Sémantique identique à la lettre, plus aucun compteur, donc plus aucun plafond.
- La migration **s'éprouve elle-même** en fin de fichier, sur une URL jetable : une
  contrainte `check` n'étant évaluée qu'à l'écriture, c'est le seul moyen de savoir en la
  jouant qu'elle est compilable. C'est exactement ce qui manquait à la 16.
- Le contexte de `PATCH /profils/moi` devient **« Enregistrement de ton profil »**.
- `attacherPhoto` **rend son message d'échec**, que l'écran du championnat annonce à
  l'arrivée. La création n'est toujours pas bloquée.

**Ne pas refaire.**

- **Un compteur de répétition d'une expression régulière PostgreSQL ne dépasse jamais
  255.** Une borne de longueur se dit `char_length`, jamais dans le quantificateur d'une
  classe de caractères — mélanger les deux questions dans une seule expression est
  précisément ce qui a fait franchir le plafond sans que personne ne le voie.
- **Une contrainte `check` ajoutée sur une colonne vide n'est jamais éprouvée par sa propre
  migration.** Elle est acceptée à la création et n'échoue qu'à la première écriture, qui
  peut arriver des semaines plus tard. Toute migration qui pose un `check` non trivial doit
  l'exercer sur une valeur d'exemple dans un bloc `do $$`.
- **Le contexte d'un `journaliser_echecs` doit nommer la ROUTE, pas l'un de ses usages.**
  Une route de modification partielle en sert plusieurs par construction.
- **Devant un défaut de bout en bout, éprouver la chaîne segment par segment contre le
  service réel**, et non la relire. Colonne, compartiment, politique, fonction SQL, route :
  ici, quatre segments sur cinq étaient corrects, et aucune lecture du code ne pouvait
  désigner le cinquième — la contrainte est en base, elle n'apparaît que dans une migration
  déjà jouée.

---

## 19. L'initiale d'une pastille sur quatre était illisible

**Symptôme.** Sur certains comptes — et sur eux seulement — l'initiale de la pastille se
lisait mal sur son rond. Aucun écran n'était en cause : la même personne était illisible
partout, une autre lisible partout.

**Cause réelle.** `Pastille` écrivait `text-white` **en toutes lettres**, et sa table
distribue quatre teintes. L'une d'elles est l'amber `#E8A020` du design system, où le blanc
ne vaut que **2,22:1** quand `#1A1A1A` y monte à 7,86:1. Une graine sur quatre tombait
dessus, ce qui explique que le défaut ait paru aléatoire : il dépendait de l'identifiant du
compte, pas de l'écran.

C'est exactement le cas d'école que `docs/design-system.md` §5 décrit — « toute surface
amber prend l'encre foncée, sans exception » — et la pastille était le seul aplat de l'app
à ne pas passer par un helper.

**Correctif (version `0.52.0`).** `encreSurAplat(couleur ?? teinte.hex)`, calculé une fois
et posé en style en ligne. Mesuré après correction : 10,88 · **7,86** · 10,56 · 14,58:1.

**Ne pas refaire.**

- **Les deux helpers d'encre ne sont pas interchangeables, et l'amber les départage.**
  `encreSur` (`lib/palette.js`) compare une **luminance** à 0,45 ; l'amber vaut **0,424**,
  il passe donc juste sous le seuil et rend du blanc. `encreSurAplat` (`lib/couleurs.js`)
  mesure le **contraste** et bascule à 3:1. Devant la question « quelle encre sur cet
  aplat », c'est le second. Le premier reste juste là où il est employé — les deux textes
  peints sur une carrosserie, qui ne rencontrent jamais l'amber.
- **Un `text-white` écrit en dur sur un fond calculé est toujours un défaut en attente.**
  La couleur du fond vient d'une table ; l'encre doit venir du même endroit.
- **Un défaut qui « touche certains comptes » n'est pas intermittent** : c'est une fonction
  de hachage quelque part. Le chercher dans les écrans a coûté du temps ; il était dans la
  table.
