import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import Voiture from "../composants/Voiture.jsx";
import Pastille from "../composants/Pastille.jsx";
import GrilleStats from "../composants/GrilleStats.jsx";
import SelecteurCouleur from "../composants/SelecteurCouleur.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import { Barre, Carte, Pave } from "../composants/Squelette.jsx";
import SelecteurSkin from "../composants/SelecteurSkin.jsx";
import Repli from "../composants/Repli.jsx";
import SectionAdmin from "../composants/SectionAdmin.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import {
  chargerNumerosPris,
  chargerProfilComplet,
  cleProfil,
  enregistrerVoiture,
  porteurDuNumero,
} from "../lib/profils.js";
import { livreeDuMembre } from "../lib/palette.js";
import { oublierCachePrefixe, useDonnees } from "../lib/useDonnees.js";
import { APP_VERSION } from "../config.js";

/**
 * Maquette 14 — mon profil : ma voiture, mes statistiques, ma personnalisation.
 *
 * **Une seule section « Ma livrée », et quatre rangées ordonnées par portée.**
 * Le mode n'est plus choisi dans un contrôle segmenté : il se déduit du skin
 * retenu, `null` valant « ma livrée » — les deux ne peuvent donc plus se
 * contredire. Le choix vit sur le profil (`livree_mode`, `livree_ecurie`), donc
 * il est le même dans tous les championnats du membre, ce que demande la
 * section 5.
 *
 * L'ordre des rangées est **Numéro, Skin, Coque, Ailerons**, et il se lit :
 *
 * | Rangée | Portée |
 * |---|---|
 * | Numéro | s'écrit sur le museau **quelle que soit** la livrée |
 * | Skin | commande les deux suivantes |
 * | Coque · Ailerons | ne peignent que sous « Ma livrée » |
 *
 * **Coque et Ailerons quittent le DOM quand un skin d'écurie est actif** — ni
 * grisés, ni transparents, ni `hidden` : sous une livrée fixe ils ne peignent
 * plus rien, et un réglage sans effet qui reste tabulable est pire qu'un
 * réglage absent. Ils partent par un repli (`composants/Repli.jsx`), sans quoi
 * la carte perdrait quatre-vingt-dix pixels d'un coup et le bouton
 * d'enregistrement sauterait sous le doigt.
 *
 * **La version `0.40.0` les gardait visibles**, au motif qu'un membre ayant
 * essayé un skin devait voir vers quoi il revenait. Ce service est désormais
 * rendu par la case « Ma livrée » du sélecteur, qui montre les deux couleurs en
 * diagonale : la question n'est pas restée sans réponse, elle a changé de
 * propriétaire (`docs/decisions.md` §17).
 *
 * **« Ma livrée » est ce que voit un nouveau joueur**, sans avoir rien à
 * choisir : `livree_mode` vaut `perso` par défaut de colonne (migration 12), et
 * `livreeDuMembre` rend `perso` pour toute ligne qui ne dit pas autre chose.
 * Coque et Ailerons sont donc visibles au premier montage.
 *
 * **Écarts assumés par rapport à la maquette**, tous documentés dans le
 * CLAUDE.md :
 *
 * 1. La rangée « Mes Grands Prix » est retirée. La maquette dessinait une
 *    grille de cartes illustrées par `assets/gp-cards.svg` ; l'écran qu'elle
 *    ouvrait (maquette 13) reste en place et atteignable par son URL, seule
 *    l'entrée depuis le profil disparaît.
 * 2. Les vignettes du sélecteur de skin sont les **pastilles carrées** de
 *    `assets/matti.svg`, pas des voitures : elles n'ont ni roues ni ailerons,
 *    donc aucun endroit où écrire un numéro. La voiture réellement dessinée —
 *    ici l'aperçu, ailleurs la vue piste — reste celle de
 *    `composants/VoituresEcuries.jsx`, seule à porter le pseudo sur son aileron
 *    arrière, qui est le seul identifiant d'un membre sur la piste depuis la
 *    version `0.39.0`.
 */

const NUMERO_MAXIMUM = 99;

