import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// The `.grade` file: a full copy of the library (every subject with its evaluation, grades and
    /// dates) and the degree settings, as JSON.
    static let gradeBackup = UTType(exportedAs: "com.migueltaibo.grade.backup", conformingTo: .json)
    /// The `.mark` file exported before the app was renamed: same contents, still importable.
    static let markBackup = UTType(importedAs: "com.migueltaibo.mark.backup", conformingTo: .json)
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
    /// `false` when the copy was made without grades. Absent (with grades) in older copies.
    var includesGrades: Bool?
    /// What part of the degree the copy holds ("1º Año"), `nil` when it holds everything.
    var scope: String?
    /// Archived studies, only in a full copy that asked for them.
    var archives: [ArchivedStudy]?

    var subjectCount: Int { courses.reduce(0) { $0 + $1.subjects.count } }
}

/// The part of the degree an export or a delete works on.
enum DataScope: Hashable, Sendable {
    case all
    case year(Int)
    /// A degree-wide term number.
    case term(Int)

    func contains(_ record: SubjectRecord, year: Int) -> Bool {
        switch self {
        case .all: true
        case .year(let wanted): year == wanted
        case .term(let wanted): record.term == wanted
        }
    }

    func title(in degree: DegreeSettings) -> String {
        switch self {
        case .all: "Todo el estudio"
        case .year(let year): degree.yearLabel(year)
        case .term(let term):
            "\(degree.yearLabel((term - 1) / max(degree.termsPerYear, 1) + 1)) · \(degree.termLabel(term))"
        }
    }
}

/// What goes into an exported `.grade` file.
struct BackupOptions: Equatable, Sendable {
    var scope = DataScope.all
    var includesGrades = true
    var includesGuides = true
    var includesViews = true
    /// Archived studies left out; every one goes in otherwise. Only with the whole study in scope.
    var excludedArchives: Set<ArchivedStudy.ID> = []
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

extension GradeBackup {
    /// Encodes the copy and writes it to a temporary `.grade`, off the main thread: with every
    /// guide PDF inside it can take a few seconds, and the screen keeps a spinner going meanwhile.
    ///
    /// Each export gets a folder of its own, and the previous ones are only cleared here, at the
    /// next export: writing over the same path while Files was still copying the last one (when
    /// it asks to replace an existing copy) left the save hanging or replaced with the wrong file.
    func writeTemporaryFile(named name: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let data = try GradeBackup.encoder.encode(self)
            let exports = URL.temporaryDirectory.appending(path: "Exports")
            try? FileManager.default.removeItem(at: exports)
            let folder = exports.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: name)
            try data.write(to: url)
            return url
        }.value
    }
}
