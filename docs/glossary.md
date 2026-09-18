# Glossaire

Le vocabulaire canonique du projet. **Ces termes ne se renomment pas** — ni dans
l'interface, ni dans le code, ni dans les commentaires.

---

## Les deux interdits absolus

| Utiliser | Ne jamais utiliser |
|---|---|
| **championnat** | ~~ligue~~ |
| **calendrier** | ~~historique~~ |

Ces deux règles sont vérifiées par des tests sur le rendu des écrans. Les maquettes de
`/maquettes/` emploient encore « ligue » et « historique » : **elles ont tort**, c'est un
écart assumé et documenté.

---

## Termes du domaine

**Championnat** — un groupe de joueurs qui se classent entre eux. Créé par un membre,
rejoint par un code d'invitation à 6 caractères. Aucune limite de membres. Un joueur
peut appartenir à plusieurs championnats. *Jamais « ligue », « groupe » ou « poule ».*

**Calendrier** — la liste des Grands Prix. Recouvre **deux écrans distincts** qu'il ne
faut pas confondre :
- le *calendrier de la saison* (onglet **Calendrier**, `/calendrier`) — les douze GP,
  identiques pour tout le monde ;
- le *calendrier d'un championnat* (`/championnats/:id/calendrier`, maquette 15) — les
  mêmes GP, avec le score du membre et le mini-classement de ses amis.

*Jamais « historique », même pour les courses passées.*

**GP** / **Grand Prix** — une course. Les deux formes sont acceptées ; « GP » à l'écrit
court, « Grand Prix » en toutes lettres dans une phrase.

**Pronostic** — une mise d'un joueur sur une issue, pour un GP. Trois types :
`vainqueur`, `podium`, `bonus`. Deux obligatoires (vainqueur, podium) et jusqu'à trois
bonus. *Le pluriel familier « pronos » est admis dans l'interface* (« Voir mes pronos »,
« Pronos ouverts ») — c'est le registre du produit.

**Pari bonus** — une cote qu'un joueur a **ajoutée** pour un GP, en attendant d'en faire
un de ses trois bonus. Les bonus se choisissent **parmi les paris bonus** du joueur, qui
sont **strictement privés** : ce sont des brouillons. *Ne pas dire « sélection » ni
« panier ».*

> ### Le mot a changé à l'écran, et nulle part ailleurs (version `0.66.0`)
>
> L'interface disait « favori », et l'étoile qui l'ajoutait disait « marque-page » : ni
> l'un ni l'autre ne disait à quoi la chose servait, alors que **la seule raison
> d'ajouter une cote est d'en faire un bonus**. Le nouveau nom porte cette raison, et il
> est le même sur les deux écrans du parcours — le tableau des cotes, l'écran de saisie —
> là où « MES FAVORIS » et « BONUS — MES FAVORIS » nommaient la même chose de deux façons.
>
> **Le code et la base gardent « favori » partout** : table `favoris`, route
> `POST /grands-prix/{id}/favoris`, `basculerFavori`, `EtoileFavori`, `chargerFavoris`,
> clé de cache. C'est un changement de **vocabulaire d'interface** ; renommer l'écriture
> aurait demandé une migration pour un mot, et la fait courir sans bénéfice.
>
> Le couple d'icônes suit le mot : **`+` quand le pari n'est pas ajouté, coche quand il
> l'est**. Un signe qui nomme l'action et un autre qui nomme son résultat, là où deux
> étoiles ne différaient que par leur remplissage.

**Cote** — l'issue d'un marché chez Unibet, et ce qu'elle rapporte. **Le mot désigne
l'objet, jamais le nombre affiché** : on ne montre jamais « ×2,80 », on montre
« 28 pts ». Voir `metier.md` §1.

**Marché** — un type de pari sur un GP : « Vainqueur », « Podium », « Ecurie Vainqueur »,
« Top 6 »… Le **libellé** affiché est toujours celui du bookmaker
(`cotes.libelle_marche`) ; le **slug** (`cotes.marche`) sert de clé de regroupement, et
**de clé de tri** — l'ordre d'affichage est celui d'`ORDRE_MARCHES`
(`lib/pronostics.js`, voir `composants.md` §5), jamais celui d'Unibet.

