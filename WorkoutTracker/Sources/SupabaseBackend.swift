import Foundation

/// Persistence backend for workouts. WorkoutStore talks to this; the app
/// wires in Supabase, tests wire in a mock.
protocol WorkoutBackend: Sendable {
    func fetchWorkouts() async throws -> [Workout]
    func insert(_ workout: Workout) async throws
    func update(_ workout: Workout) async throws
    func delete(id: UUID) async throws
    func deleteAll() async throws
}

/// Minimal transport seam so the backend can be tested without a network.
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.notHTTP
        }
        return (data, http)
    }
}

enum SupabaseConfig {
    static let url = URL(string: "https://dytsryksedogxymdgdue.supabase.co")!
    // The anon key is public by design; the workouts table is guarded by RLS.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR5dHNyeWtzZWRvZ3h5bWRnZHVlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5Mjc3NDcsImV4cCI6MjEwMjUwMzc0N30.lgRc938yeLKGESbYAMuw1M0g8fxcjmlEylTxgcNOic8"
}

enum SupabaseError: Error, Equatable, LocalizedError {
    case notHTTP
    case badStatus(code: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .notHTTP:
            return "Response was not HTTP"
        case .badStatus(let code, let body):
            return "Supabase returned \(code): \(body)"
        }
    }
}

struct SupabaseBackend: WorkoutBackend {
    let baseURL: URL
    let anonKey: String
    let transport: HTTPTransport

    init(baseURL: URL = SupabaseConfig.url,
         anonKey: String = SupabaseConfig.anonKey,
         transport: HTTPTransport = URLSession.shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.transport = transport
    }

    // Postgres timestamptz comes back with fractional seconds; what we send
    // may not have them, so accept both when decoding.
    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plainFormatter = ISO8601DateFormatter()

    static func parseDate(_ string: String) throws -> Date {
        if let date = fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string) {
            return date
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: [], debugDescription: "Unparseable date: \(string)"))
    }

    nonisolated(unsafe) private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            return try parseDate(string)
        }
        return d
    }()

    nonisolated(unsafe) private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalFormatter.string(from: date))
        }
        return e
    }()

    private func request(path: String, query: String? = nil, method: String,
                         body: Data? = nil) -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/\(path)"),
            resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw SupabaseError.badStatus(
                code: response.statusCode,
                body: String(decoding: data, as: UTF8.self))
        }
        return data
    }

    func fetchWorkouts() async throws -> [Workout] {
        let data = try await send(request(
            path: "workouts", query: "select=*&order=date.asc", method: "GET"))
        return try Self.decoder.decode([Workout].self, from: data)
    }

    func insert(_ workout: Workout) async throws {
        try await send(request(
            path: "workouts", method: "POST",
            body: try Self.encoder.encode(workout)))
    }

    func update(_ workout: Workout) async throws {
        try await send(request(
            path: "workouts", query: "id=eq.\(workout.id.uuidString)",
            method: "PATCH", body: try Self.encoder.encode(workout)))
    }

    func delete(id: UUID) async throws {
        try await send(request(
            path: "workouts", query: "id=eq.\(id.uuidString)", method: "DELETE"))
    }

    func deleteAll() async throws {
        try await send(request(
            path: "workouts", query: "id=not.is.null", method: "DELETE"))
    }
}

extension SupabaseBackend: CompletionBackend {
    func fetchCompletions() async throws -> [SetCompletion] {
        let data = try await send(request(
            path: "set_completions", query: "select=day_id,entry_index",
            method: "GET"))
        return try JSONDecoder().decode([SetCompletion].self, from: data)
    }

    func insert(_ completion: SetCompletion) async throws {
        try await send(request(
            path: "set_completions", method: "POST",
            body: try JSONEncoder().encode(completion)))
    }

    func delete(_ completion: SetCompletion) async throws {
        try await send(request(
            path: "set_completions",
            query: "day_id=eq.\(completion.dayId)&entry_index=eq.\(completion.entryIndex)",
            method: "DELETE"))
    }
}