/** Ne garde que des chiffres, et jamais plus de deux (numéro de 1 à 99). */
function nettoyerNumero(saisi) {
  return String(saisi ?? "").replace(/\D/g, "").slice(0, 2);
}

/**
 * L'état de saisie tel qu'il découle d'un profil servi.
 *
 * Écrit une seule fois : la remise à zéro après enregistrement et le suivi du
 * profil frais doivent produire exactement le même état, sinon les deux
 * chemins divergent au premier champ ajouté.
 */
function saisieDepuis(profil) {
  const livree = livreeDuMembre(profil);
  return {
    couleur1: livree.couleur1,
    couleur2: livree.couleur2,
    mode: livree.mode,
    // Le dernier slug choisi est conservé même en mode perso : c'est ce que la
    // colonne garde en base, et c'est ce que le membre retrouve s'il rebascule.
    ecurie: profil?.livree_ecurie ?? null,
    numero: profil?.numero == null ? "" : String(profil.numero),
  };
}

function SqueletteProfil() {
  return (
    <div className="flex flex-col gap-3">
      {/* L'en-tête garde son aplat rouge et le bloc de personnalisation sa
          surface blanche : ce sont les formes de l'écran, seul leur contenu est
          encore inconnu. */}
      <div className="rounded-bloc bg-primaire shadow-bloc flex items-center justify-between gap-4 p-5">
        <div className="flex flex-1 items-center gap-3.5">
          <div className="size-[42px] shrink-0 rounded-full bg-white/25" />
          <div className="min-w-0 flex-1">
            <div className="h-4 w-28 rounded-full bg-white/25" />
            <div className="mt-2 h-2.5 w-20 rounded-full bg-white/20" />
          </div>
        </div>
        <div className="h-12 w-9 rounded-champ bg-white/15" />
      </div>
      <div className="grid grid-cols-2 gap-2.5">
        {[0, 1, 2, 3].map((rang) => (
          <Carte key={rang} className="rounded-carte-sm h-[68px] p-3.5">
            <Barre largeur="w-14" hauteur="h-2.5" />
            <Barre largeur="w-10" hauteur="h-5" className="mt-2.5" />
          </Carte>
        ))}
      </div>
      {/* La silhouette suit la vraie hauteur du bloc : l'aperçu fait 140px, et
          les quatre rangées 44px chacune — la zone tactile minimale, que
          `min-h-tactile` impose. Elles sont **quatre** et non trois : c'est
          l'état par défaut, « Ma livrée », donc Coque et Ailerons compris. Sans
          elles, l'écran sauterait de deux cents pixels à l'arrivée des
          données. */}
      <Carte className="flex flex-col gap-3">
        <Barre largeur="w-24" hauteur="h-2.5" />
        <Pave className="mx-auto h-[140px] w-[70px]" />
        <Pave className="h-[44px]" />
        <Pave className="h-[44px]" />
        <Pave className="h-[44px]" />
        <Pave className="h-[44px]" />
      </Carte>
    </div>
  );
}

/**
 * Bloc rouge d'en-tête : pseudo, voiture et numéro (maquettes 12 et 14).
 *
 * `voiture` reçoit la ligne complète — profil ou ligne de classement — et
 * `livreeDuMembre` en tire ce qu'il faut peindre. Passer les deux couleurs
 * séparément ferait perdre la livrée d'écurie en chemin.
 */
export function HeroProfil({ pseudo, voiture, numero, action }) {
  const livree = livreeDuMembre(voiture);

  return (
    <div className="rounded-bloc bg-primaire shadow-bloc flex items-center justify-between gap-4 p-5">
      <div className="flex min-w-0 items-center gap-3.5">
        <Pastille nom={pseudo} graine={pseudo} taille="lg" />
        <div className="min-w-0">
          <p className="truncate text-[22px] font-medium text-white">
            {pseudo || "Pilote"}
          </p>
          {action && (
            <p className="mt-0.5 text-[12px] text-white/50">{action}</p>
          )}
        </div>
      </div>

      <div className="flex shrink-0 items-center gap-2.5">
        <Voiture
          {...livree}
          numero={numero ?? ""}
          nom={pseudo}
          titre={`Voiture de ${pseudo || "ce membre"}`}
          className="h-[58px] w-auto"
        />
        {/* Le numéro est la seule graisse 700 autorisée hors de la voiture
            (section 5). Sans numéro choisi, rien ne s'écrit : « #— » serait un
            numéro inventé. */}
        {numero != null && (
          <span className="text-[30px] leading-none font-bold text-white/30">
            #{numero}
          </span>
        )}
      </div>
    </div>
  );
}

