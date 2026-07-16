import Foundation

/// One finished set, as stored in the `workouts` table (schema in
/// docs/HISTORY_SETUP.md). Foundation-only so it compiles in
/// Tests/run_tests.sh; all Supabase I/O lives in `HistoryStore`.
struct WorkoutRecord: Codable, Identifiable, Equatable {
    struct FaultNote: Codable, Equatable {
        let text: String
        let count: Int
    }

    let id: UUID
    /// Raw `Exercise` identifier, kept as a string so rows written by newer
    /// builds (exercises this one doesn't know) still decode and display.
    let exercise: String
    let reps: Int
    let durationSeconds: Double
    let faults: [FaultNote]
    let performedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, exercise, reps, faults
        case durationSeconds = "duration_seconds"
        case performedAt = "performed_at"
    }

    /// Sections for the history list: one per calendar day, newest day first,
    /// preserving the order of `records` within each day.
    static func daySections(
        _ records: [WorkoutRecord],
        calendar: Calendar = .current
    ) -> [(day: Date, records: [WorkoutRecord])] {
        var sections: [(day: Date, records: [WorkoutRecord])] = []
        var indexByDay: [Date: Int] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.performedAt)
            if let index = indexByDay[day] {
                sections[index].records.append(record)
            } else {
                indexByDay[day] = sections.count
                sections.append((day: day, records: [record]))
            }
        }
        return sections.sorted { $0.day > $1.day }
    }
}
