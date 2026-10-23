import Foundation

/// Grades entered in the demo UI, persisted locally per subject so they survive closing the app.
/// A stopgap ahead of the real SwiftData model (brief §6, not built yet) — swapping this for
/// SwiftData later only touches this file, `SubjectDetailView` just calls `load`/`save`.
enum GradeStore {
    static func load(for subjectName: String) -> [String: Double] {
        guard let data = UserDefaults.standard.data(forKey: key(for: subjectName)),
              let values = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return [:] }
        return values
    }

    static func save(_ values: [String: Double], for subjectName: String) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: key(for: subjectName))
    }

    private static func key(for subjectName: String) -> String {
        "com.migueltaibo.mark.grades.\(subjectName)"
    }
}
