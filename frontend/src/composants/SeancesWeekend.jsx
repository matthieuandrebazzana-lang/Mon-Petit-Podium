import { SEANCES, seancesDuGp } from "../lib/calendrier2026.js";
import { formaterSeance } from "../lib/format.js";

/**
 * Le programme du week-end — cinq rangées, en heure locale du téléphone.
 *
 * C'est le premier bloc de l'écran « Détail GP », et c'est ce qu'on vient y
 * chercher : à quelle heure regarder. Les cinq séances sont datées par
 * `seancesDuGp`, qui laisse la base l'emporter sur la table statique partout où
 * elle a une réponse — voir sa note, et l'écart signalé en tête de
 * `calendrier2026.js`.
 *
 * **Cinq rangées dans UN bloc, pas cinq cartes.** Ce sont cinq valeurs d'une
 * même liste, lues d'un coup et comparées entre elles ; cinq cartes ombrées
 * auraient fait cinq objets là où il n'y a qu'un programme. Les rangées se
 * séparent par du blanc, jamais par un filet — la section 3 du design system
 * proscrit les bordures fines.
 *
 * ## Les deux états d'une rangée
 *
 * **Passée — `opacity: 0,5`.**
 *
 * > ### Écart mesuré, et assumé (CLAUDE.md §6)
 * >
 * > L'opacité compose l'encre ET son fond sur le blanc de la carte : `#1A1A1A`
 * > à 50 % y donne `#8D8D8D`, soit **3,07:1**, sous le plancher de 4,5:1 d'un
 * > texte ordinaire. C'est **0,65** qui le repasse (`#6E6E6E`, 4,63:1).
 * >
 * > La valeur est celle qui a été demandée, et l'arbitrage est celui déjà
 * > retenu pour les cartes de Grand Prix terminées (`calendrier.md` §8) : la
 * > seule information qu'on cherche sur une séance passée est « c'est fait »,
 * > et elle se lit à la pâleur avant de se lire au mot. Le jour et l'heure
 * > restent là pour qui les cherche.
 *
 * **Imminente — moins de vingt-quatre heures.** La rangée prend un aplat amber
 * très pâle et une **pastille amber à encre foncée**, exactement la pastille
 * « Pronos ouverts » d'`ETATS_GP`. C'est un choix mesuré, pas décoratif : sur du
 * blanc l'amber ne vaut que **2,22:1** en encre et **aucun** ton chaud du design
 * system ne tient 4,5:1 — un filet ou un texte amber auraient été un repère
 * illisible. L'amber n'existe que comme aplat, et l'aplat porte ici `#1A1A1A`
 * à 7,86:1.
 *
 * Le seuil vaut vingt-quatre heures et pas davantage (`SEUIL_IMMINENT_MS`) :
 * plus large, il allumerait deux rangées, et deux mises en avant n'en sont
 * plus une.
 *
 * ## Ce qui n'anime pas, et pourquoi
 *
 * **Rien.** L'écran entre déjà sous `.t-ecran` et ses blocs sous
 * `.t-stagger-line` ; à l'intérieur, aucune de ces cinq rangées ne change
 * d'état sous les yeux de qui que ce soit. Une mise en avant qui pulserait
 * serait une animation perpétuelle sur un écran qu'on ouvre plusieurs fois par
 * week-end — la première question du portier, et la réponse est non. Aucun
 * jeton de mouvement n'est ajouté.
 *
 * De la même façon, la mise en avant ne porte **pas de compte à rebours**.
 * « Dans 3h » demanderait une horloge vivante pour ne pas rancir, donc un
 * `setInterval` sur un écran de consultation ; l'app en a déjà une
 * (`useFermeture`), et elle sert là où une échéance engage quelque chose. Ici
 * la date et l'heure suffisent à répondre à la question posée.
 */

/** Opacité d'une séance déjà courue. Voir l'écart mesuré en tête de fichier. */
const OPACITE_PASSEE = 0.5;

/** Ce qu'on écrit quand l'instant manque. Jamais « 00h00 », qui serait une
 *  heure ; jamais une rangée retirée, qui ferait croire à un week-end sans EL3. */
const ABSENT = "—";

function Rangee({ seance }) {
  const { jour, heure } = formaterSeance(seance.iso);

  return (
    <li
      className={`rounded-champ flex items-center justify-between gap-3 px-3 py-2.5 ${
        seance.imminente ? "bg-accent/10" : ""
      }`}
      style={seance.passee ? { opacity: OPACITE_PASSEE } : undefined}
    >
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <p className="text-corps text-texte font-medium">{seance.libelle}</p>
          {seance.imminente && (
            // Même aplat, même encre et même rayon que la pastille « Pronos
            // ouverts » : c'est le seul repère amber de l'app, et il doit dire
            // la même chose partout — « il se passe quelque chose ici ».
            <span className="bg-accent text-texte shrink-0 rounded-[10px] px-2 py-0.5 text-[11px] font-medium">
              Bientôt
            </span>
          )}
        </div>
        <p className="text-secondaire mt-0.5 truncate text-[12px]">
          {jour ?? "Horaire à confirmer"}
        </p>
      </div>

      {/* `tabular-nums` aligne les cinq heures sur leur colonne des dizaines :
          sans lui, « 09h30 » et « 13h00 » ne se lisent plus l'un sous l'autre.
          Le crénage négatif suit la règle du design system — un chiffre n'a ni
          jambage ni hampe, rien ne vient remplir l'espace entre deux glyphes. */}
      <p className="text-texte shrink-0 text-[17px] font-medium tracking-[-0.01em] tabular-nums">
        {heure ?? ABSENT}
      </p>
    </li>
  );
}

/** `maintenant` est injectable pour la même raison que dans `etatDuGpSaison` et
 *  `etatPronostics` : « cette séance est-elle passée ? » ne se vérifie pas sur
 *  une horloge qu'on ne contrôle pas. Il ne rend pas le composant vivant pour
 *  autant — rien ne le réévalue, et c'est voulu (voir l'en-tête). */
export default function SeancesWeekend({ gp, maintenant = Date.now() }) {
  const seances = gp ? seancesDuGp(gp, maintenant) : null;

  // Aucun Grand Prix, ou une table statique sans séances pour lui : on montre
  // les cinq noms sans leurs heures plutôt qu'un bloc vide. Le programme d'un
  // week-end de Formule 1 est vrai sans la base, exactement comme les douze
  // cartes du calendrier le sont (`calendrier.md` §1).
  const rangees =
    seances ??
    SEANCES.map((seance) => ({
      ...seance,
      iso: null,
      instant: null,
      confirmee: false,
      passee: false,
      imminente: false,
    }));

  return (
    <ul className="rounded-bloc bg-surface shadow-bloc space-y-0.5 p-2">
      {rangees.map((seance) => (
        <Rangee key={seance.cle} seance={seance} />
      ))}
    </ul>
  );
}
