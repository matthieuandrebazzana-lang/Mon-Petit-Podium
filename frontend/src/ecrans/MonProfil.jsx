import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import Voiture from "../composants/Voiture.jsx";
import Pastille from "../composants/Pastille.jsx";
import GrilleStats from "../composants/GrilleStats.jsx";
import SelecteurCouleur from "../composants/SelecteurCouleur.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import { IconeChevronDroit, IconeDrapeau } from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import {
  chargerNumerosPris,
  chargerProfilComplet,
  cleProfil,
  enregistrerVoiture,
  porteurDuNumero,
} from "../lib/profils.js";
import { couleursDuMembre } from "../lib/palette.js";
import { oublierCachePrefixe, useDonnees } from "../lib/useDonnees.js";
import { APP_VERSION } from "../config.js";

/**
 * Maquette 14 — mon profil : ma voiture, mes statistiques, ma personnalisation.
 *
 * **Écarts assumés par rapport à la maquette**, tous documentés dans le
 * CLAUDE.md :
 *
 * 1. La maquette affiche une grille « MES GRANDS PRIX » de cartes illustrées
 *    par les tracés de `assets/gp-cards.svg`. L'extraction de ces tracés n'est
 *    pas au programme de l'étape 8 ; une rangée mène à l'écran qui liste
 *    vraiment ces Grands Prix (maquette 13), avec les pronostics dedans.
 * 2. La barre de navigation basse n'est toujours pas codée : l'onglet
 *    Calendrier n'a pas d'écran. La déconnexion, elle, **quitte l'accueil pour
 *    venir ici**, comme l'annonçait l'étape 3 — c'est sa place définitive.
 */

const NUMERO_MAXIMUM = 99;

/** Ne garde que des chiffres, et jamais plus de deux (numéro de 1 à 99). */
function nettoyerNumero(saisi) {
  return String(saisi ?? "").replace(/\D/g, "").slice(0, 2);
}

function SqueletteProfil() {
  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-bloc bg-primaire h-[104px]" />
      <div className="grid grid-cols-2 gap-2.5">
        {[0, 1, 2, 3].map((rang) => (
          <div key={rang} className="rounded-carte-sm bg-surface h-[68px]" />
        ))}
      </div>
      <div className="rounded-carte bg-surface h-[210px]" />
    </div>
  );
}