**Points** — le nombre entier qu'un pronostic rapporte ou peut rapporter. Deux notions
distinctes, à ne jamais confondre :
- `points` — ce que le pronostic **peut** rapporter (la cote × 10) ;
- `points_gagnes` — ce qu'il **a** rapporté (`NULL` / `0` / `> 0`).

Les confondre ferait afficher un score avant la course.

**Livrée** — un jeu de deux couleurs. Le mot a **deux emplois** :
1. la *livrée initiale* attribuée automatiquement à l'inscription (une des dix de
   `livree_par_indice`), que le membre écrase dès qu'il personnalise ;
2. la *livrée d'écurie* (`livree_mode = 'ecurie'`), un dessin de voiture complet aux
   couleurs d'une des onze écuries.

**Skin** — une **pastille carrée** montrant le motif d'une livrée, extraite de
`assets/matti.svg`. **Ce n'est pas une voiture** : ni roues, ni ailerons, ni museau.
Sert **uniquement de vignette dans le sélecteur du profil**. La voiture réellement
dessinée à l'écran reste celle de `VoituresEcuries.jsx`.

**Créateur** — le membre qui a créé le championnat (`championnats.cree_par`). Seul à
pouvoir le modifier ou le supprimer. **Peut être `NULL`** : le championnat survit à la
suppression de son compte.

**Membre** — quiconque appartient à un championnat (`membres_championnat`), créateur
compris. *Ne pas dire « joueur » quand on parle de l'appartenance* — « joueur » désigne
la personne qui pronostique, « membre » son rattachement à un championnat.

**Figé** (*cotes figées*) — statut `cotes_figees` : les cotes sont arrêtées et le scraper
refuse d'y toucher. **Attention** : le statut seul ne suffit pas à ouvrir les pronostics,
il faut aussi que les qualifications soient passées (`metier.md` §3).

**Fermé** (*pronostics fermés*) — départ passé. Plus aucune modification.
*Ne pas confondre avec « figé »* : figé concerne les **cotes**, fermé concerne les
**pronostics**.

**Terminé** — statut `termine` : la course est courue et le job de résultats a fait son
passage. **Ne garantit pas** que tous les pronostics ont été notés.

**Piste** (*vue piste*) — l'écran signature : les voitures des membres réparties
verticalement selon leurs points, sur une route qui occupe tout l'écran. Depuis la version
`0.49.0` la route est **beige** et vient de `assets/vue_piste.svg`, un **bandeau** aux
couleurs du championnat la coiffe, et la hauteur d'une voiture dit ses points **sans
correction** — c'est la taille qui cède quand la place manque, jamais la position.

**Bloc** — un widget de l'interface : surface autonome très arrondie, sur fond beige.
C'est aussi le nom du composant React (`Bloc`) qui porte l'animation d'entrée.

---

## Termes techniques à ne pas renommer

**`id_unibet`** — l'identifiant du nœud Unibet d'un GP (préfixe `p`). **La clé de
rapprochement du scraper.** Jamais le nom.

**`id_outcome_unibet`** — l'identifiant d'une issue chez Unibet (préfixe `o`).
**Il change d'un marché à l'autre pour le même pilote** : ne jamais s'en servir pour
identifier une personne.

**`slug`** — clé normalisée : minuscules, accents ramenés à la lettre de base, reste en
tirets. Trois familles indépendantes de slugs coexistent, et elles n'ont pas les mêmes
valeurs — slug de **circuit** (`pays-bas`, `abu-dhabi`), slug de **marché**
(`ecurie-vainqueur`), slug de **livrée** (`red-bull`, `racing-bulls`).

**`est_membre`** — la fonction `security definer` qui casse la récursion RLS. Son nom est
cité dans plusieurs politiques : la renommer demande de toutes les revoir.
