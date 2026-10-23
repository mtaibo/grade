import Engine
import SwiftUI

struct ContentView: View {
    private let placeholder = Subject(name: "Sin asignaturas", ectsCredits: 0, root: .grade(Grade(name: "—")))

    var body: some View {
        ContentUnavailableView(
            placeholder.name,
            systemImage: "function",
            description: Text("El motor de cálculo y la interfaz todavía no están conectados.")
        )
    }
}
