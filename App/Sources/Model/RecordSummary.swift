import Engine
import Foundation

/// The record's numbers, worked out once per redraw: each subject's progress, and averages over
/// the subjects whose grades are all in, weighted by credits when the study uses them — one still in progress has no final grade
/// yet to average (§2).
struct RecordSummary {
    let progress: [SubjectRecord.ID: SubjectProgress]
    let subjects: [SubjectRecord]
    let usesCredits: Bool
    let rounding: GradeRounding

    init(_ courses: [Course], degree: DegreeSettings) {
        subjects = courses.flatMap(\.subjects)
        usesCredits = degree.usesCredits
        rounding = degree.rounding
        progress = Dictionary(subjects.map { ($0.id, SubjectProgress($0, rounding: degree.rounding)) }) { first, _ in first }
    }

    func progress(of record: SubjectRecord) -> SubjectProgress {
        progress[record.id] ?? SubjectProgress(record, rounding: rounding)
    }

    private func completed(_ records: [SubjectRecord]) -> [SubjectRecord] {
        records.filter { progress(of: $0).isComplete }
    }

    func average(of records: [SubjectRecord]) -> Double? {
        let done = completed(records)
        let weight = { (record: SubjectRecord) in usesCredits ? record.subject.ectsCredits : 1 }
        let total = done.reduce(0) { $0 + weight($1) }
        guard total > 0 else { return nil }
        return done.reduce(0) { $0 + progress(of: $1).worst * weight($1) } / total
    }

    var average: Double? { average(of: subjects) }

    var passed: [SubjectRecord] {
        completed(subjects).filter { progress(of: $0).status == .guaranteed }
    }

    var passedCredits: Double { passed.reduce(0) { $0 + $1.subject.ectsCredits } }
    var totalCredits: Double { subjects.reduce(0) { $0 + $1.subject.ectsCredits } }

    static func format(_ average: Double?) -> String {
        average?.formatted(.number.precision(.fractionLength(2))) ?? "—"
    }
}
