# CONTEXTE GREED F1 — OCTOBRE 2026

Ce fichier est à coller au début d'un nouveau chat Claude pour reprendre le travail là où on s'est arrêtés.

## QUI EST MATTHIEU

Étudiant ingénieur ING3 à l'ECE Paris, en échange universitaire à Baruch College New York (septembre–décembre 2026). Construit Greed F1 comme projet personnel combinant ambition produit et développement full-stack. Recherche un stage de 5 semaines à partir de janvier 2027.

## C'EST QUOI GREED F1

Application web (PWA) + app native iOS. Permet à des amis de créer des championnats privés, inviter des membres via un code à 6 caractères, faire des pronostics avant chaque Grand Prix F1 en utilisant les vraies cotes bookmaker Unibet, et gagner des points selon les résultats réels.

URL production web : https://greed-f1.com (alias de greed-f1.vercel.app)
Version web actuelle : 0.87.2
Version backend actuelle : 0.82.1
Version iOS actuelle : 0.47.4

## STACK TECHNIQUE

Frontend : React, Vite, Tailwind CSS v4 → Vercel (greed-f1.com + greed-f1.vercel.app)
Backend : FastAPI → Railway (mon-petit-podium-production.up.railway.app)
Base de données : Supabase/PostgreSQL (projet ID: ycsxcythvtcruiomrgvv)
Auth : Supabase Auth — email/password + Google OAuth actif
Emails : Resend via SMTP Supabase, domaine greed-f1.com vérifié
App iOS : Swift 5.0, SwiftUI, iOS 17.0+, Xcode 26.6, simulateur iPhone 17 Pro iOS 26.5
Bundle ID : com.bazzana.greedf1, SDK Supabase Swift 2.55.2
Repo GitHub : monorepo (frontend/ + backend/ + ios/ + docs/)

## MÉTHODE DE TRAVAIL

Deux chats : Claude (décisions + prompts) / Claude Code terminal (code + commits)
Chaque prompt commence par "Lis CLAUDE.md et ios/CLAUDE.md."
Migrations Supabase : toujours appliquées manuellement dans le SQL Editor
Docker non disponible → migrations testées en production directement
29 migrations appliquées (la 29 : `20261001120000_rattachement_par_date`)
Après chaque session, Claude Code met à jour docs/contexte-chat.md
Versions : web, backend et iOS sont indépendantes — chacune ne bouge que si son code change (`CLAUDE.md` §7). `CLAUDE.md` §8 suit la version web

## COMPTE REVIEWER APP STORE

Email : matthieu.andre.bazzana+reviewer@gmail.com
Pseudo : Reviewer
Membre de : Team Bazzana (données réelles saison 2026)
Mot de passe : à noter séparément

## CE QUI EST FAIT — VERSION WEB (0.87.2)

Authentification email/password + Google OAuth + onboarding pseudo
Championnats privés avec photo, code d'invitation, classement
Vue piste avec algorithme de positionnement géométrique + résolution collisions
Personnalisation voiture : couleurs, numéro, skin écurie (11 livrées)
Pronostics : marchés par catégorie, paris bonus, flip clock countdown
Tableau des cotes avec couleurs d'écurie
Résultats GP : mes résultats + classement 20 pilotes
Résultats par GP dans un championnat (accordion par membre, podium pilote par pilote)
Calendrier avec drapeaux pays + tracés circuits
Historique GP par membre
Profil membre avec stats et voiture
Mode admin : scraper, toggle prévisualisation, alertes libellés non reconnus
PWA installable
Emails fonctionnels via Resend (mot de passe oublié)
Pages greed-f1.com/privacy, /terms, /contact
Landing page publique sur greed-f1.com
Suppression de compte (conformité App Store 5.1.1(v))
Drapeau, tracé et croisement du calendrier par date de course (0.87.2) : `slugDuGp` (`lib/calendrier2026.js`), date à ±3 jours puis nom — corrige « GP Bahrein » couru à Sepang

