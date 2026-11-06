import SwiftUI

/// **Les écrans réels, sur les données d'exemple du parcours guidé** — empilés sur
/// l'accueil par ``EtapeParcours/pileAccueil``, jamais par un lien.
///
/// Ils reçoivent une liste de championnats **inerte** (``MesChampionnats/init(inerte:)``) :
/// ni lue, ni rechargée, ni écrite sur disque — un championnat d'exemple n'y entre jamais,
/// et la liste réelle de l'accueil ne bouge pas.
struct EcranDemoView: View {

    let ecran: EcranDemo

    @StateObject private var inerte = MesChampionnats(inerte: true)

    var body: some View {
        switch ecran {
        case .creer:
            CreerChampionnatView(mesChampionnats: inerte, demo: true)
        case .rejoindre:
            RejoindreChampionnatView(mesChampionnats: inerte, demo: true)
        case .championnat:
            ChampionnatDetailView(championnat: DonneesDemo.championnat, mesChampionnats: inerte)
        }
    }
}
