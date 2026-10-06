import SwiftUI

/// Écran de démarrage minimal : sert à vérifier que le projet compile et tourne.
struct ContentView: View {
    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            Text("Greed F1")
                .font(.system(size: 44, weight: .bold, design: .default))
                .foregroundStyle(Color.encrePrimaire)
        }
    }
}

#Preview {
    ContentView()
}
