import SwiftUI

/// Cuenta → iCloud: whether the study syncs, how it's going, and a way to do it right now.
struct CloudSyncView: View {
    @Environment(CloudSync.self) private var cloud
    @State private var isSyncing = false

    private var statusText: String {
        switch cloud.status {
        case .off: "Desactivada en este \(Device.name)"
        case .checking: "Comprobando…"
        case .noAccount: "Inicia sesión en iCloud en Ajustes"
        case .unavailable: "iCloud no responde; se volverá a intentar"
        case .upToDate: "Al día"
        case .waiting:
            if let next = cloud.nextSync, next > .now {
                "Cambios pendientes: se subirán \(next.formatted(.relative(presentation: .named)))"
            } else {
                "Cambios pendientes"
            }
        case .syncing: "Sincronizando…"
        case .quotaExceeded: "Tu iCloud está lleno"
        }
    }

    private var statusSymbol: String {
        switch cloud.status {
        case .upToDate: "checkmark.icloud"
        case .waiting, .syncing, .checking: "arrow.trianglehead.2.clockwise.icloud"
        default: "exclamationmark.icloud"
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("Sincronizar con iCloud", isOn: Binding(get: { cloud.isEnabled }, set: { cloud.setEnabled($0) }))
            } footer: {
                Text("Tus estudios, notas, fechas y guías se guardan en tu iCloud privado y llegan a tus otros dispositivos. Yo no puedo verlos.")
            }

            if cloud.isEnabled {
                Section {
                    Label(statusText, systemImage: statusSymbol)
                    if let lastSync = cloud.lastSync {
                        LabeledContent("Última vez", value: lastSync.formatted(.relative(presentation: .named)))
                    }
                    Button("Sincronizar ahora", systemImage: "arrow.clockwise") {
                        isSyncing = true
                        Task {
                            await cloud.syncNow()
                            isSyncing = false
                        }
                    }
                    .disabled(isSyncing || cloud.status == .noAccount)
                } footer: {
                    Text("Los cambios suben 10 minutos después de hacerlos. Si cambias muchas cosas seguidas, esperan a que termines y unos minutos más. iOS puede retrasarlo si cierras la app antes.")
                }
            }
        }
        .navigationTitle("iCloud")
        .navigationBarTitleDisplayMode(.inline)
    }
}
