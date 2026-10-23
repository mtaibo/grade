import Foundation

/// A grade as the user typed it: `value` out of `outOf`, not necessarily the leaf's own scale —
/// e.g. a teacher grades out of 2 while the model's leaf is out of 10, and the user shouldn't have
/// to multiply by 5 themselves. `SubjectDetailView` converts to the leaf's scale for the engine.
struct GradeEntry: Codable, Equatable {
    var value: Double
    var outOf: Double
}

/// Grades entered in the demo UI, persisted locally per subject so they survive closing the app.
/// A stopgap ahead of the real SwiftData model (brief §6, not built yet) — swapping this for
/// SwiftData later only touches this file, `SubjectDetailView` just calls `load`/`save`.
enum GradeStore {
    static func load(for subjectName: String) -> [String: GradeEntry] {
        guard let data = UserDefaults.standard.data(forKey: key(for: subjectName)),
              let entries = try? JSONDecoder().decode([String: GradeEntry].self, from: data)
        else { return [:] }
        return entries
    }

    static func save(_ entries: [String: GradeEntry], for subjectName: String) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key(for: subjectName))
    }

    private static func key(for subjectName: String) -> String {
        "com.migueltaibo.mark.grades.\(subjectName)"
    }
}
