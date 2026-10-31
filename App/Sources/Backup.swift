import Foundation
import SwiftUI
import UIKit

/// The system share sheet for a file already on disk, presented by UIKit itself: wrapped in a
/// SwiftUI sheet it animated in twice.
@MainActor
enum ShareSheet {
    static func present(_ url: URL) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad shows it as a popover, which needs somewhere to point.
        controller.popoverPresentationController?.sourceView = top.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        top.present(controller, animated: true)
    }
}

/// Picking or opening a `.grade` file: read it, ask before replacing anything, then restore.
@MainActor
@Observable
final class BackupImportCenter {
    struct Pending: Identifiable {
        let id = UUID()
        let backup: GradeBackup
    }

    var isPicking = false
    var pending: Pending?
    var message: String?

    func prepare(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let data = try? Data(contentsOf: url) else { throw BackupError.unreadable }
            pending = Pending(backup: try GradeBackup.decode(data))
        } catch {
            message = error.localizedDescription
        }
    }

    func confirm(_ pending: Pending, into library: Library, replacing: Bool) {
        if replacing {
            library.restore(pending.backup)
        } else {
            library.merge(pending.backup)
        }
        let archives = pending.backup.archives?.count ?? 0
        message = "Se han importado \(pending.backup.subjectCount) asignaturas"
            + (archives == 0 ? "." : archives == 1 ? " y 1 estudio archivado." : " y \(archives) estudios archivados.")
        self.pending = nil
    }
}

/// Attached once at the root so a file chosen in Cuenta and a `.grade` opened from Files or AirDrop
/// go through the same confirmation.
struct BackupImportHost: ViewModifier {
    @Environment(Library.self) private var library
    @Bindable var center: BackupImportCenter

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $center.isPicking, allowedContentTypes: [.gradeBackup, .markBackup, .json]) { result in
                if case .success(let url) = result { center.prepare(url: url) }
            }
            .onOpenURL { center.prepare(url: $0) }
            .confirmationDialog(
                "¿Importar esta copia?",
                isPresented: Binding(get: { center.pending != nil }, set: { if !$0 { center.pending = nil } }),
                titleVisibility: .visible,
                presenting: center.pending
            ) { pending in
                Button("Añadir a lo que tengo") { center.confirm(pending, into: library, replacing: false) }
                // A copy of part of the study would leave only that part: the rest's grades would go.
                if pending.backup.scope == nil {
                    Button("Sustituir mi estudio actual", role: .destructive) { center.confirm(pending, into: library, replacing: true) }
                }
            } message: { pending in
                Text(Self.summary(of: pending.backup))
            }
            .alert("Copia de seguridad", isPresented: Binding(get: { center.message != nil }, set: { if !$0 { center.message = nil } })) {
                Button("Vale") {}
            } message: {
                Text(center.message ?? "")
            }
    }

    private static func summary(of backup: GradeBackup) -> String {
        var text = "La copia tiene \(backup.subjectCount) asignaturas"
        if let scope = backup.scope { text += " (\(scope))" }
        if backup.includesGrades == false { text += ", sin notas" }
        if let archives = backup.archives, !archives.isEmpty {
            text += archives.count == 1 ? " y 1 estudio archivado" : " y \(archives.count) estudios archivados"
        }
        if backup.scope != nil {
            return text + ". Se suman a las tuyas y sustituyen las que ya estaban en la copia. Como es solo una parte del estudio, no puede sustituir el tuyo entero. No se puede deshacer."
        }
        return text + ". «Añadir» las suma a las tuyas y sustituye las que ya estaban en la copia; «Sustituir» cambia tu estudio actual por el de la copia. Los estudios archivados se conservan. No se puede deshacer."
    }
}
