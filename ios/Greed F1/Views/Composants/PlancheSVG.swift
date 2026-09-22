import SwiftUI

/// Lecture d'une **planche SVG** posée dans `Resources/Vecteurs/`, forme par forme.
///
/// **Extraction, jamais reproduction** — la même règle que `decouper-icones.sh` et
/// `extraire-gp.mjs` (`ios/CLAUDE.md` §3), appliquée à des planches que le catalogue
/// d'assets ne peut pas servir.
///
/// > **Pourquoi ces cinq planches ne sont pas des `imageset`.** Une image du catalogue se
/// > teinte d'une seule encre (`template`) ou d'aucune. Or la voiture personnalisée demande
/// > **deux** aplats remplacés indépendamment, sur une trentaine de formes entrelacées avec
/// > les gris mécaniques — pneus, suspensions, fond plat, casque — qui, eux, ne bougent
/// > pas. Aucun rendu du catalogue ne sait faire ça. Le fichier est donc lu tel quel et ses
/// > `fill` sont substitués à la volée, exactement comme la version web remplace `cls-6` et
/// > `cls-14` (`frontend/src/composants/Voiture.jsx`).
///
/// **Ce n'est pas un moteur SVG.** Il couvre précisément ce que ces cinq planches
/// emploient, et rien de plus : `polygon`, `rect` (avec `rx`/`ry`), `circle`, `path`
/// limité à `M L H V C S Q T Z`, les classes d'une feuille `<style>` en tête de fichier,
/// et les transformations `translate` / `rotate` / `scale` / `matrix`. **Aucun arc** — les
/// cinq planches n'en contiennent pas une, vérifié fichier par fichier.
///
/// Les `<text>` de la planche sont **ignorés** : ce sont ses réserves (« ZoneName », un
/// numéro d'exemple), que ``VueVoiture`` réécrit au vrai pseudo et au vrai numéro.
struct PlancheSVG {

    /// Une forme de la planche : son tracé, en unités de la `viewBox` du fichier, et
    /// l'encre que le fichier lui donne — en minuscules, pour que la substitution n'ait
    /// qu'une seule orthographe à reconnaître.
    struct Forme {
        let chemin: Path
        let remplissage: String
    }

    let formes: [Forme]

    // MARK: - Chargement

    /// **Le cache n'est pas une optimisation cosmétique.** La grille de choix des skins
    /// monte douze vignettes d'un coup, et `matti.svg` pèse 79 formes : sans lui, la
    /// planche serait relue douze fois au premier affichage, puis à chaque recomposition
    /// que SwiftUI déclenche en faisant défiler l'écran.
    private static var cache: [String: PlancheSVG] = [:]

    /// La planche nommée, lue une fois pour toutes. Un fichier absent rend une planche
    /// **vide** plutôt qu'une erreur : un dessin manquant laisse un blanc, il ne fait pas
    /// tomber l'écran de profil.
    static func nommee(_ nom: String) -> PlancheSVG {
        if let connue = cache[nom] { return connue }
        let planche = Lecteur.lire(nom: nom) ?? PlancheSVG(formes: [])
        cache[nom] = planche
        return planche
    }
}

// MARK: - Lecteur

/// L'analyseur proprement dit. `XMLParser` en mode SAX : la planche est parcourue une fois,
/// sans arbre intermédiaire.
private final class Lecteur: NSObject, XMLParserDelegate {

    /// L'état hérité par un élément de son parent — la transformation accumulée et l'encre
    /// courante. Un `<g fill="…">` peint ses enfants qui ne se peignent pas eux-mêmes.
    private struct Herite {
        var transformation: CGAffineTransform
        var remplissage: String
    }

    private var pile: [Herite] = [Herite(transformation: .identity, remplissage: "")]
    private var classes: [String: String] = [:]
    private var formes: [PlancheSVG.Forme] = []

    /// Vrai tant qu'on est dans la feuille de style : `XMLParser` livre le texte par
    /// morceaux, donc on l'accumule au lieu de le traiter à la volée.
    private var dansLaFeuille = false
    private var feuille = ""

    /// Profondeur du `<text>` en cours, s'il y en a un. Les réserves de la planche ne sont
    /// pas des formes.
    private var profondeurTexte = 0

    static func lire(nom: String) -> PlancheSVG? {
        guard let url = Bundle.main.url(forResource: nom, withExtension: "svg", subdirectory: "Vecteurs")
                ?? Bundle.main.url(forResource: nom, withExtension: "svg"),
              let donnees = try? Data(contentsOf: url) else { return nil }

        let lecteur = Lecteur()
        let analyseur = XMLParser(data: donnees)
        analyseur.delegate = lecteur
        guard analyseur.parse() else { return nil }
        return PlancheSVG(formes: lecteur.formes)
    }