## CE QUI EST FAIT — VERSION iOS (0.47.4)

Navigation TabView 4 onglets (Accueil, Championnats, Calendrier, Profil)
AccueilView : widget GP navigable avec drapeau + tracé circuit
ChampionnatsView + ChampionnatDetailView : classement, vue piste kerbs pleine hauteur, résultats par GP
CalendrierView : 12 GP avec drapeau + tracé, statuts, scroll auto
ProfilView : stats, livrée voiture, picker skin, suppression compte
ProfilMembreView + HistoriqueGPView + ResultatsGPView
CreerChampionnatView + RejoindreChampionnatView
CotesView + PronosView + RecapView : flux complet pronos
Google OAuth : bouton sur Landing + Connexion, OnboardingView pseudo
Recadrage photo avant upload
Toutes les données branchées sur l'API réelle
Mention "Provisoire" sur les résultats provisoires
Localisation français/anglais (0.46.0) : dictionnaires Swift `Localisation/Traductions{FR,EN}.swift`, `t("clé")` / `tp("clé", n)`, détection au 1er lancement (français si téléphone en français, sinon anglais), choix manuel persisté, toggle FR/EN sur Landing, Connexion et Profil > Paramètres, dates dans la langue choisie, fr + en déclarés (Info.plist + knownRegions)
Sélecteur de langue retravaillé (0.46.1) : drapeaux emoji 🇫🇷 / 🇬🇧, segment actif en pastille pleine `primaire` + encre blanche, segment inactif sur fond neutre avec drapeau atténué (40 %, désaturé) et texte à 80 % (pas plus bas : 4,5:1 mesuré), pastille qui glisse en 200 ms (fondu sous mouvement réduit). Vérifié au simulateur sur Landing, Connexion et Profil > Paramètres
Drapeau, tracé et croisement du calendrier par date de course (0.46.2) : `SlugCircuit.de(_:dateCourse:)` (`Models/GrandPrix.swift`), date à ±3 jours puis nom — utilisé par `GrandPrixEnBase`, `ProchainGP` et `GrandPrixJoue` ; deux lignes au même week-end, le calendrier garde celle qui a des cotes. Corrige le widget du prochain GP vide pour « GP Bahrein » couru à Sepang. Vérifié au simulateur en FR et EN (Accueil, Calendrier, Profil)
Noms de GP, pays et circuits traduits (0.46.3) : clés `gp.<slug>.{pays,nom,court,circuit}` dans les deux dictionnaires, lues par `GrandPrixSaison` (plus rien d'écrit en dur dans la liste statique). Anglais au format « Malaysian GP », « Singapore GP ». Le nom affiché vient toujours du calendrier statique — `GrandPrixSaison.nomAffiche(slug:repli:)`, exposé en `nomAffiche` sur `GrandPrixEnBase`, `ProchainGP`, `GrandPrixPronos`, `GrandPrixDuChampionnat` ; le nom de la base ne sert qu'au rattachement. L'accueil dit donc « GP Malaisie » / « Malaysian GP » le 4 octobre, comme le calendrier. Vérifié au simulateur en FR et EN (widget Accueil, Calendrier, carte et fiche du 4 octobre)
Sélecteur de langue plus visible (0.46.4) : les deux options en couleur pleine quelle que soit la langue active (plus de désaturation ni d'opacité réduite sur le drapeau, libellé inactif en `secondaire` plein — `encreSegmentInactif`, 8,18:1 sur le beige, 9,22:1 sur le blanc) ; l'état ne se lit qu'à la pastille `#800111`. Segments 80 × 40 (au lieu de 62 × 32), drapeau 20 pt, code en `Font.segment` (Helvetica Neue Medium 14, nouveau jeton) ; glissement de la pastille conservé. Vérifié au simulateur sur Landing, Connexion (bascule en direct) et le bloc Paramètres du Profil (reproduit à l'identique, faute de session au simulateur), en FR et EN
En-tête de ChampionnatDetailView retravaillé (0.46.5) : trois colonnes centrées sur l'axe vertical — titre + membres/saison à gauche à leur largeur naturelle, photo carrée 56 pt (hauteur du bloc titre, rayon `champ`) au milieu, ⋯ à droite. Deux `Spacer` égaux placent la photo à équidistance du texte et du glyphe ⋯ (retrait de 12 pt du cadre tactile, pour mesurer au glyphe). Sans photo — et pendant son chargement — `PhotoChampionnat` peint l'initiale blanche sur `primaire` `#800111` (10,88:1) : une seule mise en page. Vérifié au simulateur avec photo, sans photo et avec un nom sur deux lignes (écarts égaux à 1–2 pt près)
Carrousel « Mes / Ses Grands Prix » (0.47.0, mergé sur `main` depuis `feat/gp-carousel-a`) : `HistoriqueGPView` (Profil et ProfilMembre) passe d'une liste à un carrousel swipeable — une carte par GP joué, la carte active centrée, ses voisines visibles de part et d'autre. Fond = drapeau de la carte active fortement flouté (`FondDrapeauFlou`), en fondu d'une carte à l'autre ; la carte porte le même drapeau net. Voile mesuré (`ApparenceDrapeau.voileEncreSecondaire`, 4,5:1 pour l'encre secondaire à 70 %) ; drapeaux clairs (`estClair`) voilés seulement sous le texte. Tap sur une carte = déploiement plein écran en détail des pronostics (`DetailGrandPrixJoue`, `matchedGeometryEffect`), ressorts critiques `Mouvement.deploiement` / `repli` (0,34 / 0,28, sans dépassement), contenu après 160 ms ; mouvement réduit = fondu. Statuts Gagné / Perdu / En attente traduits FR/EN
Pile de championnats sur l'accueil (0.47.0, mergé sur `main` depuis `feat/championship-stack`) : `Views/Accueil/PileChampionnats.swift` remplace la liste. Carte du dessus = `CarteChampionnat` inchangée (tap → détail via `navigationDestination(item:)`) ; toutes les autres dépassent au-dessus en bandes de 44 pt (nom + « 1/3 », teinte voilée de `Materiau.voilePile`), resserrées de 4 pt par cran (3 crans max). **Seule la carte du dessus se glisse** : swipe haut → elle part au fond, swipe bas → la carte du fond revient ; les bandes ne portent aucun geste, un glissement parti d'elles fait défiler l'accueil. **Tap sur une bande = aperçu** : la carte se déplie en pleine `CarteChampionnat` à sa place dans le paquet (pleine largeur), sans changer l'ordre ni l'ordre d'empilement : l'aperçu garde le zIndex de sa profondeur, et les cartes de devant (carte du dessus comprise) **descendent** de sa hauteur pleine (mesurée par chaque carte, `onGeometryChange`) moins sa bande moins 8 pt de chevauchement — elles restent par-dessus, rien n'est couvert, l'accueil s'écarte avec elles (`padding(.bottom)`), même ressort `Mouvement.pile` à l'ouverture et à la fermeture ; un seul aperçu (en ouvrir un autre replie le premier), tap hors de la pile ou sur la carte du dessus = fermer (le tap extérieur est un `TapGesture` de l'accueil, `including: .subviews` hors aperçu ; `apercuPile` vit dans `AccueilView`), 2ᵉ tap sur l'aperçu = ouvrir. Tap sur la carte du dessus sans aperçu = ouvrir. **Ordre mémorisé** dans `UserDefaults`, clé `accueil.pile.ordre.<user_id>` (`OrdrePile`, même fichier) : par défaut effectif décroissant puis nom ; mémorisé à chaque swipe et à l'ouverture depuis un aperçu (la carte passe au premier plan, écrit tout de suite, appliqué au retour) ; `rapprocher` retire les championnats quittés et ajoute les nouveaux **au fond** — l'ordre rapproché est réécrit dès qu'il change, sans quoi un nouveau championnat serait rangé par l'ordre par défaut à la lecture suivante (conséquence : l'ordre par défaut n'est calculé qu'au premier affichage, il ne suit pas l'évolution des effectifs). Cartes qui passent au fond : elles restent au premier plan pendant tout le trajet (zIndex dynamique, `plan(profondeur:id:)` : carte tirée > cartes en vol > carte du dessus > bandes) et ne passent derrière qu'à l'arrêt complet du ressort (`withAnimation(…, completionCriteria: .removed)`, compteur de trajets pour les swipes enchaînés) ; en vol leur ombre s'éteint et leur hauteur se réduit à la bande, pour que le passage derrière ne se voie pas. Fluidité : chaque carte est un `CartePile` qui porte son propre `@GestureState` (déplacement + axe) — un glissement ne redessine qu'elle ; `CarteChampionnat(ombre: false)` dans la pile (son ombre rognée était calculée pour rien) ; pendant le geste, les bandes perdent la couche ambiante de `ombreAplat(allegee:)`, rendue au lâcher. Ressorts `Mouvement.pile` (tap, critique) et `pileLancee` (swipe, response 0,35 / amortissement 0,8). Mouvement réduit : le paquet se remplace en fondu. Le swipe sur la carte du dessus est un `highPriorityGesture` (espace global, axe fixé au premier déplacement : seul un geste vertical déplace la carte ; un geste annulé la ramène via `@GestureState`) — il prend le pas sur le ScrollView de l'accueil, qui le captait auparavant ; il reste actif pendant un aperçu : le swipe (haut ou bas) s'exécute et replie l'aperçu dans la même transaction (`apercu = nil` dans le `withAnimation` de `envoyerAuFond` / `ramenerDuFond`), sans animation séparée. Barre claire entre deux cartes pendant le trajet (cause : une carte en vol s'arrête à sa bande, sans le rayon qui chevauche sa voisine — les coins arrondis de celle-ci et le dépassement du ressort `pileLancee` laissaient voir le fond) : chaque carte en vol pose sous tout le paquet une `JupePile` de sa teinte voilée (`Rayon.carte` sous le haut de sa bande → `Rayon.carte` sous son bas), allumée seulement en vol — hors vol, une carte du dessus tirée vers le haut en découvrirait les coins carrés. Mesuré en vidéo 60 i/s (`simctl io recordVideo`) contre l'ancienne version : liseré et encoches disparus. Vérifié au simulateur sur un banc d'essai fictif (pas de session) : aperçu, relais entre deux aperçus, tap extérieur, 2ᵉ tap → détail puis retour avec la carte au premier plan, swipe sur une bande = défilement, swipe haut sur le dessus, ordre relu après relance, nouveau championnat au fond ; auparavant : 1 et 20 championnats, mouvement réduit ; ordre Z pendant et après le trajet, swipe court qui revient, deux swipes enchaînés (gestes injectés par CGEvent, images capturées en rafale)
Écran « Mes résultats » du widget de l'accueil refait (0.47.1) : « Voir mes résultats → » (navigation inchangée, `EtapePronos.resultats`) ouvre `Views/Resultats/MesResultatsGPView.swift` — le détail du carrousel du profil sans le héros : `FondDrapeauFlou` + `ContenuDetailGrandPrix` (en-tête nom/date/points/X sur Y réussis/« Provisoire », une carte par pronostic, podium réel), extrait de `DetailGrandPrixJoue` et partagé par les deux écrans. Données : `GrandsPrixJoues(gpId:)`, restreint à ce GP, résultats disponibles ou non. Rien joué ou aucun championnat → classement officiel (`ResultatsGPView`), comme avant ; la branche `dateResultats` d'`EntreePronosView` reste en place, non montée. Cartes de pronostic redessinées (`CarteVerdict`, ex-`CartePronostic`, aussi dans le carrousel) : fond teinté (gagné `vertSauge` 7 %, perdu `primaire` 4 %, attente blanc) + liseré, damier `Materiau.damierPronostic` 6 % (repli sans damier : `Materiau.damierSurPronostics = false`), icône ✓ / ✗ blanche sur aplat plein, verdict en **pastille pleine** (blanc sur vert 4,86:1, sur bordeaux 10,88:1) — le vert sauge en texte tombait à 4,12:1 sur la carte teintée et damée, mesuré —, points 26 pt (vert si gagné, `0` gris si perdu, en jeu gris si en attente), unité « pts » grise. Vérifié au simulateur sur un banc fictif (GP Malaisie, trois statuts, provisoire)
Widget « Total saison » de `HistoriqueGPView` (0.47.2, mergé sur `main` depuis `feat/total-saison-damier`, version rouge validée) : bandeau bordeaux en deux moitiés — total, réussis / tentés et rang (pastille) à gauche, voiture **enregistrée** du membre à droite, tournée museau vers le texte (`VoitureMembre`, reçue de `ProfilView` / `ProfilMembreView` ; silhouette neutre tant que le profil n'est pas lu). Damier blanc (`Damier(encre:)`, nouvelle option de couleur). Une seule marge, posée sur le conteneur. Contrastes mesurés : blanc 9,83:1, `encreSecondaire` 5,41:1 au pire pixel du damier. La variante blanche (`feat/total-saison-blanc`) est abandonnée, branche supprimée
Écran championnat retouché (0.47.3, mergé sur `main` depuis `feat/championnat-detail-style`, branche supprimée) : photo du championnat à 100 pt (rayon `widget`), réduite par pas de 2 pt jusqu'à 72 pt si le nom ne tient pas en deux lignes (`DispositionEntete`, `Layout` qui mesure le titre par TextKit) ; texte, photo et ⋯ centrés verticalement, photo à équidistance du texte et du glyphe ⋯ ; l'en-tête grandit avec elle. **Sans photo, rien** : ni initiale ni aplat, l'en-tête redevient texte à gauche + ⋯ à droite, à sa hauteur naturelle. Le `Picker` segmenté natif (blanc sur gris clair sous iOS 26) est remplacé par `Views/Composants/SelecteurSegmente.swift` : actif en pastille `#800111` pleine + blanc (10,88:1), inactif en `secondaire` sur fond neutre (7,56:1), **une seule** pastille sous la rangée, qui épouse le segment choisi (`matchedGeometryEffect(isSource: false)`) sur le ressort critique `Mouvement.glissement` (response 0,3, amortissement 1 — nouveau jeton), fondu sous mouvement réduit. **Saccade de la bascule Classement / Piste** (cause : le `switch` démontait un contenu et construisait l'autre dans la transaction de la pastille — `Canvas` de la piste, photos des cockpits, entrée des voitures) : les deux contenus et le sol de la piste restent montés, superposés, seule l'opacité bascule ; la piste est comparée avant réévaluation (`PisteIntegree`, `.equatable()`) ; l'entrée des voitures attend le premier affichage (`VuePisteView.lancerEntree`) et ne se rejoue plus. Le contenu masqué l'est à **0,001** et non 0 : à 0, SwiftUI ne le dessine pas et la première bascule perdait 1 à 3 images (mesuré). Mesuré en vidéo (`simctl io recordVideo`, position de la pastille image par image) : une position par image à 60 i/s, à la première bascule comme aux suivantes, 3 lancements sur 3. Gris de l'écran passés en `secondaire` sur le beige (9,32:1 au lieu de 4,71:1) : sous-titre membres/saison, ⋯ (agrandi à 20 pt), mention « Provisoire ». Damier `Materiau.damierFiligrane` (5 %) à deux endroits : fond du sélecteur (encre `secondaire`), carte « Résultats par Grand Prix » (gris d'origine, 4,98:1) — retiré des lignes du podium (`fondPodium` non monté). Vérifié au simulateur sur un banc fictif : avec photo, sans photo, nom long sur deux lignes, nom tronqué (photo à 72 pt), bascules répétées, mouvement réduit
Pile de marchés sur « Fais tes paris » (0.47.4, mergé sur `main` depuis `feat/pronos-stack`, branche supprimée) : `Views/Pronos/PileMarches.swift` remplace l'accordéon de `CotesView` (gardé en place, non monté). Chaque marché est une carte sur son aplat (`MarcheCote.aplat` : rouge vainqueur, bleu podium ; bonus : une teinte par marché dans l'ordre, `Color.teintesMarcheBonus` — terracotta, sauge, ocre, mauve, orange doux, menthe, blanc ≥ 4,86:1 mesuré) + damier `Materiau.damier` + `LueurHaute`. Fermée : bande de 52 pt (nom, pastille « ✓ n », chevron) ; la suivante recouvre son bas de `Rayon.carte`, comme les bandes de l'accueil. **Toutes fermées à l'arrivée** ; tap sur l'en-tête = ouvrir / fermer sur place, les suivantes descendent / remontent ; **plusieurs ouvertes à la fois** ; une étoile ne referme rien ; **aucun swipe**, ordre `OrdreMarches` inchangé, tout glissement fait défiler l'écran. Mécanique reprise de `PileChampionnats` (`ZStack`, zIndex par rang, carte rognée à sa bande + rayon, décalage = somme des pas, ressort `Mouvement.pile` ; mouvement réduit = sans trajet), deux écarts : décalage en `padding` et non `offset` (la `LazyVGrid` d'une carte ouverte doit connaître sa vraie place pour rester paresseuse) ; hauteur dépliée **calculée** (`CarteCote.hauteur`, désormais `static`, 56 pt — carte compacte : nom 14 pt, points 16 pt dessous, étoile à droite) et non mesurée — mesurée, elle arrivait une image trop tard et les cartes suivantes sautaient hors du ressort. Seules les cartes ouvertes construisent leur grille ; `CarteCote(ombre: false)` dans la pile. Le damier est cadré sur la bande (104 pt, fondu sous l'en-tête) : posé sur toute la carte ouverte, `scaledToFill` le grossissait ~3× (vu au simulateur). VoiceOver : « Ouvrir / Fermer <marché> », valeur = nombre de favoris (clés `cotes.a11y.ouvrir` / `fermer`). Vérifié au simulateur sur un banc fictif non versionné (7 marchés dont un de 60 issues, favoris hors ligne) : tout fermé à l'arrivée, trois cartes ouvertes ensemble puis refermées, étoiles + compteurs de bande + rangée « Mes paris bonus », défilement parti d'une carte, 60 issues en lancer (vidéo : médiane 16,7 ms entre images), `PronosView` liste les trois favoris. **Vainqueur et podium exclus de la seule liste des paris bonus de `PronosView`** (`MarcheCote.exclueDesBonus` : slug `vainqueur`, préfixes `vainqueur_course` et `podium` — liste, total, POST) ; dans `CotesView` ils s'épinglent comme les autres marchés (étoile, pastille de bande, rangée « Mes favoris »). Étoile favori en jaune vif `Color.jauneEtoile` `#FFD700` cernée d'un trait `texte` (`EtoileJaune` : le jaune seul 1,40:1 sur blanc, contour 17,4:1, jaune/contour 12,4:1) **uniquement** pour l'étoile indicative `EtoileFavori` de la feuille de choix (vainqueur / podium) de `PronosView` ; l'étoile d'épinglage `EtoileParisBonus` garde son gris d'origine (`secondaire` à 60 %, 22 pt) dans `CotesView` seulement ; dans « Mes paris bonus » de `PronosView` elle passe en `EtoileJaune` 22 pt (`EtoileParisBonus(jaune: true)`). Damier `Materiau.damierFiligrane` (5 %) dans `PronosView` à deux endroits : le bandeau « Mes paris bonus », devenu carte blanche (sur le beige le damier ferait tomber `grisSecondaire` à 4,42:1, sur le blanc 4,98:1), et les lignes de bonus retenues (ambre, `encreSecondaireAmbre` 4,66:1 au pire pixel, calculé). Puis à trois autres : les blocs vainqueur (`#800111`) et podium (`bleuArdoise`), en gris d'origine — encre douce du champ vide 4,73:1 / 4,80:1 au pire pixel, un damier blanc la faisait tomber à 4,41 / 4,39 —, et le compte à rebours (`BlocEcheance`, donc aussi dans `RecapView`), dont le label passe de `grisSecondaire` (4,41:1 sur le beige damé) à `secondaire`. Compilé ; rendu de l'étoile jaune et du damier non vérifié au simulateur. Non vérifiés : VoiceOver et mouvement réduit au simulateur (lus dans le code), iPhone réel

## ÉVALUATION DES PRONOSTICS

Registre d'évaluateurs par slug exact (18 marchés couverts)
Statut : en_attente / non_evaluable / gagne / perdu
Pipeline provisoire (à l'arrivée) → définitif (J+1)
192 tests de non-régression backend
Identifiants canoniques des issues au figeage
Alertes admin (libellés non reconnus, échecs OpenF1)

## DOMAINE ET EMAILS

greed-f1.com acheté sur Porkbun
Resend configuré (domaine vérifié, DKIM/SPF/DMARC)
Supabase branché sur Resend via SMTP
Google OAuth branding validé et publié sur Google Cloud

## CE QUI RESTE À FAIRE

Bloquants App Store :

Sign in with Apple (bloqué — en attente compte Apple Developer 99€/an)
Screenshots finaux (iPhone + iPad)
Test iPad (ouvrir chaque écran sur simulateur iPad)

Fonctionnalités prévues :

Notifications push
f1-ml : modèle de prédiction ML à intégrer

Bugs connus :

Google OAuth iOS non encore testé sur iPhone réel

## SCRAPER ET OPÉRATIONS

Rattachement d'un GP Unibet (backend 0.82.1, `docs/decisions.md` §24) : identifiant Unibet, puis date de course à ±3 jours, puis nom en repli. Aucun candidat → GP nouveau, ligne créée. Deux candidats ou plus (ou une ligne réelle du même week-end sous un autre identifiant) → rien créé, alerte admin `grand_prix_ambigu`.
Le 4 octobre 2026 est le GP de Bahreïn délocalisé à Sepang : ligne unique `16a9c686-392a-4ef0-a624-f112825106d9`, nom Unibet « GP Bahrein », drapeau et tracé de Sepang (slug `malaisie`). Doublon avec la ligne manuelle « GP Malaisie » résorbé le 1er octobre par `adopter_grand_prix`.

Scraper (avec figeage) :
curl -X POST "https://mon-petit-podium-production.up.railway.app/scraper/declencher" -H "X-Admin-Secret: monpetitpodium2026"

Recalcul définitif d'un GP :
curl -X POST "https://mon-petit-podium-production.up.railway.app/jobs/resultats/{gp_id}/recalcul?relire=true" -H "X-Admin-Secret: monpetitpodium2026"

## VOCABULAIRE CANONIQUE

"championnat" jamais "ligue" — "calendrier" jamais "historique" — "paris bonus" jamais "favoris" — "pronostic" jamais "pari" dans le code — points toujours en entiers

====================================
FIN DU CONTEXTE