/** Bloc rouge d'en-tête : pseudo, voiture et numéro (maquettes 12 et 14). */
export function HeroProfil({ pseudo, voiture, numero, action }) {
  const couleurs = couleursDuMembre(voiture);

  return (
    <div className="rounded-bloc bg-primaire flex items-center justify-between gap-4 p-5">
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
          couleur1={couleurs.couleur1}
          couleur2={couleurs.couleur2}
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
  const { utilisateur, deconnecter } = useAuth();
  const naviguer = useNavigate();

  const profilId = utilisateur?.id ?? null;

  const cle = profilId ? cleProfil(profilId, profilId) : null;
  const chargeur = useCallback(
    (signal) => chargerProfilComplet(profilId, signal),
    [profilId],
  );
  const { donnees, chargement, erreur, setDonnees } = useDonnees(cle, chargeur);

  const profil = donnees?.profil ?? null;

  // ---- Saisie ------------------------------------------------------------
  // L'état de saisie part du profil chargé, puis vit sa vie. Il n'est réinitialisé
  // que lorsque le profil change d'identité (nouvelle réponse serveur), pas à
  // chaque rendu : sinon le rafraîchissement en arrière-plan du cache
  // *stale-while-revalidate* effacerait une couleur en cours de choix.
  const [couleur1, setCouleur1] = useState(null);
  const [couleur2, setCouleur2] = useState(null);
  const [numero, setNumero] = useState(null);
  const [ouvert, setOuvert] = useState(null);

  useEffect(() => {
    if (!profil) return;
    setCouleur1((actuelle) => actuelle ?? profil.couleur1);
    setCouleur2((actuelle) => actuelle ?? profil.couleur2);
    setNumero((actuel) =>
      actuel ?? (profil.numero == null ? "" : String(profil.numero)),
    );
  }, [profil]);

  const [envoi, setEnvoi] = useState(false);
  const [echec, setEchec] = useState(null);
  const [enregistre, setEnregistre] = useState(false);
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

  const porteur = useMemo(() => porteurDuNumero(pris, numero), [pris, numero]);

  const voiture = {
    couleur1: couleur1 ?? profil?.couleur1,
    couleur2: couleur2 ?? profil?.couleur2,
  };
  const numeroSaisi = numero ? Number(numero) : null;

  const modifie =
    Boolean(profil) &&
    (voiture.couleur1 !== profil.couleur1 ||
      voiture.couleur2 !== profil.couleur2 ||
      (numeroSaisi ?? null) !== (profil.numero ?? null));

  async function enregistrer() {
    setEnvoi(true);
    setEchec(null);
    setEnregistre(false);
    setTentative((n) => n + 1);

    const resultat = await enregistrerVoiture({
      couleur1: voiture.couleur1,
      couleur2: voiture.couleur2,
      // `retirer_numero` est un drapeau explicite : un `numero: null` serait
      // indiscernable d'un champ non transmis côté backend, et personne ne
      // pourrait plus revenir à l'état sans numéro.
      ...(numeroSaisi ? { numero: numeroSaisi } : { retirer_numero: true }),
    });

    setEnvoi(false);

    if (!resultat.ok) {
      setEchec(resultat.message);
      return;
    }

    setEnregistre(true);
    // Le profil rendu par la route fait foi : il porte les valeurs normalisées
    // par le backend (couleurs en majuscules), pas celles de la saisie.
    setDonnees((precedent) => ({ ...precedent, profil: resultat.donnees }));
    setCouleur1(resultat.donnees.couleur1);
    setCouleur2(resultat.donnees.couleur2);
    setNumero(resultat.donnees.numero == null ? "" : String(resultat.donnees.numero));

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

  if (erreur && !donnees) {
    return (
      <Ecran direction="avant">
        <Bloc rang={1}>
          <EnTete titre="Mon profil" retourVers="/accueil" />
        </Bloc>
        <Bloc rang={2}>
          <Alerte ton="erreur">{erreur}</Alerte>
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
                  voiture={voiture}
                  numero={numeroSaisi}
                  action="Saison 2026"
                />

                <GrilleStats stats={donnees?.stats} />

                <div className="rounded-carte bg-surface p-4">
                  <p className="text-label text-texte-doux mb-3 uppercase">
                    Ma voiture
                  </p>

                  <div className="flex items-center gap-4">
                    {/* L'aperçu est à gauche, les réglages à droite : le
                        résultat du choix reste sous les yeux pendant qu'on
                        choisit. C'est aussi ce que fait la maquette. */}
                    <Voiture
                      couleur1={voiture.couleur1}
                      couleur2={voiture.couleur2}
                      numero={numeroSaisi ?? ""}
                      nom={profil.pseudo}
                      titre="Aperçu de ta voiture"
                      className="h-[112px] w-auto shrink-0"
                    />

                    <div className="min-w-0 flex-1">
                      <SelecteurCouleur
                        libelle="Coque"
                        valeur={voiture.couleur1}
                        interdite={voiture.couleur2}
                        ouvert={ouvert === 1}
                        onOuvrir={() => setOuvert(ouvert === 1 ? null : 1)}
                        onChange={(hex) => {
                          setCouleur1(hex);
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
                          setCouleur2(hex);
                          setOuvert(null);
                        }}
                      />

                      <div className="flex min-h-tactile items-center justify-between gap-3 py-1.5">
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
                            // `inputMode` plutôt que `type="number"` : sur iOS
                            // le second ouvre un clavier à flèches, accepte les
                            // signes et le « e », et affiche des incrémenteurs
                            // dont personne n'a besoin pour deux chiffres.
                            inputMode="numeric"
                            autoComplete="off"
                            maxLength={2}
                            placeholder="—"
                            value={numero ?? ""}
                            onChange={(evenement) => {
                              setNumero(nettoyerNumero(evenement.target.value));
                              setEnregistre(false);
                            }}
                            className="text-texte w-[46px] bg-transparent py-2 pr-3 pl-0.5 text-[15px] font-medium outline-none"
                          />
                        </div>
                      </div>
                    </div>
                  </div>

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

                  {echec && (
                    <div className="mt-3">
                      <Alerte ton="erreur" tentative={tentative}>
                        {echec}
                      </Alerte>
                    </div>
                  )}

                  <div className="mt-3.5">
                    <Bouton
                      variante="principal"
                      onClick={enregistrer}
                      occupe={envoi}
                      libelleOccupe="Enregistrement…"
                      disabled={!modifie && !echec}
                    >
                      {enregistre && !modifie
                        ? "Voiture enregistrée"
                        : "Enregistrer ma voiture"}
                    </Bouton>
                  </div>
                </div>

                <Link
                  to={`/profils/${profilId}/grands-prix`}
                  className="rounded-carte bg-surface pressable min-h-tactile flex items-center gap-3.5 p-4"
                >
                  <span
                    aria-hidden="true"
                    className="bg-primaire rounded-champ flex size-[46px] shrink-0 items-center justify-center text-white"
                  >
                    <IconeDrapeau className="size-[22px]" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="text-corps text-texte block font-medium">
                      Mes Grands Prix
                    </span>
                    <span className="text-texte-doux mt-0.5 block text-[12px]">
                      {donnees?.stats?.gp_joues
                        ? `${donnees.stats.gp_joues} GP joué${
                            donnees.stats.gp_joues > 1 ? "s" : ""
                          } cette saison`
                        : "Tes pronostics, Grand Prix par Grand Prix"}
                    </span>
                  </span>
                  <IconeChevronDroit className="text-texte-doux size-4 shrink-0" />
                </Link>
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
