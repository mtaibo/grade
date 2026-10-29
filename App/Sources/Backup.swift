import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The `.grade` file: a full copy of the library (every subject with its evaluation, grades and
    /// dates) and the degree settings, as JSON.
    static let gradeBackup = UTType(exportedAs: "com.migueltaibo.grade.backup", conformingTo: .json)
}

/// What a `.grade` file holds: the library, the degree settings and any uploaded guides.
struct GradeBackup: Codable {
    static let format = "grade-backup"
    static let currentVersion = 1

    var format = Self.format
    var version = Self.currentVersion
    var exportedAt = Date.now
    var courses: [Course]
    var degree: DegreeSettings
    /// The teaching-guide PDFs, by subject id. Absent in copies made before guides existed.
    var guides: [String: Data]?
    /// The custom home-screen views. Absent in copies made before they existed.
    var selections: [CustomSelection]?

    var subjectCount: Int { courses.reduce(0) { $0 + $1.subjects.count } }
}

enum BackupError: LocalizedError {
    case notABackup
    case newerVersion
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notABackup: "Este archivo no es una copia de Grade."
        case .newerVersion: "Esta copia es de una versión más nueva de Grade. Actualiza la app para abrirla."
        case .unreadable: "No se ha podido leer el archivo."
        }
    }
}

extension GradeBackup {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = Library.fileEncoder.nonConformingFloatEncodingStrategy
        return encoder
    }

    static func decode(_ data: Data) throws -> GradeBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = Library.fileDecoder.nonConformingFloatDecodingStrategy
        guard let backup = try? decoder.decode(GradeBackup.self, from: data), [Self.format, "mark-backup"].contains(backup.format) else {
            throw BackupError.notABackup
        }
        guard backup.version <= Self.currentVersion else { throw BackupError.newerVersion }
        return backup
    }
}

/// The file handed to the share sheet. The library (with every guide PDF) is only encoded and
/// written to a temporary `.grade` when it's actually shared — never while the screen just redraws.
struct BackupFile: Transferable {
    let library: Library

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .gradeBackup) { file in
            let data = try await file.library.backupData()
            let url = URL.temporaryDirectory.appending(path: "Grade \(Date.now.formatted(.iso8601.year().month().day())).grade")
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
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

    func confirm(_ pending: Pending, into library: Library) {
        library.restore(pending.backup)
        message = "Se han importado \(pending.backup.subjectCount) asignaturas."
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
            .fileImporter(isPresented: $center.isPicking, allowedContentTypes: [.gradeBackup, .json]) { result in
                if case .success(let url) = result { center.prepare(url: url) }
            }
            .onOpenURL { center.prepare(url: $0) }
            .confirmationDialog(
                "¿Importar esta copia?",
                isPresented: Binding(get: { center.pending != nil }, set: { if !$0 { center.pending = nil } }),
                titleVisibility: .visible,
                presenting: center.pending
            ) { pending in
                Button("Sustituir lo que tengo", role: .destructive) { center.confirm(pending, into: library) }
            } message: { pending in
                Text("La copia tiene \(pending.backup.subjectCount) asignaturas. Todo lo que hay ahora en la app se sustituye por ello. No se puede deshacer.")
            }
            .alert("Copia de seguridad", isPresented: Binding(get: { center.message != nil }, set: { if !$0 { center.message = nil } })) {
                Button("Vale") {}
            } message: {
                Text(center.message ?? "")
            }
    }
}
