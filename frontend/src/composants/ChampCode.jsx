import { useEffect, useId, useRef, useState } from "react";
import { dureeCss, useSecousse } from "../lib/secousse.js";

export const LONGUEUR_CODE = 6;

/** Le champ ne laisse entrer que ce que le code peut contenir (règle 4.5). */
export function normaliserCode(valeur) {
  return valeur
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, LONGUEUR_CODE);
}

/**
 * Saisie du code d'invitation de la maquette 06 : six cases, une par caractère.
 *
 * Une seule zone de saisie réelle, transparente, posée sur les cases. Six
 * `<input>` séparés obligeraient à gérer à la main le retour arrière, le
 * collage d'un code entier et le déplacement du curseur — et sur iOS, chaque
 * changement de champ fait sursauter le clavier. Ici le collage fonctionne
 * naturellement, et la correction aussi.
 *
 * Les cases ne sont que du décor : elles portent `aria-hidden`, le lecteur
 * d'écran n'entend que le champ, avec son libellé.
 */
export default function ChampCode({
  valeur,
  onChange,
  erreur = null,
  tentative = 0,
  autoFocus = false,
}) {
  const id = useId();
  const idErreur = `${id}-erreur`;
  const champ = useRef(null);
  const boite = useSecousse(erreur, tentative);

  const [actif, setActif] = useState(false);

  const [message, setMessage] = useState(erreur);
  useEffect(() => {
    if (erreur) {
      setMessage(erreur);
      return undefined;
    }
    const minuterie = setTimeout(
      () => setMessage(null),
      dureeCss("--revert-dur", 280),
    );
    return () => clearTimeout(minuterie);
  }, [erreur]);

  const cases = Array.from({ length: LONGUEUR_CODE }, (_, index) => ({
    index,
    caractere: valeur[index] ?? null,
    // La case « en cours » n'est mise en avant que si le champ a le focus :
    // un curseur qui clignote sur un formulaire inactif est un faux signal.
    courante: actif && index === Math.min(valeur.length, LONGUEUR_CODE - 1),
  }));

  return (
    <div className={`t-input-wrap ${erreur ? "is-error" : ""}`}>
      <label htmlFor={id} className="text-label text-texte-doux mb-3.5 block uppercase">
        Code d'invitation
      </label>

      <div ref={boite} className="t-input relative">
        <input
          ref={champ}
          id={id}
          name="code"
          type="text"
          inputMode="text"
          autoComplete="one-time-code"
          autoCapitalize="characters"
          autoCorrect="off"
          spellCheck={false}
          autoFocus={autoFocus}
          maxLength={LONGUEUR_CODE}
          value={valeur}
          aria-invalid={erreur ? "true" : undefined}
          aria-describedby={erreur ? idErreur : undefined}
          onChange={(evenement) => onChange(normaliserCode(evenement.target.value))}
          onFocus={() => setActif(true)}
          onBlur={() => setActif(false)}
          // Transparent et posé sur les cases : l'appui n'importe où dans le
          // bloc ouvre le clavier, et le curseur natif reste invisible.
          className="absolute inset-0 z-10 h-full w-full cursor-pointer text-transparent caret-transparent opacity-0 outline-none"
        />

        <div aria-hidden="true" className="flex justify-center gap-2">
          {cases.map(({ index, caractere, courante }) => (
            <div
              key={index}
              className={`flex h-[58px] w-12 items-center justify-center rounded-champ text-[22px] font-medium transition-colors duration-150 ${
                caractere !== null
                  ? "bg-primaire text-white"
                  : courante
                    ? "bg-fond text-texte-doux ring-2 ring-primaire/25"
                    : "bg-fond text-texte-doux/40"
              }`}
            >
              {caractere ?? "—"}
            </div>
          ))}
        </div>
      </div>

      {message && (
        <p
          id={idErreur}
          role="alert"
          className="t-error-msg text-corps-sm text-primaire mt-3 px-1 text-center"
        >
          {message}
        </p>
      )}
    </div>
  );
}
