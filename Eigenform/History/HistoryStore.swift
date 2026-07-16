import Foundation
import Supabase

/// Reads and writes the signed-in user's `workouts` rows (schema in
/// docs/HISTORY_SETUP.md).
///
/// Saves are optimistic: the record appears in `records` immediately and joins
/// a UserDefaults-backed pending queue, so a set finished with no signal in
/// the gym uploads on the next save, refresh, or sign-in instead of being
/// lost. Rows are only dequeued once the server accepts them (or already has
/// them).
@MainActor
final class HistoryStore: ObservableObject {

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var records: [WorkoutRecord] = []
    @Published private(set) var phase: Phase = .idle

    private var client: SupabaseClient?
    private var isFlushing = false
    private static let pendingKey = "history.pendingSaves"

    // Codec for the local pending queue only; the wire format is the SDK's.
    private static let queueEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let queueDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func configure(client: SupabaseClient) {
        self.client = client
    }

    /// Sign-out: cached rows and unsent saves belong to the account that just
    /// left, so both are dropped rather than shown to — or uploaded as — the
    /// next one.
    func clearLocal() {
        records = []
        phase = .idle
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
    }

    /// Kick the pending queue without a UI-driven refresh (e.g. right after
    /// sign-in restores a session).
    func retryQueuedSaves() {
        Task { await flushPending() }
    }

    /// Fire-and-forget from the session flow; never blocks the summary screen.
    func save(_ summary: SessionSummary) {
        guard client != nil else { return }
        let record = WorkoutRecord(
            id: UUID(),
            exercise: summary.exercise.rawValue,
            reps: summary.reps,
            durationSeconds: summary.duration,
            faults: summary.faults.map { WorkoutRecord.FaultNote(text: $0.text, count: $0.count) },
            performedAt: Date())
        records.insert(record, at: 0)
        setPending(pending() + [record])
        Task { await flushPending() }
    }

    func refresh() async {
        guard let client else { return }
        if records.isEmpty { phase = .loading }
        await flushPending()
        do {
            let rows: [WorkoutRecord] = try await client
                .from("workouts")
                .select("id, exercise, reps, duration_seconds, faults, performed_at")
                .order("performed_at", ascending: false)
                .limit(200)
                .execute()
                .value
            // Saves still stuck in the queue haven't landed server-side yet;
            // keep them visible on top rather than letting them vanish.
            let unsent = pending().filter { queued in !rows.contains { $0.id == queued.id } }
            records = (unsent + rows).sorted { $0.performedAt > $1.performedAt }
            phase = .loaded
        } catch {
            // Keep whatever is already on screen; only surface the failure
            // when there's nothing to show instead.
            if records.isEmpty { phase = .failed(Self.friendlyMessage(for: error)) }
        }
    }

    // MARK: Pending queue

    private func flushPending() async {
        guard let client, !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        var queue = pending()
        while let record = queue.first {
            do {
                try await client.from("workouts").insert(record).execute()
            } catch let error as PostgrestError where error.code == "23505" {
                // Duplicate id: an earlier flush inserted this row but didn't
                // get to dequeue it. The server has it — fall through.
            } catch {
                // Anything else (offline, table not created yet, auth hiccup):
                // keep the row and retry on the next flush.
                break
            }
            queue.removeFirst()
            setPending(queue)
        }
    }

    private func pending() -> [WorkoutRecord] {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingKey),
              let queue = try? Self.queueDecoder.decode([WorkoutRecord].self, from: data)
        else { return [] }
        return queue
    }

    private func setPending(_ queue: [WorkoutRecord]) {
        if queue.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        } else if let data = try? Self.queueEncoder.encode(queue) {
            UserDefaults.standard.set(data, forKey: Self.pendingKey)
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("workouts"),
           text.contains("does not exist") || text.contains("schema cache") {
            return "The workouts table isn't set up yet — run the SQL in docs/HISTORY_SETUP.md."
        }
        return text
    }
}