export default function MonProfil() {
  const { utilisateur, estAdmin, deconnecter } = useAuth();
  const naviguer = useNavigate();

  const profilId = utilisateur?.id ?? null;

  const cle = profilId ? cleProfil(profilId, profilId) : null;
  const chargeur = useCallback(
    (signal) => chargerProfilComplet(profilId, signal),
    [profilId],
  );
  const { donnees, chargement, echec, recharger, remplacer } = useDonnees(
    cle,
    chargeur,
  );
  const [tentativeChargement, setTentativeChargement] = useState(0);

  function reessayerChargement() {
    setTentativeChargement((n) => n + 1);
    recharger();
  }

  const profil = donnees?.profil ?? null;

  // ---- Saisie ------------------------------------------------------------
  // L'état de saisie **suit le profil servi tant que le membre n'a rien
  // touché**, et se fige dès qu'il touche à quelque chose.
  //
  // Les deux moitiés comptent, et c'est le défaut corrigé ici. Le cache
  // *stale-while-revalidate* affiche d'abord ce qu'il savait : sans le suivi,
  // la réponse fraîche arrivait bien mais la saisie gardait la valeur périmée,
  // et l'ancienne couleur restait à l'écran indéfiniment. Sans le figeage, la
  // revalidation en arrière-plan effacerait une couleur en cours de choix.
  const [saisie, setSaisie] = useState(null);
  const [edite, setEdite] = useState(false);
  const [ouvert, setOuvert] = useState(null);
  const [enregistre, setEnregistre] = useState(false);

  useEffect(() => {
    if (!profil || edite) return;
    setSaisie(saisieDepuis(profil));
  }, [profil, edite]);

  /** Modifie un champ de la saisie et fige le suivi du serveur. */
  const modifier = useCallback((champs) => {
    setEdite(true);
    setEnregistre(false);
    setSaisie((precedente) => ({ ...precedente, ...champs }));
  }, []);

  const [envoi, setEnvoi] = useState(false);
  // Échec de l'ENREGISTREMENT, à ne pas confondre avec celui du chargement
  // rendu par `useDonnees` : l'un est un message de refus métier posé sous le
  // bouton, l'autre remplace l'écran.
  const [echecEnvoi, setEchecEnvoi] = useState(null);
  const [tentative, setTentative] = useState(0);

  // Les numéros déjà pris sont chargés **une seule fois** : la vérification à
  // chaque frappe se fait ensuite en mémoire. Un appel réseau par caractère
  // saisi serait le pire compromis possible pour un avertissement qui ne bloque
  // rien (l'unicité du numéro est indicative, voir la migration).
  const [pris, setPris] = useState([]);
  useEffect(() => {
    if (!profilId) return undefined;
    const controleur = new AbortController();
    let actif = true;

    (async () => {
      try {
        const resultat = await chargerNumerosPris(profilId, controleur.signal);
        if (actif && resultat.ok) setPris(resultat.donnees);
      } catch {
        // L'avertissement est un confort : son échec ne doit rien empêcher.
      }
    })();

    return () => {
      actif = false;
      controleur.abort();
    };
  }, [profilId]);

  // `voiture` est la saisie si elle existe, le profil servi sinon. Ce repli
  // n'est pas théorique : l'effet de synchronisation ne tourne qu'APRÈS le
  // premier rendu, et sans lui la première image afficherait une voiture aux
  // couleurs par défaut et un numéro vide alors que le cache les connaît déjà.
  // Tout ce que l'écran lit passe donc par `voiture`, jamais par `saisie`.
  const voiture = saisie ?? saisieDepuis(profil);
  const numero = voiture.numero;
  const numeroSaisi = numero ? Number(numero) : null;
  // **Une seule question, un seul juge.** « Un skin est-il actif ? » commande
  // désormais trois choses — le message d'explication, la valeur passée au
  // sélecteur, et la présence même de Coque et Ailerons. Trois conditions
  // écrites séparément auraient divergé au premier ajustement. Le slug est
  // exigé avec le mode, comme le fait `livreeDuMembre` : un mode `ecurie` sans
  // livrée ne peint rien.
  const skinActif = voiture.mode === "ecurie" && Boolean(voiture.ecurie);

  const porteur = useMemo(() => porteurDuNumero(pris, numero), [pris, numero]);

  const modifie =
    Boolean(profil) &&
    (voiture.couleur1 !== profil.couleur1 ||
      voiture.couleur2 !== profil.couleur2 ||
      voiture.mode !== livreeDuMembre(profil).mode ||
      voiture.ecurie !== (profil.livree_ecurie ?? null) ||
      (numeroSaisi ?? null) !== (profil.numero ?? null));

  async function enregistrer() {
    setEnvoi(true);
    setEchecEnvoi(null);
    setEnregistre(false);
    setTentative((n) => n + 1);

    const resultat = await enregistrerVoiture({
      couleur1: voiture.couleur1,
      couleur2: voiture.couleur2,
      livree_mode: voiture.mode,
      // Le slug n'est transmis que s'il existe : `null` serait refusé par le
      // format en base, et il n'y a rien à écrire tant qu'aucune livrée n'a
      // jamais été choisie.
      ...(voiture.ecurie ? { livree_ecurie: voiture.ecurie } : {}),
      // `retirer_numero` est un drapeau explicite : un `numero: null` serait
      // indiscernable d'un champ non transmis côté backend, et personne ne
      // pourrait plus revenir à l'état sans numéro.
      ...(numeroSaisi ? { numero: numeroSaisi } : { retirer_numero: true }),
    });

    setEnvoi(false);

    if (!resultat.ok) {
      setEchecEnvoi(resultat.message);
      return;
    }

    setEnregistre(true);

    // **`remplacer` et non `setDonnees` : le cache doit suivre.** `setDonnees`
    // ne touche que l'état React ; le cache `localStorage` gardait alors la
    // version d'avant, et c'est lui qui est relu au montage suivant. C'est
    // précisément ce qui faisait réapparaître l'ancienne couleur en revenant
    // sur le profil.
    remplacer({ ...donnees, profil: resultat.donnees });

    // Le profil rendu par la route fait foi : il porte les valeurs normalisées
    // par le backend (couleurs en majuscules), pas celles de la saisie. La
    // saisie repart de lui, et redevient suiveuse du serveur.
    setSaisie(saisieDepuis(resultat.donnees));
    setEdite(false);

    // Les classements affichent cette voiture : leur cache doit repartir de
    // zéro, sinon la vue liste et la vue piste garderaient l'ancienne livrée
    // jusqu'au prochain chargement complet. Tous les championnats du membre
    // sont concernés — sa voiture est la même partout (section 5) — et l'écran
    // ne les connaît pas : d'où l'effacement par préfixe.
    oublierCachePrefixe(`classement:${profilId}:`);
  }

  async function seDeconnecter() {
    const resultat = await deconnecter();
    if (resultat.ok) naviguer("/", { replace: true });
  }

  if (echec && !donnees) {
    return (
      <Ecran direction="avant">
        <Bloc rang={1}>
          <EnTete titre="Mon profil" retourVers="/accueil" />
        </Bloc>
        <Bloc rang={2}>
          <BlocErreur
            echec={echec}
            onReessayer={reessayerChargement}
            tentative={tentativeChargement}
          />
        </Bloc>
      </Ecran>
    );
  }

  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete titre="Mon profil" retourVers="/accueil" />
      </Bloc>

      <div className="flex flex-1 flex-col gap-3">
        <Bloc rang={2}>
          <ZoneChargement
            chargement={chargement && !donnees}
            squelette={<SqueletteProfil />}
          >
            {profil && (
              <div className="flex flex-col gap-3">
                <HeroProfil
                  pseudo={profil.pseudo}
                  voiture={{
                    couleur1: voiture.couleur1,
                    couleur2: voiture.couleur2,
                    livree_mode: voiture.mode,
                    livree_ecurie: voiture.ecurie,
                  }}
                  numero={numeroSaisi}
                  action="Saison 2026"
                />

                <GrilleStats stats={donnees?.stats} />

                <div className="rounded-carte bg-surface shadow-carte p-4">
                  <p className="text-label text-texte-doux mb-3 uppercase">
                    Ma livrée
                  </p>

                  {/* L'aperçu est au-dessus des réglages et centré : c'est le
                      sujet de l'écran, et il reste sous les yeux pendant qu'on
                      règle les couleurs comme pendant qu'on essaie un skin. */}
                  <Voiture
                    mode={voiture.mode}
                    ecurie={voiture.ecurie}
                    couleur1={voiture.couleur1}
                    couleur2={voiture.couleur2}
                    numero={numeroSaisi ?? ""}
                    nom={profil.pseudo}
                    titre="Aperçu de ta voiture"
                    className="mx-auto h-[140px] w-auto"
                  />

                  {/* **L'ordre suit la portée de chaque réglage.** Le numéro
                      s'écrit sur le museau quelle que soit la livrée : il est
                      donc au-dessus, hors de tout ce que le skin commande.
                      Vient le skin, puis — seulement s'il vaut « Ma livrée » —
                      les deux couleurs qu'il commande. Un contrôle est posé
                      juste au-dessus de ce qu'il modifie ; posé en dessous, il
                      faudrait un libellé pour dire ce qu'il gouverne. */}
                  <div className="mt-1.5 flex min-h-tactile items-center justify-between gap-3 py-1.5">
                    <label
                      htmlFor="numero-voiture"
                      className="text-corps-sm text-texte-doux"
                    >
                      Numéro
                    </label>
                    <div className="rounded-champ bg-fond flex items-center">
                      <span
                        aria-hidden="true"
                        className="text-texte-doux pl-3 text-[15px]"
                      >
                        #
                      </span>
                      <input
                        id="numero-voiture"
                        // `inputMode` plutôt que `type="number"` : sur iOS le
                        // second ouvre un clavier à flèches, accepte les signes
                        // et le « e », et affiche des incrémenteurs dont
                        // personne n'a besoin pour deux chiffres.
                        inputMode="numeric"
                        autoComplete="off"
                        maxLength={2}
                        placeholder="—"
                        value={numero}
                        onChange={(evenement) =>
                          modifier({
                            numero: nettoyerNumero(evenement.target.value),
                          })
                        }
                        className="text-texte w-[46px] bg-transparent py-2 pr-3 pl-0.5 text-[15px] font-medium outline-none"
                      />
                    </div>
                  </div>

                  {/* Le skin n'est pas un second mode : `null` vaut « ma
                      livrée », et c'est la valeur d'un nouveau joueur — celle du
                      défaut de colonne (`livree_mode` vaut `perso`) comme celle
                      que rend `livreeDuMembre` quand il ne trouve rien. `mode`
                      s'en déduit, il n'est plus choisi à la main, donc les deux
                      ne peuvent plus se contredire. */}
                  <SelecteurSkin
                    valeur={skinActif ? voiture.ecurie : null}
                    couleur1={voiture.couleur1}
                    couleur2={voiture.couleur2}
                    ouvert={ouvert === 3}
                    onOuvrir={() => setOuvert(ouvert === 3 ? null : 3)}
                    onChange={(slug) => {
                      modifier(
                        slug
                          ? { mode: "ecurie", ecurie: slug }
                          : { mode: "perso" },
                      );
                      setOuvert(null);
                    }}
                  />

                  {/* **Coque et Ailerons quittent le DOM sous un skin d'écurie**,
                      ils ne sont ni grisés ni transparents : sous une livrée
                      fixe ils ne peignent plus rien, et un réglage sans effet
                      qui reste tabulable et lisible au lecteur d'écran est pire
                      qu'un réglage absent.

                      Ce qu'ils rendaient — voir vers quoi on revient — est
                      repris par la case « Ma livrée » du sélecteur ci-dessus,
                      qui montre les deux couleurs en diagonale. La question
                      n'est donc pas restée sans réponse, elle a changé de
                      propriétaire.

                      Le repli sert le retour autant que le départ : les deux
                      rangées reviennent en poussant le bouton d'enregistrement
                      vers le bas au lieu de le faire apparaître dessous. */}
                  <Repli visible={!skinActif}>
                    <SelecteurCouleur
                      libelle="Coque"
                      valeur={voiture.couleur1}
                      interdite={voiture.couleur2}
                      ouvert={ouvert === 1}
                      onOuvrir={() => setOuvert(ouvert === 1 ? null : 1)}
                      onChange={(hex) => {
                        modifier({ couleur1: hex });
                        setOuvert(null);
                      }}
                    />
                    <SelecteurCouleur
                      libelle="Ailerons"
                      valeur={voiture.couleur2}
                      interdite={voiture.couleur1}
                      ouvert={ouvert === 2}
                      onOuvrir={() => setOuvert(ouvert === 2 ? null : 2)}
                      onChange={(hex) => {
                        modifier({ couleur2: hex });
                        setOuvert(null);
                      }}
                    />
                  </Repli>

                  {/* La phrase prend la place que les deux rangées viennent de
                      libérer, et c'est elle qui dit où elles sont parties. Le
                      marron `secondaire` et non `texte-doux` : 9,4:1 sur blanc
                      contre 2,0:1, et c'est une phrase qu'on vient lire. */}
                  {skinActif && (
                    <p className="text-corps-sm text-secondaire mt-2">
                      Le skin remplace ta livrée sur la piste et dans les
                      classements. Choisis « Ma livrée » pour retrouver la coque
                      et les ailerons.
                    </p>
                  )}

                  {/* L'avertissement ne bloque jamais l'enregistrement :
                      l'unicité du numéro est indicative, et deux membres qui
                      tiennent au 44 doivent pouvoir le garder. */}
                  {porteur && (
                    <p className="text-corps-sm text-secondaire mt-3">
                      Le {numeroSaisi} est déjà porté par {porteur} dans un de tes
                      championnats. Tu peux quand même le garder.
                    </p>
                  )}

                  {numero === "0" && (
                    <p className="text-corps-sm text-secondaire mt-3">
                      Le numéro va de 1 à {NUMERO_MAXIMUM}. Laisse le champ vide
                      pour ne pas en porter.
                    </p>
                  )}

                  {echecEnvoi && (
                    <div className="mt-3">
                      <Alerte ton="erreur" tentative={tentative}>
                        {echecEnvoi}
                      </Alerte>
                    </div>
                  )}

                  <div className="mt-3.5">
                    <Bouton
                      variante="principal"
                      onClick={enregistrer}
                      occupe={envoi}
                      libelleOccupe="Enregistrement…"
                      disabled={!modifie && !echecEnvoi}
                    >
                      {enregistre && !modifie
                        ? "Voiture enregistrée"
                        : "Enregistrer ma voiture"}
                    </Bouton>
                  </div>
                </div>

                {/* La section n'existe que pour un administrateur. Elle est
                    posée en dernier, sous la personnalisation : c'est un outil
                    d'exploitation, pas une partie du profil, et il n'a aucune
                    raison de passer devant la voiture ni devant les
                    statistiques.

                    **C'est le seul endroit de l'app qui lise `estAdmin` et non
                    `modeAdmin`, et ce n'est pas un oubli** : la section porte
                    l'interrupteur, elle doit donc rester visible interrupteur
                    éteint — sinon il n'y aurait plus rien pour le rallumer, et
                    il faudrait se déconnecter pour sortir du mode membre.
                    Toute AUTRE surface d'administration se conditionne à
                    `modeAdmin`. */}
                {estAdmin && <SectionAdmin />}
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        <div className="min-h-3 flex-1" />
      </div>

      <footer className="flex flex-col items-center gap-3 pt-5">
        <button
          type="button"
          onClick={seDeconnecter}
          className="text-texte-doux min-h-tactile pressable -my-2 px-3 py-2 text-[13px] font-medium"
        >
          Se déconnecter
        </button>
        <span className="text-label-sm text-texte-doux uppercase">
          Version {APP_VERSION}
        </span>
      </footer>
    </Ecran>
  );
}
