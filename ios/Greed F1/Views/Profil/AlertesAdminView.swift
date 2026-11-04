import SwiftUI

/// Les alertes d'administration, dans le bloc « Administration » du profil
/// (`GET /admin/alertes`).
///
/// **Elles n'existaient que sur le web** jusqu'à la `0.59.0` : l'alerte du remplaçant du
/// Mexique (« Hirakawa, Ryo ») était en base, et l'administrateur, sur iPhone, ne l'a jamais
/// vue (`bugs-connus.md` §44).
///
/// Une alerte de libellé se **résout ici** : un tap ouvre la liste des engagés du week-end,
/// le choix part sur `POST /admin/alertes/resoudre`, et le backend recalcule le GP. Les
/// autres alertes se lisent seulement.
struct AlertesAdminView: View {

    private enum Etat: Equatable {
        case chargement
        case indisponibles
        case pret([AlerteAdmin])
        case echec(ErreurAPI)
    }

    @State private var etat: Etat = .chargement
    @State private var alerteOuverte: AlerteAdmin?
    @State private var retour: String?

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("admin.alertes.titre"))
                .font(.custom("HelveticaNeue-Medium", size: 17))
                .foregroundColor(.texte)

            switch etat {
            case .chargement:
                SkeletonView(.ligneLongue)
            case .indisponibles:
                texteDoux(t("admin.alertes.indisponibles"))
            case .echec(let erreur):
                ErreurEnLigne(erreur: erreur)
            case .pret(let alertes) where alertes.isEmpty:
                texteDoux(t("admin.alertes.aucune"))
            case .pret(let alertes):
                ForEach(alertes) { alerte in
                    ligne(alerte)
                }
            }

            if let retour {
                Text(retour)
                    .font(.corpsSm)
                    .foregroundColor(.texte)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(mouvementReduit ? nil : Mouvement.entree(0.20), value: retour)
        .sensoryFeedback(.success, trigger: retour) { _, nouveau in nouveau != nil }
        .task { await charger() }
        .sheet(item: $alerteOuverte) { alerte in
            ChoixEngageView(alerte: alerte) { message in
                alerteOuverte = nil
                retour = message
                Task { await charger() }
            }
        }
    }

    @ViewBuilder
    private func ligne(_ alerte: AlerteAdmin) -> some View {
        let contenu = VStack(alignment: .leading, spacing: 2) {
            Text(alerte.gp?.isEmpty == false ? alerte.gp! : "—")
                .font(.label)
                .tracking(Tracking.label)
                .foregroundColor(.grisSecondaire)
            Text(alerte.titre)
                .font(.corps)
                .foregroundColor(.texte)
                .fixedSize(horizontal: false, vertical: true)
            if !alerte.detail.isEmpty {
                Text(alerte.detail)
                    .font(.corpsSm)
                    .foregroundColor(.grisSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if alerte.resoluble {
                Text(t("admin.alertes.choisir"))
                    .font(.custom("HelveticaNeue-Medium", size: 14))
                    .foregroundColor(.encrePrimaire)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())

        if alerte.resoluble {
            Button { alerteOuverte = alerte } label: { contenu }
                .buttonStyle(StyleAppui(.bouton))
        } else {
            contenu
        }
    }

    private func texteDoux(_ texte: String) -> some View {
        Text(texte)
            .font(.corpsSm)
            .foregroundColor(.grisSecondaire)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func charger() async {
        do {
            let reponse = try await Administration.chargerAlertes()
            etat = reponse.disponible ? .pret(reponse.alertes) : .indisponibles
        } catch let erreur as ErreurAPI {
            etat = .echec(erreur)
        } catch {
            // Tâche annulée : l'écran a été quitté.
        }
    }
}

/// La feuille du choix : les engagés **de ce Grand Prix**, pilotes ou écuries selon
/// l'issue. Un tap envoie le choix ; l'erreur éventuelle reste dite sous la liste.
private struct ChoixEngageView: View {

    let alerte: AlerteAdmin
    let termine: (String) -> Void

    @State private var engages: EngagesDuGP?
    @State private var erreur: ErreurAPI?
    @State private var envoi: String?

    @Environment(\.dismiss) private var fermer

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(t("admin.alertes.explicationChoix"))
                        .font(.corpsSm)
                        .foregroundColor(.grisSecondaire)
                    if let erreur {
                        ErreurEnLigne(erreur: erreur)
                    }
                }

                if let engages {
                    Section {
                        if alerte.choisitUneEcurie {
                            ForEach(engages.ecuries) { ecurie in
                                rangee(id: ecurie.id, titre: ecurie.nom, sousTitre: nil) {
                                    envoyer(numero: nil, ecurie: ecurie.ecurieId, id: ecurie.id)
                                }
                            }
                        } else {
                            ForEach(engages.pilotes) { pilote in
                                rangee(id: "\(pilote.numero)", titre: "n°\(pilote.numero) · \(pilote.nom)",
                                       sousTitre: pilote.equipe) {
                                    envoyer(numero: pilote.numero, ecurie: nil, id: "\(pilote.numero)")
                                }
                            }
                        }
                    }
                } else if erreur == nil {
                    Section { SkeletonView(.ligneLongue) }
                }
            }
            .navigationTitle(alerte.choisitUneEcurie
                             ? t("admin.alertes.choisirEcurie", alerte.libelle ?? "")
                             : t("admin.alertes.choisirPilote", alerte.libelle ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("admin.alertes.fermer")) { fermer() }
                }
            }
        }
        .sensoryFeedback(.error, trigger: erreur) { _, nouveau in nouveau != nil }
        .interactiveDismissDisabled(envoi != nil)
        .task { await charger() }
    }

    private func rangee(id: String, titre: String, sousTitre: String?,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre).font(.corps).foregroundColor(.texte)
                    if let sousTitre {
                        Text(sousTitre).font(.corpsSm).foregroundColor(.grisSecondaire)
                    }
                }
                Spacer()
                if envoi == id {
                    ProgressView()
                        .accessibilityLabel(t("admin.alertes.a11y.envoi"))
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(envoi != nil)
    }

    private func charger() async {
        guard let gpId = alerte.gpId else { return }
        do {
            engages = try await Administration.chargerEngages(gpId: gpId)
        } catch let refus as ErreurAPI {
            erreur = refus
        } catch {}
    }

    private func envoyer(numero: Int?, ecurie: String?, id: String) {
        guard envoi == nil else { return }
        envoi = id
        erreur = nil
        Task {
            do {
                let message = try await Administration.resoudre(
                    alerte: alerte, numeroPilote: numero, ecurieId: ecurie)
                termine(message)
            } catch let refus as ErreurAPI {
                erreur = refus
            } catch {}
            envoi = nil
        }
    }
}
