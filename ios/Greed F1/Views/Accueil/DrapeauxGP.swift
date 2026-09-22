// Généré par « ios/scripts/extraire-gp.mjs » — ne pas modifier à la main.
//
// Les teintes de chaque drapeau, reprises de `frontend/src/composants/DrapeauxGP.jsx`.
// Elles ne peignent rien : c'est de la bande la plus claire que `ApparenceDrapeau`
// dérive le voile du widget. **Toute forme peinte par le drapeau doit avoir sa teinte
// ici** — un drapeau dont on tairait le blanc recevrait un voile trop léger, et le
// texte blanc du widget y disparaîtrait.

enum TeintesDrapeaux {
    static let table: [String: [UInt32]] = [
        "pays-bas": [0xAE1C28, 0xFFFFFF, 0x21468B],
        "italie": [0x009246, 0xFFFFFF, 0xCE2B37],
        "espagne": [0xAA151B, 0xF1BF00, 0xAA151B],
        "azerbaidjan": [0x0092BC, 0xE8192C, 0x00B050],
        "malaisie": [0xCC3128, 0xF8F9FB, 0x262956, 0xF3C839],
        "singapour": [0xEF3340, 0xFFFFFF],
        "etats-unis": [0xB42C47, 0xF8F9FB, 0x23365C],
        "mexique": [0x036939, 0xFEFEFE, 0xD02E26, 0xAC692B],
        "bresil": [0x408C43, 0xF9DF3B, 0x0C5282, 0xFFFFFF],
        "las-vegas": [0xB42C47, 0xF8F9FB, 0x23365C],
        "qatar": [0x8B253D, 0xFFFFFF],
        "abu-dhabi": [0x078544, 0xFFFFFF, 0xC92F35, 0x010101],
    ]
}