    // MARK: Delegate

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes attributs: [String: String]) {

        if element == "style" { dansLaFeuille = true; return }
        if element == "text" || element == "tspan" { profondeurTexte += 1 }

        let parent = pile[pile.count - 1]
        var etat = parent

        if let brut = attributs["transform"] {
            etat.transformation = Transformation.lire(brut).concatenating(parent.transformation)
        }
        if let classe = attributs["class"]?.split(separator: " ").first,
           let encre = classes[String(classe)] {
            etat.remplissage = encre
        }
        if let encre = attributs["fill"] {
            etat.remplissage = EncreSVG.normaliser(encre)
        }
        pile.append(etat)

        // Une forme posée dans un `<text>` n'existe pas ; le garde évite aussi de peindre
        // les `<tspan>` que Illustrator y glisse.
        guard profondeurTexte == 0, let chemin = Self.chemin(element, attributs) else { return }

        formes.append(PlancheSVG.Forme(
            chemin: chemin.applying(etat.transformation),
            remplissage: etat.remplissage
        ))
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        if element == "style" {
            dansLaFeuille = false
            classes = Self.lireFeuille(feuille)
            return
        }
        if element == "text" || element == "tspan" { profondeurTexte -= 1 }
        if pile.count > 1 { pile.removeLast() }
    }

    func parser(_ parser: XMLParser, foundCharacters texte: String) {
        if dansLaFeuille { feuille += texte }
    }

    func parser(_ parser: XMLParser, foundCDATA bloc: Data) {
        if dansLaFeuille, let texte = String(data: bloc, encoding: .utf8) { feuille += texte }
    }

    // MARK: Formes

    /// Le tracé d'un élément, en unités de la `viewBox`. `nil` pour tout ce qui n'est pas
    /// une des quatre formes que ces planches emploient.
    private static func chemin(_ element: String, _ a: [String: String]) -> Path? {
        func nombre(_ cle: String, _ defaut: CGFloat = 0) -> CGFloat {
            a[cle].flatMap { Double($0) }.map { CGFloat($0) } ?? defaut
        }

        switch element {
        case "path":
            guard let d = a["d"] else { return nil }
            var lecteur = LecteurChemin(d)
            return lecteur.tracer()

        case "polygon", "polyline":
            guard let brut = a["points"] else { return nil }
            let valeurs = Nombres.lire(brut)
            guard valeurs.count >= 4 else { return nil }
            var chemin = Path()
            chemin.move(to: CGPoint(x: valeurs[0], y: valeurs[1]))
            for i in stride(from: 2, to: valeurs.count - 1, by: 2) {
                chemin.addLine(to: CGPoint(x: valeurs[i], y: valeurs[i + 1]))
            }
            if element == "polygon" { chemin.closeSubpath() }
            return chemin

        case "rect":
            let boite = CGRect(x: nombre("x"), y: nombre("y"),
                               width: nombre("width"), height: nombre("height"))
            guard boite.width > 0, boite.height > 0 else { return nil }
            // `rx` seul vaut pour les deux rayons, et réciproquement — c'est la règle SVG,
            // et les pneus de la planche s'en servent (`rx` et `ry` y sont toujours égaux).
            let rx = a["rx"] != nil ? nombre("rx") : nombre("ry")
            let ry = a["ry"] != nil ? nombre("ry") : nombre("rx")
            guard rx > 0 || ry > 0 else { return Path(boite) }
            return Path(roundedRect: boite, cornerSize: CGSize(width: rx, height: ry), style: .continuous)

        case "circle":
            let r = nombre("r")
            guard r > 0 else { return nil }
            return Path(ellipseIn: CGRect(x: nombre("cx") - r, y: nombre("cy") - r,
                                          width: r * 2, height: r * 2))

        case "ellipse":
            let rx = nombre("rx"), ry = nombre("ry")
            guard rx > 0, ry > 0 else { return nil }
            return Path(ellipseIn: CGRect(x: nombre("cx") - rx, y: nombre("cy") - ry,
                                          width: rx * 2, height: ry * 2))

        default:
            return nil
        }
    }

    /// `{ nom de classe → encre }`. Seul `fill` est lu : les planches ne portent ni trait ni
    /// opacité, et un sélecteur groupé (`.cls-4, .cls-5 { … }`) donne la même encre aux deux.
    private static func lireFeuille(_ texte: String) -> [String: String] {
        var table: [String: String] = [:]
        for bloc in texte.split(separator: "}") {
            let morceaux = bloc.split(separator: "{", maxSplits: 1)
            guard morceaux.count == 2 else { continue }
            guard let encre = valeur("fill", dans: String(morceaux[1])) else { continue }
            for selecteur in morceaux[0].split(separator: ",") {
                let propre = selecteur.trimmingCharacters(in: .whitespacesAndNewlines)
                guard propre.hasPrefix(".") else { continue }
                table[String(propre.dropFirst())] = EncreSVG.normaliser(encre)
            }
        }
        return table
    }

    private static func valeur(_ propriete: String, dans corps: String) -> String? {
        for declaration in corps.split(separator: ";") {
            let paire = declaration.split(separator: ":", maxSplits: 1)
            guard paire.count == 2,
                  paire[0].trimmingCharacters(in: .whitespacesAndNewlines) == propriete
            else { continue }
            return paire[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

// MARK: - Couleurs de planche

/// Les encres d'une planche — **des chaînes, pas des `Color`**, parce que c'est sur elles
/// que porte la substitution : « partout où ce fichier écrit `#be1622`, peins `couleur1` ».
enum EncreSVG {

    /// Forme canonique d'une encre de planche : `#rrggbb` en minuscules. `#fff` est étendu,
    /// `none` reste `none`. Sans cette normalisation, `#EDEDED` du fichier et `#ededed` de
    /// la table de substitution ne se reconnaîtraient pas.
    static func normaliser<S: StringProtocol>(_ brut: S) -> String {
        let propre = brut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard propre.hasPrefix("#") else { return propre }
        let chiffres = propre.dropFirst()
        if chiffres.count == 3 {
            return "#" + chiffres.map { "\($0)\($0)" }.joined()
        }
        return "#" + chiffres.prefix(6)
    }

    /// `Color` d'une encre `#rrggbb`. `nil` pour `none` ou pour une chaîne illisible — la
    /// forme n'est alors simplement pas peinte.
    static func couleur(_ encre: String) -> Color? {
        let propre = normaliser(encre)
        guard propre.hasPrefix("#"), propre.count == 7,
              let valeur = UInt32(propre.dropFirst(), radix: 16) else { return nil }
        return Color(hexadecimal: valeur)
    }
}

// MARK: - Lecture des nombres

private enum Nombres {
    /// Tous les nombres d'une chaîne SVG, dans l'ordre. Les séparateurs y sont libres —
    /// virgule, espace, ou rien du tout devant un signe moins.
    static func lire<S: StringProtocol>(_ source: S) -> [CGFloat] {
        var valeurs: [CGFloat] = []
        var lecteur = LecteurChemin(String(source))
        while let valeur = lecteur.nombreSuivant() { valeurs.append(valeur) }
        return valeurs
    }
}

// MARK: - Données de chemin

/// L'analyseur d'un attribut `d`.
///
/// **Il ne gère pas les arcs**, et c'est délibéré : aucune des cinq planches n'en contient
/// (relevé commande par commande sur les cinq fichiers). Un `A` rencontré un jour serait
/// donc un fichier nouveau, pas une régression silencieuse — la commande est ignorée et le
/// tracé se ferme sur ce qu'il a.
private struct LecteurChemin {

    private let source: [Character]
    private var index = 0

    init(_ d: String) { source = Array(d) }

    /// Le tracé complet, en unités de la `viewBox`.
    mutating func tracer() -> Path {
        var chemin = Path()
        var courant = CGPoint.zero
        var depart = CGPoint.zero
        /// Le second point de contrôle de la dernière courbe — ce dont `S`/`T` ont besoin
        /// pour refléter leur tangente. Remis à zéro par toute autre commande, comme
        /// l'exige la spécification.
        var controlePrecedent: CGPoint?
        var controleQuadratique: CGPoint?
        var commande: Character = "M"

        while true {
            sauterSeparateurs()
            guard index < source.count else { break }

            if source[index].isLetter {
                commande = source[index]
                index += 1
                if commande == "Z" || commande == "z" {
                    chemin.closeSubpath()
                    courant = depart
                    controlePrecedent = nil
                    controleQuadratique = nil
                    continue
                }
            }

            let relatif = commande.isLowercase
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                relatif ? CGPoint(x: courant.x + x, y: courant.y + y) : CGPoint(x: x, y: y)
            }

            switch commande.lowercased().first {
            case "m":
                guard let x = nombreSuivant(), let y = nombreSuivant() else { return chemin }
                courant = point(x, y)
                depart = courant
                chemin.move(to: courant)
                // Les paires suivantes d'un `M` sont des `L`, c'est la spécification.
                commande = relatif ? "l" : "L"
                controlePrecedent = nil; controleQuadratique = nil

            case "l":
                guard let x = nombreSuivant(), let y = nombreSuivant() else { return chemin }
                courant = point(x, y)
                chemin.addLine(to: courant)
                controlePrecedent = nil; controleQuadratique = nil

            case "h":
                guard let x = nombreSuivant() else { return chemin }
                courant = CGPoint(x: relatif ? courant.x + x : x, y: courant.y)
                chemin.addLine(to: courant)
                controlePrecedent = nil; controleQuadratique = nil

            case "v":
                guard let y = nombreSuivant() else { return chemin }
                courant = CGPoint(x: courant.x, y: relatif ? courant.y + y : y)
                chemin.addLine(to: courant)
                controlePrecedent = nil; controleQuadratique = nil

            case "c":
                guard let x1 = nombreSuivant(), let y1 = nombreSuivant(),
                      let x2 = nombreSuivant(), let y2 = nombreSuivant(),
                      let x = nombreSuivant(), let y = nombreSuivant() else { return chemin }
                let c1 = point(x1, y1), c2 = point(x2, y2), fin = point(x, y)
                chemin.addCurve(to: fin, control1: c1, control2: c2)
                courant = fin; controlePrecedent = c2; controleQuadratique = nil

            case "s":
                guard let x2 = nombreSuivant(), let y2 = nombreSuivant(),
                      let x = nombreSuivant(), let y = nombreSuivant() else { return chemin }
                let c1 = controlePrecedent.map {
                    CGPoint(x: 2 * courant.x - $0.x, y: 2 * courant.y - $0.y)
                } ?? courant
                let c2 = point(x2, y2), fin = point(x, y)
                chemin.addCurve(to: fin, control1: c1, control2: c2)
                courant = fin; controlePrecedent = c2; controleQuadratique = nil

            case "q":
                guard let x1 = nombreSuivant(), let y1 = nombreSuivant(),
                      let x = nombreSuivant(), let y = nombreSuivant() else { return chemin }
                let c = point(x1, y1), fin = point(x, y)
                chemin.addQuadCurve(to: fin, control: c)
                courant = fin; controleQuadratique = c; controlePrecedent = nil

            case "t":
                guard let x = nombreSuivant(), let y = nombreSuivant() else { return chemin }
                let c = controleQuadratique.map {
                    CGPoint(x: 2 * courant.x - $0.x, y: 2 * courant.y - $0.y)
                } ?? courant
                let fin = point(x, y)
                chemin.addQuadCurve(to: fin, control: c)
                courant = fin; controleQuadratique = c; controlePrecedent = nil

            default:
                // Commande inconnue — `A` compris. On s'arrête net plutôt que de lire ses
                // paramètres comme des coordonnées et de rendre un gribouillis.
                return chemin
            }
        }
        return chemin
    }

    // MARK: Lexique

    private mutating func sauterSeparateurs() {
        while index < source.count, source[index] == " " || source[index] == ","
                || source[index] == "\n" || source[index] == "\r" || source[index] == "\t" {
            index += 1
        }
    }

    /// Le nombre suivant, ou `nil` à la fin. Il reconnaît le signe collé au chiffre
    /// précédent (`10-5`), la décimale sans zéro (`.5`) et l'exposant (`1e-3`) — les trois
    /// formes qu'Illustrator écrit.
    mutating func nombreSuivant() -> CGFloat? {
        sauterSeparateurs()
        let debut = index
        if index < source.count, source[index] == "-" || source[index] == "+" { index += 1 }
        var vu = false
        while index < source.count, source[index].isNumber { index += 1; vu = true }
        if index < source.count, source[index] == "." {
            index += 1
            while index < source.count, source[index].isNumber { index += 1; vu = true }
        }
        guard vu else { index = debut; return nil }
        if index < source.count, source[index] == "e" || source[index] == "E" {
            let reprise = index
            index += 1
            if index < source.count, source[index] == "-" || source[index] == "+" { index += 1 }
            var exposant = false
            while index < source.count, source[index].isNumber { index += 1; exposant = true }
            if !exposant { index = reprise }
        }
        return Double(String(source[debut..<index])).map { CGFloat($0) }
    }
}

// MARK: - Transformations

private enum Transformation {

    /// La matrice d'un attribut `transform`.
    ///
    /// > **L'ordre compte, et il est à l'envers de la lecture.** `translate(a) rotate(b)`
    /// > fait subir au point la rotation **d'abord**, la translation ensuite. La liste est
    /// > donc composée de la droite vers la gauche — l'inverse donnerait une planche dont
    /// > les ailerons avant partent en biais à côté de la voiture.
    static func lire(_ brut: String) -> CGAffineTransform {
        var resultat = CGAffineTransform.identity
        for (nom, arguments) in fonctions(brut) {
            let a = Nombres.lire(arguments)
            let etape: CGAffineTransform
            switch nom {
            case "translate":
                etape = CGAffineTransform(translationX: a.first ?? 0, y: a.count > 1 ? a[1] : 0)
            case "rotate":
                let angle = (a.first ?? 0) * .pi / 180
                if a.count > 2 {
                    etape = CGAffineTransform(translationX: -a[1], y: -a[2])
                        .concatenating(CGAffineTransform(rotationAngle: angle))
                        .concatenating(CGAffineTransform(translationX: a[1], y: a[2]))
                } else {
                    etape = CGAffineTransform(rotationAngle: angle)
                }
            case "scale":
                etape = CGAffineTransform(scaleX: a.first ?? 1, y: a.count > 1 ? a[1] : (a.first ?? 1))
            case "matrix":
                guard a.count >= 6 else { continue }
                etape = CGAffineTransform(a: a[0], b: a[1], c: a[2], d: a[3], tx: a[4], ty: a[5])
            default:
                continue
            }
            resultat = etape.concatenating(resultat)
        }
        return resultat
    }

    /// `translate(1 2) rotate(3)` → `[("translate", "1 2"), ("rotate", "3")]`.
    private static func fonctions(_ brut: String) -> [(String, String)] {
        var resultat: [(String, String)] = []
        var nom = ""
        var arguments = ""
        var dansArguments = false
        for caractere in brut {
            if caractere == "(" { dansArguments = true; arguments = ""; continue }
            if caractere == ")" {
                dansArguments = false
                resultat.append((nom.trimmingCharacters(in: .whitespacesAndNewlines), arguments))
                nom = ""
                continue
            }
            if dansArguments { arguments.append(caractere) } else { nom.append(caractere) }
        }
        return resultat
    }
}

// MARK: - Rendu

/// Une fenêtre de planche, peinte dans la place qu'on lui donne.
///
/// **C'est la planche entière derrière une `viewBox`**, jamais un tracé recopié — le même
/// principe que les icônes de la barre (`ios/CLAUDE.md` §3). La fenêtre est centrée et mise
/// à l'échelle sans déformation : l'équivalent exact de `preserveAspectRatio="xMidYMid meet"`.
struct VuePlanche: View {

    /// Nom du fichier dans `Resources/Vecteurs/`, sans extension.
    let planche: String

    /// La fenêtre découpée, en unités de la `viewBox` du fichier.
    let fenetre: CGRect

    /// `{ encre du fichier → encre à peindre }`, en `#rrggbb` minuscules. Vide, la planche
    /// garde ses couleurs.
    var substitutions: [String: Color] = [:]

    var body: some View {
        Canvas { contexte, taille in
            let cadre = CadrePlanche(fenetre: fenetre, taille: taille)
            contexte.transform = cadre.transformation
            for forme in PlancheSVG.nommee(planche).formes {
                guard let encre = substitutions[forme.remplissage] ?? EncreSVG.couleur(forme.remplissage)
                else { continue }
                contexte.fill(forme.chemin, with: .color(encre))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Le passage des unités de la planche aux points de l'écran.
///
/// **Il vit à part de ``VuePlanche``** parce que deux choses en ont besoin : le `Canvas`
/// qui peint les formes, et ce que ``VueVoiture`` pose *par-dessus* — la photo du cockpit,
/// le numéro, le pseudo. Deux calculs écrits séparément auraient décalé la photo du casque
/// dès la première retouche de cadrage.
struct CadrePlanche {

    let fenetre: CGRect
    let taille: CGSize

    /// Facteur d'échelle, sans déformation : la fenêtre entre entièrement dans la place
    /// donnée, comme `xMidYMid meet`.
    var echelle: CGFloat {
        guard fenetre.width > 0, fenetre.height > 0 else { return 1 }
        return min(taille.width / fenetre.width, taille.height / fenetre.height)
    }

    var transformation: CGAffineTransform {
        let e = echelle
        let dx = (taille.width - fenetre.width * e) / 2 - fenetre.minX * e
        let dy = (taille.height - fenetre.height * e) / 2 - fenetre.minY * e
        return CGAffineTransform(scaleX: e, y: e).concatenating(
            CGAffineTransform(translationX: dx, y: dy))
    }

    /// Un point de la planche, en points d'écran.
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: y).applying(transformation)
    }
}
